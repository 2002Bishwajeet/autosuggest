# Plan 005: Fix overlay contrast and animation race; make runtime-down state actionable

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat f2dae47..HEAD -- Sources/AutoSuggestApp/Suggestions/FloatingOverlayRenderer.swift Sources/AutoSuggestApp/UI/AutoSuggestViews.swift Sources/AutoSuggestApp/UI/AutoSuggestUIModel.swift Sources/AutoSuggestApp/App/AppCoordinator.swift`
> If excerpts below don't match the live code, STOP.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none (independent of plans 001–004)
- **Category**: bug / dx-ux
- **Planned at**: commit `f2dae47`, 2026-06-11

## Why this matters

The floating suggestion overlay is the entire visible product, and it renders its text in `tertiaryLabelColor` — borderline-illegible on the HUD material, worse in dark mode. A hide/show animation race can also leave a freshly shown suggestion invisible: re-showing during the 0.12s fade-out skips the fade-in (panel still "visible") while the pending completion handler orders the panel out anyway. Finally, when no runtime is ready, the status popover says "No local runtime is ready" with no hint of what to do — the most common new-user failure mode (Ollama not started) reads as "the app is broken".

## Current state

- `Sources/AutoSuggestApp/Suggestions/FloatingOverlayRenderer.swift` — `@MainActor` class:

  ```swift
  // :11-25
  func showSuggestion(_ text: String, caretRectInScreen: CGRect?) {
      ensurePanel()
      guard let panel, let textField else { return }
      textField.stringValue = text
      layoutPanel(panel: panel, textField: textField, text: text, caretRectInScreen: caretRectInScreen)
      if !panel.isVisible {
          panel.alphaValue = 0
          panel.orderFrontRegardless()
          NSAnimationContext.runAnimationGroup { context in
              context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.14
              panel.animator().alphaValue = 1
          }
      }
  }

  // :27-37
  func hideSuggestion() {
      guard let panel, panel.isVisible else { return }
      NSAnimationContext.runAnimationGroup { context in
          context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12
          panel.animator().alphaValue = 0
      } completionHandler: {
          DispatchQueue.main.async {
              panel.orderOut(nil)
          }
      }
  }

  // :66-68
  let textField = NSTextField(labelWithString: "")
  textField.textColor = NSColor.tertiaryLabelColor
  ```

  The race: `hideSuggestion()` starts the fade; `showSuggestion()` arrives 50ms later — `panel.isVisible` is still true, so it only swaps the text (alpha keeps animating to 0); then the completion handler fires `orderOut`. Result: active suggestion, invisible panel, until the next full hide→show cycle.

- `Sources/AutoSuggestApp/App/AppCoordinator.swift:818-836` — `derivePauseReason(...)` returns strings including `"No local runtime is ready"` (line 833) and the permissions summary (line 827).
- `Sources/AutoSuggestApp/UI/AutoSuggestUIModel.swift:101` — `var pauseReason: String?` inside the quick-panel state struct (around lines 95-110; read the surrounding struct before editing).
- `Sources/AutoSuggestApp/UI/AutoSuggestViews.swift:32-35` — display site:

  ```swift
  if let pauseReason = uiModel.quickPanelState.pauseReason {
      ...
      Label(pauseReason, systemImage: "pause.circle")
  ```

- The UI model already supports banners: `AutoSuggestUIModel.swift:342 func showBanner(kind:title:message:)` — do not duplicate that mechanism.

## Commands you will need

| Purpose   | Command       | Expected on success |
|-----------|---------------|---------------------|
| Build     | `swift build` | exit 0              |
| Tests     | `swift test`  | all pass            |

## Scope

**In scope** (the only files you should modify):
- `Sources/AutoSuggestApp/Suggestions/FloatingOverlayRenderer.swift`
- `Sources/AutoSuggestApp/App/AppCoordinator.swift` (pause remedy derivation only)
- `Sources/AutoSuggestApp/UI/AutoSuggestUIModel.swift` (one new state field)
- `Sources/AutoSuggestApp/UI/AutoSuggestViews.swift` (display the remedy)
- `Tests/AutoSuggestAppTests/AutoSuggestUIModelTests.swift` (extend)
- `plans/README.md` (status row)

**Out of scope** (do NOT touch, even though they look related):
- Overlay positioning/fallback-anchor logic (lines 84-131) — works; degraded-mode visual cues are deferred.
- `StatusBarController` icon rendering.
- Onboarding flow (`OnboardingFlowView.swift`) — separate concern.
- A clickable "Retry" button wired to runtime re-checks — needs plan 004's `invalidateAvailabilityCache()`; deferred (see Maintenance notes).

## Git workflow

- Branch: `advisor/005-overlay-status-ux`
- Commit per step; message style: short imperative summary.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Overlay text contrast

In `FloatingOverlayRenderer.swift:67`, change `NSColor.tertiaryLabelColor` → `NSColor.secondaryLabelColor`. (Keeps the "ghost text" affordance while clearing the legibility floor on `.hudWindow` material in both appearances. Do not use `.labelColor` — the suggestion must remain visually distinct from typed text.)

**Verify**: `grep -n "tertiaryLabelColor" Sources/AutoSuggestApp/Suggestions/FloatingOverlayRenderer.swift` → no matches.

### Step 2: Fix the hide/show race with a generation counter

In `FloatingOverlayRenderer`:
- Add `private var hideGeneration = 0`.
- In `showSuggestion`, after the guard: `hideGeneration += 1`, and make the alpha recovery unconditional — if the panel is already visible (mid-fade-out), animate alpha back to 1 instead of skipping:

  ```swift
  hideGeneration += 1
  if !panel.isVisible {
      panel.alphaValue = 0
      panel.orderFrontRegardless()
  }
  NSAnimationContext.runAnimationGroup { context in
      context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.14
      panel.animator().alphaValue = 1
  }
  ```

- In `hideSuggestion`, capture the generation and bail in the completion if superseded (hop back to the main actor explicitly — the class is `@MainActor` but the completion closure is not):

  ```swift
  hideGeneration += 1
  let generation = hideGeneration
  NSAnimationContext.runAnimationGroup { context in
      context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12
      panel.animator().alphaValue = 0
  } completionHandler: {
      DispatchQueue.main.async { [weak self] in
          guard let self, self.hideGeneration == generation else { return }
          self.panel?.orderOut(nil)
      }
  }
  ```

  If Swift 6 strict concurrency rejects `self` capture in the completion handler, use `MainActor.assumeIsolated` inside the `DispatchQueue.main.async` block — do not weaken the class's actor isolation.

**Verify**: `swift build` → exit 0.

### Step 3: Add a pause remedy to the UI state

- In `AutoSuggestUIModel.swift`, next to `pauseReason` (line ~101), add `var pauseRemedy: String?` and thread it through the same initializer/default (`nil`) as `pauseReason` (line ~107).
- In `AppCoordinator.swift`, locate where `derivePauseReason`'s result is assigned into the quick-panel state (grep `pauseReason:` in the file). Add a sibling `derivePauseRemedy` that maps the same conditions to action hints, and assign it:
  - permissions not ready → `"Open System Settings → Privacy & Security → Accessibility / Input Monitoring, then relaunch AutoSuggest."`
  - low-power pause → `"Suggestions resume automatically when Low Power Mode turns off."`
  - no runtime ready → `"Start Ollama (`ollama serve`) or install a model via Model Source Settings…"`
  - manual pause → nil (the reason already contains the resume time).

  Structure it as one function returning `(reason: String?, remedy: String?)` or two parallel functions — match whichever shape touches fewer call sites; do not restructure the surrounding state-building code.
- In `AutoSuggestViews.swift` (the `pauseReason` display at lines ~32-35), under the existing `Label`, render the remedy when present as secondary text:

  ```swift
  if let remedy = uiModel.quickPanelState.pauseRemedy {
      Text(remedy)
          .font(.caption)
          .foregroundStyle(.secondary)
  }
  ```

  Match the indentation/styling idiom of the surrounding view code (it uses `Label`/`Text` with design-system styles — mirror the adjacent rows).

**Verify**: `swift build` → exit 0.

### Step 4: Tests

Extend `Tests/AutoSuggestAppTests/AutoSuggestUIModelTests.swift` (follow its existing style):
- Quick-panel state with a runtime-down `pauseReason` carries the expected `pauseRemedy` (construct the state the way existing tests do; if remedy derivation lives in `AppCoordinator` and isn't reachable from tests, make `derivePauseRemedy` an internal static pure function and test it directly).
- `pauseReason == nil` → `pauseRemedy == nil`.

**Verify**: `swift test` → exit 0, all pass including the new tests.

### Step 5: Manual smoke test (only if you can run a GUI)

Run the app, type to get a suggestion, then rapidly type-pause-type to force hide→show within ~100ms. The suggestion must stay visible. Quit Ollama (if running) and confirm the popover shows the remedy line. If you cannot run a GUI, state that this step was skipped.

## Test plan

See step 4 — two new tests in `AutoSuggestUIModelTests.swift`. The overlay race fix is not unit-testable headlessly (NSPanel/animation); covered by the smoke test + reviewer scrutiny.

## Done criteria

- [ ] `swift test` exits 0
- [ ] `grep -rn "tertiaryLabelColor" Sources/` → no matches
- [ ] `hideGeneration` guard present in `FloatingOverlayRenderer.hideSuggestion`'s completion
- [ ] `pauseRemedy` exists in the UI model and is rendered in `AutoSuggestViews.swift`
- [ ] No files outside the in-scope list are modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:
- The quick-panel state struct in `AutoSuggestUIModel.swift` is constructed in more than 3 places (the new field would fan out too far — report the construction sites).
- Swift 6 isolation errors in the animation completion can't be solved with `MainActor.assumeIsolated`.
- `derivePauseReason` has been restructured since `f2dae47`.

## Maintenance notes

- After plan 004 lands, add a "Check again" button next to the remedy that calls `InferenceEngine.invalidateAvailabilityCache()` and refreshes health — deferred from this plan to avoid a cross-plan dependency.
- Reviewer should scrutinize: the generation-counter logic under rapid show/hide/show/hide interleavings, and remedy copy tone (it's user-facing).
- Localization: the remedy strings are user-facing English literals, consistent with current code (`Localizable.strings` exists but UI strings are mostly hardcoded — a known repo-wide gap, tracked in `plans/README.md` rejected/deferred section).
