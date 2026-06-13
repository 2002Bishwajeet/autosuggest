# Native-fidelity inline suggestions — design

- **Date:** 2026-06-13
- **Status:** Approved design (pre-implementation)
- **Author:** Brainstormed with Claude; approved by maintainer
- **Supersedes:** the parked "AX inline-injection spike (option 3)" follow-up

## Context & motivation

The user wants inline suggestions that look like Apple's native inline
predictions ("ghost text" at the caret), in as many apps as possible. A
reverse-engineering spike (2026-06-13, macOS 26.5.1) investigated whether a
third party can **drive Apple's own inline-prediction renderer** with our text
in arbitrary apps. The verdict, confirmed by three independent adversarial
lenses (input-method, private-XPC/AX, code-injection), is **infeasible**:

- Apple renders inline predictions **in-process**, inside the foreground app's
  own `NSTextView` (TextKit2 / `NSTextLayoutManager`). The render entry points
  (`-[NSSpellChecker showInlinePredictionForCandidates:client:]` and the private
  `_showInlinePredictionFor…:view:client:…`) take the destination as **`view:`
  (NSTextView) and `client:` (NSTextInputClient) — live in-process objects**.
  There is no system-wide overlay window for predictions.
- No public/private API yields a **foreign** app's `NSTextInputClient`/`NSView`;
  Accessibility only returns an opaque `AXUIElementRef` proxy. Driving the
  renderer cross-process would require **code injection**, blocked by Hardened
  Runtime + Library Validation + SIP (and `/Library/InputManagers` is gone on
  macOS 26).
- The contextual prediction **feed** (`suggestd` /
  `com.apple.proactive.input.suggester` in `CoreSuggestions.framework`, backed by
  an on-device transformer in `TextInput`'s `TIInlineCompletionGenerator`)
  requires `com.apple.private.suggestions.*` entitlements no third party can
  mint.
- An InputMethodKit IME can only place **marked text**, styled by the *client*
  (no way to force dim/no-underline), hijacks the whole keyboard, and fails in
  Electron/terminals.
- Every shipping competitor (GhostType, Cotypist, Cotabby, Typeahead, KeyType)
  uses the **same architecture AutoSuggest already has**: AX reads field + caret
  → draw your **own** overlay ghost text → AX-insert the accepted completion.

**Reachable wins the spike surfaced (public, no private entitlement):**

- **`FoundationModels.framework` (macOS 26)** — Apple's on-device Apple
  Intelligence LLM. `SystemLanguageModel` + `LanguageModelSession`. Gives
  Apple-grade, fully on-device completions we render ourselves, with **no model
  download and no localhost server** (eliminates the recurring -1011 / "Ollama
  not running" friction). Gated only at runtime by `SystemLanguageModel.availability`.
- `NSSpellChecker.completionsForPartialWordRange:…` — public, Lexicon-backed
  word/phrase completions (a cheap complementary tier; not in scope for v1).

**Therefore** this work keeps our own renderer and invests in the two layers
that actually move the needle: a better completion **source** and a more
**native-looking** overlay.

## Goals

1. Add Apple's on-device LLM as a first-class completion source that "just
   works" for eligible users, with graceful fallback to the existing chain.
2. Make the existing inline ghost-text overlay read as native: correct font,
   baseline, and color at the caret, with double-ghosting avoided.

## Non-goals

- Driving / reusing Apple's native inline-prediction renderer (proven
  infeasible).
- Becoming an Input Method.
- Streaming token-by-token ghost text (clean follow-up after single-shot lands).
- A dedicated FoundationModels settings panel (a status row suffices for v1).

## Architecture overview

Two **independent** layers, shipped as **two PRs**:

- **Layer A — FoundationModels runtime** (inference/model layer only).
- **Layer B — Overlay fidelity** (context + rendering layer only).

They share no files and can be implemented/reviewed in parallel. Both must end
with `swift build` green, the full `swift test` suite green (add tests, never
weaken existing ones), and `swiftformat Sources Tests --lint` reporting 0 files.

---

## Layer A — FoundationModels completion runtime

### A1. New runtime type

`Sources/AutoSuggestApp/Inference/FoundationModelsInferenceRuntime.swift`,
conforming to `InferenceRuntime`:

```
protocol InferenceRuntime {
    @MainActor var name: String { get }                                  // "foundationmodels"
    @MainActor func isAvailable() async -> Bool
    @MainActor func generateSuggestion(context: String) async throws -> Suggestion
}
```

**SDK + OS gating** (package min-deploy stays macOS 13; CI/older toolchains must
still build):

- Wrap the FoundationModels import and the concrete type in
  `#if canImport(FoundationModels)` and annotate the type
  `@available(macOS 26.0, *)`.
- `InferenceRuntimeFactory` registers it only inside
  `if #available(macOS 26.0, *)` (and `#if canImport(FoundationModels)`).

### A2. `isAvailable()`

Return `true` iff `SystemLanguageModel.default.availability == .available`. On
`.unavailable(.deviceNotEligible)`, `.appleIntelligenceNotEnabled`, or
`.modelNotReady`, return `false`. `InferenceEngine`'s existing 15s TTL
availability cache (`isAvailableCached`) then transparently falls through to the
next runtime. **This is the mechanism that removes the -1011 friction** for
eligible users while non-eligible users are unaffected.

### A3. `generateSuggestion(context:)`

- Build a `LanguageModelSession` with terse instructions: produce **only** the
  continuation of the user's text — no preamble, no quotes, no explanation.
- `respond(to:options:)` with
  `GenerationOptions(sampling: .greedy, maximumResponseTokens: ≈24)` (short
  continuation; matches the CoreML runtime's 24-token budget).
- **Context budgeting:** the FoundationModels context window is ~4096 tokens
  (prompt + response). Truncate the incoming `context` to a safe prefix budget
  before prompting (reuse/extend whatever truncation the pipeline already
  applies; otherwise a conservative char-based heuristic).
- **Error handling:** catch `LanguageModelSession.GenerationError` (e.g.
  guardrail refusals, context overflow) and **return an empty `Suggestion`** so
  `InferenceEngine.suggest` falls through cleanly (it already treats an empty
  completion as "try the next runtime"). Because `isAvailable()` gates entry,
  `generateSuggestion` failures are generation/runtime errors → return empty.
- **v1 latency:** create a fresh session per request (simple, stateless —
  avoids transcript growth). A `prewarm()`-ed warm session is an explicit
  follow-up optimization, not v1.
- **Privacy:** on-device, no network; **never log the prompt or completion**
  (existing invariant). Use `Logger(scope:)` for non-content diagnostics only.

### A4. Testability seam

FoundationModels types can't run on CI or macOS < 26. Mirror the CoreML fix:
introduce a small protocol, e.g.

```
@MainActor protocol FoundationModelResponding {
    func respond(toPrompt: String, maxTokens: Int) async throws -> String
    var isModelAvailable: Bool { get }
}
```

The runtime depends on the protocol; the real conformer wraps
`LanguageModelSession` behind the availability gate. Unit tests inject a mock to
exercise: token-cap handling, error→empty mapping, truncation, and
`isAvailable()` for each availability state — all without the SDK.

### A5. Factory + config

`InferenceRuntimeFactory.makeRuntimes` (currently default order
`["coreml","ollama","llama.cpp"]`):

- Add `case "foundationmodels"` (also accept `"foundation-models"`,
  `"applellm"` as aliases → canonicalize). Register only when available
  (SDK + OS + `foundationModelsEnabled`).
- New default order: `["foundationmodels","coreml","ollama","llama.cpp"]`.
- Add `LocalModelConfig.foundationModelsEnabled: Bool` (default `true`) so a user
  can disable it.

### A6. Config migration (`ConfigMigrationManager`)

Migrations gate on `config.configVersion` vs `AppConfig.currentConfigVersion`.

- Bump `AppConfig.currentConfigVersion`.
- New step: if `config.runtimeOrder` **equals a known prior default**
  (`["coreml","ollama","llama.cpp"]` or any earlier default), **prepend**
  `"foundationmodels"`. If the user has a **customized** order, only prepend
  `"foundationmodels"` when absent — **never reorder or clobber** their choice.
- Set `foundationModelsEnabled = true` for migrated configs.
- **Idempotent** (running twice adds nothing); **must preserve v0/v1 configs**.

### A7. UI (minimal)

In `ModelsSettingsView`, add a runtime status row for FoundationModels using the
new `RuntimeDisplayName` helper ("Apple Intelligence"): show
available / "Not available on this device" / "Apple Intelligence not enabled",
derived from `SystemLanguageModel.availability`. The full dedicated panel
(Models P2-style) stays deferred.

> **Cross-PR dependency:** the `RuntimeDisplayName` helper is introduced in the
> UI polish PR (#9, branch `ui-polish-theming`). Layer A's UI row should land
> after #9 merges, or define a local fallback name if implemented first.

### A8. Tests (Layer A)

- Factory: registers FoundationModels first when available + flag on; omitted
  when flag off; omitted (no crash) when unavailable.
- Migration: prepends to old-default order; leaves a customized order untouched
  except for appending when absent; idempotent; v0/v1 still migrate.
- Runtime (via mock `FoundationModelResponding`): empty-on-error,
  token-cap, truncation, `isAvailable()` per availability state.

### A9. Risks / mitigations (Layer A)

- **Availability gating** (eligibility / Apple Intelligence off / model not
  ready): handled by fall-through; non-eligible users keep today's behavior.
- **Guardrail false-refusals on benign text:** return empty → fall through.
- **Context budget (4096):** truncate input defensively.
- **`rateLimited` under rapid keystrokes:** the orchestrator already debounces
  (~150ms) and cancels stale requests; treat rate-limit as empty → fall through.
- **macOS 26-only:** fully gated; older OSes never see it.

---

## Layer B — Overlay fidelity polish

Files: `Sources/AutoSuggestApp/Suggestions/FloatingOverlayRenderer.swift`,
`Sources/AutoSuggestApp/Context/AXTextContextProvider.swift`,
`Sources/AutoSuggestApp/Context/TextContextProvider.swift` (the context struct),
and `Sources/AutoSuggestApp/Suggestions/TypingPipeline.swift` (wiring). Today the
renderer guesses font size from caret height; caret geometry already comes from
AX `AXBoundsForRange`.

### B1. Real font instead of a guess

Read the focused field's font from AX: request `AXAttributedStringForRange`
(parameterized attribute) over the caret/selection range and read the
`.font`/`kCTFontAttributeName` attribute. Carry font family + point size on the
context struct (e.g. `caretFont: NSFont?`) → `TypingPipeline` →
`showSuggestion`. Fall back to the existing caret-height heuristic only when AX
exposes no font.

### B2. Baseline alignment

Position the ghost text so its **baseline** matches the line, using the caret
rect plus font ascender/descender, rather than aligning to `caret.minY`.
Implement as a **pure layout function** `(caretRect, font) -> NSRect` for
testability.

### B3. Dim-grey color match

Validate the ghost color against Apple's native inline prediction grey. Current
`placeholderTextColor` is close; evaluate `tertiaryLabelColor`. Keep it a single
named constant in `DesignSystem`/the renderer so it's one-line tunable.

### B4. Tab-to-accept

Already wired: `CGEventShortcutMonitor.acceptKeyCodes = [48, 36, 76]`
(Tab/Return/Enter), user-configurable via `updateKeyCodes`. Confirm behavior and
document; no functional change expected.

### B5. Double-ghost suppression *(highest-risk item)*

When the focused field is **already** showing Apple's native inline prediction,
suppress ours to avoid two overlapping ghosts.

- **Primary:** best-effort AX read of the completion markup the spike found
  readable on the focused element (`AXIsSuggestion` / `AXCompletionText` family).
  If an active suggestion is detected, do not show our overlay for that keystroke.
- **Backstop:** a per-app exclusion (the existing exclusions mechanism) for apps
  where detection is unreliable but native predictions are known-on.
- If detection proves flaky in practice, **ship the per-app exclusion only** and
  log (content-free) when detection was attempted. Do not block the rest of
  Layer B on B5.

### B6. Electron / Chromium AX coverage

Many Electron apps hide AX text until enabled. On detecting a Chromium-class
focused app, set `AXManualAccessibility` (and/or `AXEnhancedUserInterface`) =
true on the application element to unlock AX text. Document the
`--force-renderer-accessibility=complete` launch flag for apps that still refuse.
Keep current behavior (no overlay) when AX yields nothing — no regressions.

### B7. Tests (Layer B)

- Font extraction from a **mock** AX attributed string (font present / absent).
- Baseline-layout pure function given caret rect + font metrics.
- Suppression decision pure function given a "native completion present" flag.

### B8. Risks / mitigations (Layer B)

- **B5 detection unreliable:** scoped as best-effort with a per-app backstop; not
  a blocker for B1–B4/B6.
- **AX font missing in some apps:** graceful fallback to the height heuristic.
- **Electron AX toggling side effects:** apply narrowly (Chromium apps), keep the
  "no overlay when AX empty" safety.

---

## Cross-cutting constraints

- **Privacy invariants:** no raw typed text or completions logged or persisted;
  FoundationModels is on-device. PII-filter before any persistence
  (`PIIFilter`); telemetry stays content-free.
- **Policy / secure-field:** untouched; suggestions must never fire in secure
  fields (`PolicyEngine`, `AXTextContextProvider`).
- **Migrations:** never break existing v0/v1 configs.
- **Conventions:** `Logger(scope:)` not `print`; tests mirror source names with
  `@testable import AutoSuggestApp`; UI strings hardcoded English (no l10n
  layer).

## Verification gates (both layers)

- `swift build` exit 0
- `swift test` — full suite green, plus the new tests above
- `swiftformat Sources Tests --lint` — 0 files require formatting
- Layer B: manual visual confirmation in the Xcode app target (font/baseline
  match in TextEdit/Notes/Safari, Light + Dark; double-ghost suppression in a
  native field with Apple inline predictions on).

## Sequencing

1. **PR 1 — Layer A (FoundationModels runtime).** Highest ROI; independent.
2. **PR 2 — Layer B (overlay fidelity).** Independent; B5 may degrade to the
   per-app backstop without blocking B1–B4/B6.

Each gets its own implementation plan via the writing-plans flow.

## Open questions

- **B3 exact color:** confirm `placeholderTextColor` vs `tertiaryLabelColor`
  against Apple's native grey during implementation (cheap to tune).
- **B5 detection reliability:** to be validated empirically; backstop defined.

## References

- RE spike artifacts: workflow `inline-prediction-re-spike` (run
  `wf_6efbf8a0-6d8`); full result at the task output for `wv3ok6elh`.
- Key symbols: `NSTextView.allowsInlinePredictions` / `inlinePredictionType`
  (public on/off trait); `showInlinePredictionForCandidates:client:`;
  `SystemLanguageModel` / `LanguageModelSession` (FoundationModels);
  `AXBoundsForRange`, `AXAttributedStringForRange`, `AXIsSuggestion` /
  `AXCompletionText` (AX).
- Code anchors: `InferenceRuntime.swift`, `InferenceRuntimeFactory.swift`
  (default order line 14), `ConfigMigrationManager.swift`, `AppConfig.swift`
  (`currentConfigVersion`), `FloatingOverlayRenderer.swift`,
  `AXTextContextProvider.extractCaretRect`, `TypingPipeline.swift` (lines
  137–138), `CGEventShortcutMonitor.swift` (accept key codes).
