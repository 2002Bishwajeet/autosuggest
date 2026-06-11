# Plan 009: BYOK ship spike — validate, harden, and scope Online LLM for v0.2

> **Executor instructions**: This is a **spike**, not a build-everything plan.
> The deliverables are (a) one small hardening diff with tests, and (b) a
> written ship-readiness report at `docs/BYOK_SHIP_PLAN.md`. Follow the steps,
> honor STOP conditions, and update `plans/README.md` when done.
>
> **Drift check (run first)**: `git diff --stat f2dae47..HEAD -- Sources/AutoSuggestApp/Inference/OnlineLLMInferenceRuntime.swift Sources/AutoSuggestApp/Inference/InferenceRuntimeFactory.swift Sources/AutoSuggestApp/Config/AppConfig.swift`
> Plan 002 truncates one error-body string in OnlineLLMInferenceRuntime —
> expected. Plan 004 makes `isAvailable` async — expected. Other structural
> mismatches are STOP conditions.

## Status

- **Priority**: P3 (post-launch / v0.2)
- **Effort**: M (spike) — full ship is L, scoped by this spike's output
- **Risk**: LOW (spike itself); MED for the eventual ship
- **Depends on**: plans/002 (don't ship BYOK while completions leak to logs); plan 008 recommended first (launch before expanding scope)
- **Category**: direction
- **Planned at**: commit `f2dae47`, 2026-06-11

## Why this matters

Online LLM (BYOK) is ~85% built and intentionally shipped disabled: the runtime implements OpenAI-compatible, OpenRouter, and Anthropic protocols (`Inference/OnlineLLMInferenceRuntime.swift`, 155 lines); config, keychain storage, migration scaffolding, settings UI (`UI/AutoSuggestViews.swift:573-626`), and tests (`Tests/AutoSuggestAppTests/OnlineLLMInferenceRuntimeTests.swift`) all exist. The checklist (`checklist.md:67`) lists it as the last post-MVP feature. It unblocks users on weak hardware and is the most-requested capability class for tools like this. But it must not ship as-is: the runtime sends the user's typed context plus the API key to **whatever endpoint URL is configured, over any scheme** — and the error/UX path for live API failures has never been validated. This spike hardens the endpoint boundary now (cheap, safe even while disabled) and produces a concrete v0.2 ship plan.

## Current state

- `Sources/AutoSuggestApp/Inference/OnlineLLMInferenceRuntime.swift`:

  ```swift
  // :13-18 — endpoint accepted as-is, no scheme/host validation
  init(provider: OnlineLLMProvider, model: String, endpointURL: String?, apiKey: String) {
      ...
      self.endpointURL = (endpointURL?.isEmpty ?? true) ? provider.defaultEndpoint : endpointURL!
      self.apiKey = apiKey
  }
  // :47 — key goes out as a Bearer header to that URL
  request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
  ```

  Error mapping exists and is good: `checkHTTPStatus` (lines 141-154) maps 401 → `InferenceError.invalidAPIKey`, 429 → `.rateLimited(retryAfterSeconds:)`, other → `.providerError`.
- `Sources/AutoSuggestApp/Inference/InferenceRuntimeFactory.swift` (~lines 58-71) — constructs the runtime only when `config.onlineLLM.enabled` is true; read it to confirm where the API key is loaded from `SecretStore` (keychain account default: `autosuggest.online.byok.default`, see `README.md:105-114`).
- `Config/AppConfig.swift:229-250` — `OnlineLLMConfig` with `enabled` (default `false`, line 463) and `rolloutStage: "post-mvp"`; `ConfigMigrationManager.swift:20-23` already sketches the post-mvp → available migration path.
- `Tests/AutoSuggestAppTests/OnlineLLMInferenceRuntimeTests.swift` — existing coverage; read before adding tests.
- Error display path: `SuggestionOrchestrator` catches inference errors → `onError` → `TypingPipeline` records metrics/telemetry. **No user-visible surfacing** — a bad API key today would just mean "no suggestions, silently". The UI model has `showBanner(kind:title:message:)` (`UI/AutoSuggestUIModel.swift:342`) as the natural surfacing hook.
- ATS note: the bundled app has no `NSAppTransportSecurity` override in `macos/AutoSuggestDesktop/Info.plist`, so plaintext HTTP to remote hosts is OS-blocked in the app build — but the SwiftPM runner and future plist edits make explicit validation worth having anyway.

## Commands you will need

| Purpose   | Command       | Expected on success |
|-----------|---------------|---------------------|
| Build     | `swift build` | exit 0              |
| Tests     | `swift test --filter OnlineLLM` | all pass |

## Scope

**In scope**:
- `Sources/AutoSuggestApp/Inference/OnlineLLMInferenceRuntime.swift` (endpoint validation only)
- `Tests/AutoSuggestAppTests/OnlineLLMInferenceRuntimeTests.swift` (extend)
- `docs/BYOK_SHIP_PLAN.md` (create — the spike report)
- `plans/README.md` (status row)

**Out of scope** (do NOT do in this spike, even though the report will discuss them):
- Flipping `enabled` to true anywhere, or changing defaults/migrations.
- Building error banners, key-entry UI changes, or fallback routing.
- Live API calls with real keys — that's the maintainer's validation step, specified in the report.
- Website/README messaging changes (LAUNCH_AUDIT deliberately removed BYOK claims until it ships).

## Git workflow

- Branch: `advisor/009-byok-spike`
- Commit per step; message style: short imperative summary.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Harden the endpoint boundary

In `OnlineLLMInferenceRuntime`, add a static validator and use it for every request URL (both `requestOpenAICompatible` and `requestAnthropic` build URLs from `endpointURL`):

```swift
/// BYOK endpoints must be HTTPS, except loopback for local proxies.
static func isAllowedEndpoint(_ url: URL) -> Bool {
    if url.scheme?.lowercased() == "https" { return true }
    if url.scheme?.lowercased() == "http",
       let host = url.host?.lowercased(),
       host == "127.0.0.1" || host == "localhost" || host == "::1" {
        return true
    }
    return false
}
```

In both request paths, after building the URL: `guard Self.isAllowedEndpoint(url) else { throw InferenceError.runtimeUnavailable("BYOK endpoint must use HTTPS (or localhost for proxies).") }`.

**Verify**: `swift build` → exit 0.

### Step 2: Tests for the validator

Extend `OnlineLLMInferenceRuntimeTests.swift` (match its existing style):
- `https://api.openai.com` → allowed
- `http://127.0.0.1:8080` and `http://localhost:1234` → allowed
- `http://api.example.com` → rejected
- `ftp://x` / scheme-less → rejected
- A runtime constructed with an `http://` remote endpoint: `generateSuggestion` throws (no network call attempted — if the existing tests use a URLProtocol stub, assert the stub was never hit; if they don't, assert the thrown error message).

**Verify**: `swift test --filter OnlineLLM` → all pass.

### Step 3: Investigate and write `docs/BYOK_SHIP_PLAN.md`

Read these before writing: `InferenceRuntimeFactory.swift` (key loading, enable gating), `AutoSuggestViews.swift:573-626` (the disabled settings UI), `ConfigMigrationManager.swift` (rollout migration), `SuggestionOrchestrator.swift:64-68` (error path), `AppConfig.swift:229-250`. The report must contain, with file:line evidence for each claim:

1. **Gap inventory** — what stands between "disabled" and "shippable": enable/rollout mechanics (config flip vs. UI toggle — recommend one), key-entry flow status (does the UI actually write to `SecretStore`? trace it), error surfacing (map `InferenceError.invalidAPIKey` / `.rateLimited` / `.providerError` to `showBanner` calls — specify where the hook goes), fallback behavior when the provider fails (does the engine fall through to local runtimes today? — trace `InferenceEngine.suggest`'s loop with the online runtime first in `runtimeOrder`).
2. **Privacy posture** — BYOK sends typed context to a third party by design; specify the consent UX (explicit toggle copy, what the website/README must say when re-enabling the messaging that LAUNCH_AUDIT removed) and confirm plan 002's log hygiene covers the new path.
3. **Manual validation matrix for the maintainer** — exact steps per provider (OpenAI-compatible, OpenRouter, Anthropic): model to use, expected latency budget (<1s p50 for ~60-token completions), the three failure drills (wrong key → banner; rate limit → banner with retry-after; network off → silent fallback to local).
4. **Recommended v0.2 cut** — smallest shippable scope, ordered task list with S/M/L estimates, and explicit non-goals (e.g. streaming, per-app provider routing).

**Verify**: `docs/BYOK_SHIP_PLAN.md` exists; every file:line citation in it resolves to real code.

## Test plan

Step 2's validator tests (≥5 new). Full suite stays green: `swift test` → exit 0.

## Done criteria

- [ ] `swift test` exits 0; new endpoint-validation tests pass
- [ ] `isAllowedEndpoint` guards both provider request paths
- [ ] `config.onlineLLM.enabled` default is still `false` (`grep -n "enabled: false" Sources/AutoSuggestApp/Config/AppConfig.swift` still shows the onlineLLM default)
- [ ] `docs/BYOK_SHIP_PLAN.md` exists with the four required sections
- [ ] No files outside the in-scope list are modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:
- The settings UI turns out to never persist the API key (a real gap — it belongs in the report as a finding, but if it means the existing tests can't construct the runtime, report before working around it).
- `InferenceRuntimeFactory` constructs the online runtime even when `enabled == false` (would contradict the "disabled" premise — security-relevant, report immediately).
- Adding the guard breaks an existing test that intentionally uses a plain-HTTP remote stub URL — report; the test may need a `localhost` stub instead, but confirm that's the test's intent first.

## Maintenance notes

- The validator is intentionally static/pure so the eventual settings UI can call it for inline validation before saving.
- Reviewer should scrutinize: the loopback allowance (it's what makes local proxies like LiteLLM work — keep it documented).
- When v0.2 ships BYOK: restore the online-LLM messaging on the website (it was removed by design on 2026-06-03 — see `docs/LAUNCH_AUDIT.md` item #3), and update `README.md:228-241` ("Online Models (Post-MVP BYOK)").
