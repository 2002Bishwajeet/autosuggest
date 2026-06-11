# Plan 002: Stop user-derived text leaking into the system log and telemetry

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat f2dae47..HEAD -- Sources/AutoSuggestApp/Support/Logger.swift Sources/AutoSuggestApp/Suggestions/SuggestionOrchestrator.swift Sources/AutoSuggestApp/Suggestions/TypingPipeline.swift Sources/AutoSuggestApp/Inference/OnlineLLMInferenceRuntime.swift`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `f2dae47`, 2026-06-11

## Why this matters

AutoSuggest's brand promise is "100% local, no cloud, private". But today every model completion — text derived from what the user typed, which the model frequently echoes — is written to the macOS unified system log in plaintext, because the project's `Logger` wrapper forces `privacy: .public` on all interpolated values (overriding os_log's default redaction). Anyone with Console.app, `log show`, or a sysdiagnose can read it. Separately, the local telemetry file stores the *raw accepted completion* — even though the neighboring training-data exporter carefully PII-filters the very same strings. This is the highest trust-impact fix in the codebase and it's small.

## Current state

- `Sources/AutoSuggestApp/Support/Logger.swift` — the only logging facade; everything in the app routes through it:

  ```swift
  // Logger.swift:11-21
  func info(_ message: String) {
      logger.info("\(message, privacy: .public)")
  }
  func warn(_ message: String) {
      logger.warning("\(message, privacy: .public)")
  }
  func error(_ message: String) {
      logger.error("\(message, privacy: .public)")
  }
  ```

- `Sources/AutoSuggestApp/Suggestions/SuggestionOrchestrator.swift:52` — logs the raw completion:

  ```swift
  logger.info("Suggestion ready: \(completion)")
  ```

- `Sources/AutoSuggestApp/Suggestions/TypingPipeline.swift:165-176` — telemetry stores the raw completion (contrast: `TrainingDataExporter.recordTrainingPair` at `Privacy/TrainingDataExporter.swift:51-52` sanitizes both prompt and completion through `PIIFilter` before persisting):

  ```swift
  Task {
      await metricsCollector.recordSuggestionAccepted()
      await personalizationEngine.recordAcceptedSuggestion(completionText)
      await telemetryManager.record(
          event: "suggestion_accepted",
          payload: ["completion": completionText]
      )
      ...
  }
  ```

- `Sources/AutoSuggestApp/Inference/OnlineLLMInferenceRuntime.swift:150-152` — provider error embeds the full HTTP response body in the error message; `InferenceEngine.swift:38` then logs `error.localizedDescription` (publicly):

  ```swift
  default:
      let body = String(data: data, encoding: .utf8) ?? "No response body"
      throw InferenceError.providerError(statusCode: http.statusCode, message: body)
  ```

- Telemetry is local-JSONL and **off by default** (`Config/AppConfig.swift:473-474`: `TelemetryConfig(enabled: false, ...)`), which limits but does not remove the exposure — users who enable it get raw text persisted and exportable.
- Note: `PersonalizationEngine.recordAcceptedSuggestion` stores into the AES-GCM `EncryptedFileStore` — that path is fine; do not change it.

## Commands you will need

| Purpose   | Command       | Expected on success |
|-----------|---------------|---------------------|
| Build     | `swift build` | exit 0              |
| Tests     | `swift test`  | all pass (≥119)     |

## Scope

**In scope** (the only files you should modify):
- `Sources/AutoSuggestApp/Support/Logger.swift`
- `Sources/AutoSuggestApp/Suggestions/SuggestionOrchestrator.swift`
- `Sources/AutoSuggestApp/Suggestions/TypingPipeline.swift`
- `Sources/AutoSuggestApp/Inference/OnlineLLMInferenceRuntime.swift`
- Any additional `logger.*` call site found in Step 4 that interpolates user-derived text (list them in your summary)
- `plans/README.md` (status row)

**Out of scope** (do NOT touch, even though they look related):
- `Privacy/TrainingDataExporter.swift` — already sanitizes correctly.
- `Privacy/PIIFilter.swift` — its regex coverage is a separate concern (plan 006 territory).
- `Observability/TelemetryManager.swift` — the storage mechanism is fine; only payloads change.
- `PersonalizationEngine` / `EncryptedFileStore` — encrypted at rest by design.

## Git workflow

- Branch: `advisor/002-private-logging`
- Commit per step; message style: short imperative summary.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Default the Logger to redacted

In `Logger.swift`, change all three `privacy: .public` to `privacy: .private`. The unified log will show `<private>` for message content unless the machine has a logging profile installed — that is the correct default for this product. (Static log strings like `"Typing pipeline started."` become redacted too; that's an accepted trade-off — they're recoverable locally via `log config` when debugging. Do NOT add a public/private parameter per call site in this plan; keep the facade simple.)

**Verify**: `swift build` → exit 0; `grep -c "privacy: .private" Sources/AutoSuggestApp/Support/Logger.swift` → `3`; `grep -c "privacy: .public" Sources/AutoSuggestApp/Support/Logger.swift` → `0`.

### Step 2: Remove completion text from the orchestrator log

In `SuggestionOrchestrator.swift:52`, replace:

```swift
logger.info("Suggestion ready: \(completion)")
```

with a content-free line:

```swift
logger.info("Suggestion ready (\(completion.count) chars, confidence \(suggestion.confidence)).")
```

**Verify**: `grep -n "Suggestion ready" Sources/AutoSuggestApp/Suggestions/SuggestionOrchestrator.swift` → shows the new form; no `\(completion)` bare interpolation remains on that line.

### Step 3: Remove raw completion from telemetry

In `TypingPipeline.swift` (the `suggestion_accepted` record, lines ~168-171), replace the payload:

```swift
payload: ["completion": completionText]
```

with:

```swift
payload: ["completion_length": String(completionText.count)]
```

Leave `personalizationEngine.recordAcceptedSuggestion(completionText)` and `trainingDataExporter.recordTrainingPair(...)` exactly as they are.

**Verify**: `grep -rn '"completion"' Sources/` → no matches.

### Step 4: Truncate provider error bodies

In `OnlineLLMInferenceRuntime.swift` `checkHTTPStatus` (lines ~150-152), cap the body included in the error:

```swift
default:
    let rawBody = String(data: data, encoding: .utf8) ?? "No response body"
    let body = String(rawBody.prefix(200))
    throw InferenceError.providerError(statusCode: http.statusCode, message: body)
```

Then audit every remaining log call for user-derived content:

```
grep -rn "logger\.\(info\|warn\|error\)" Sources/ | grep -iE "completion|context|prompt|suggestion|text"
```

For each hit, decide: if the interpolated value can contain user-typed text or model output, replace it with a length/count or a static description. Known-clean hits you should leave alone: messages interpolating only `error.localizedDescription` from file-system/keychain errors, paths, model IDs, and status codes.

**Verify**: re-run the grep above → every remaining hit interpolates only lengths, counts, paths, model IDs, or error domains (record the final list in your summary).

### Step 5: Full suite

**Verify**: `swift test` → exit 0, 0 failures.

## Test plan

No new tests required — the changes are content-removal in log/telemetry strings, verified by the greps in steps 1–4. The existing 119-test suite must stay green (TypingPipeline telemetry behavior is exercised via `IntegrationTestHarness.swift`; if a test asserts on the old `"completion"` payload key, update that assertion to the new key — that is an expected, in-scope test edit).

## Done criteria

- [ ] `swift test` exits 0
- [ ] `grep -rn "privacy: .public" Sources/` → no matches
- [ ] `grep -rn '"completion": completionText' Sources/` → no matches
- [ ] `grep -n "Suggestion ready: \\\\(completion)" Sources/` → no matches
- [ ] No files outside the in-scope list are modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:
- The code at the cited locations doesn't match the excerpts.
- You find a call site that *requires* the raw text in logs for an existing feature (e.g. a diagnostics exporter that intentionally includes it) — surface it, don't decide unilaterally. (Known: `AppCoordinator.buildDiagnosticsReport` around line 838 builds a user-facing diagnostics string — it includes config/permission state, which is fine; STOP only if you find it embedding typed text.)
- More than ~15 call sites need editing in step 4 — that suggests a broader pattern this plan under-scoped.

## Maintenance notes

- Future logging must never interpolate `completion`, `context`, `prompt`, `textBeforeCaret`, or `fullText`. Consider (follow-up, not here) a lint rule or a `Logger.sensitive(_:)` helper that hashes content.
- Reviewer should scrutinize step 4's judgment calls — the grep list in the executor's summary is the review artifact.
- Deferred: making the telemetry payload schema explicit (a struct instead of `[String: String]`) — nice-to-have, not security.
