# Plan 004: Remove main-thread blocking from the suggestion hot path

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat f2dae47..HEAD -- Sources/AutoSuggestApp/Inference/ Sources/AutoSuggestApp/Suggestions/AXTextInsertionEngine.swift`
> Plans 001 and 003 legitimately modify `AXTextInsertionEngine.swift` (tests
> visibility + clipboard snapshot). Verify the *structure* described below
> still holds; semantic mismatches are a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: plans/001-insertion-context-characterization-tests.md, plans/003-clipboard-fidelity-on-accept.md
- **Category**: perf
- **Planned at**: commit `f2dae47`, 2026-06-11

## Why this matters

Every debounced keystroke triggers `InferenceEngine.suggest()`, which is `@MainActor` and calls each runtime's **synchronous** `isAvailable()` before trying it. The llama.cpp adapter's `isAvailable()` spawns `/usr/bin/pgrep` twice (blocking `waitUntilExit`) and, if those fail, blocks the main thread on a `DispatchSemaphore` for up to **1.5 seconds**; the Ollama adapter spawns pgrep too. With a runtime down, the user's main thread — the same thread servicing the CGEvent tap — stalls for seconds per suggestion. On top of that, accepting a suggestion runs `Thread.sleep(0.05)` on the main actor inside the event-tap callback path. Sustained main-thread stalls also risk macOS disabling the event tap (`kCGEventTapDisabledByTimeout`). This plan makes availability async + cached and removes the sleep.

## Current state

- `Sources/AutoSuggestApp/Inference/InferenceRuntime.swift` — the protocol:

  ```swift
  protocol InferenceRuntime {
      @MainActor var name: String { get }
      @MainActor func isAvailable() -> Bool
      @MainActor func generateSuggestion(context: String) async throws -> Suggestion
  }
  ```

- `Sources/AutoSuggestApp/Inference/InferenceEngine.swift` — `@MainActor`; two hot call sites:

  ```swift
  // InferenceEngine.swift:17-19
  var availableRuntimeNames: [String] {
      runtimes.filter { $0.isAvailable() }.map(\.name)
  }
  // InferenceEngine.swift:28-29 (inside suggest(for:))
  for runtime in runtimes {
      guard runtime.isAvailable() else { continue }
  ```

- `Sources/AutoSuggestApp/Inference/LlamaCppInferenceRuntime.swift` — the blockers:

  ```swift
  // :13-18
  func isAvailable() -> Bool {
      if isProcessRunning("llama-server") || isProcessRunning("llama.cpp") { return true }
      return isEndpointReachable()
  }
  // :20-35 — DispatchSemaphore + URLSession dataTask, semaphore.wait(timeout: .now() + 1.5)
  // :108-119 — isProcessRunning spawns /usr/bin/pgrep and waitUntilExit()s
  // :162-164 — `private final class ResultBox: @unchecked Sendable { var value = false }`
  ```

- `Sources/AutoSuggestApp/Inference/OllamaFallbackInferenceRuntime.swift:15-26` — `isAvailable()` is a pgrep spawn + `waitUntilExit()`.
- `Sources/AutoSuggestApp/Inference/CoreMLInferenceRuntime.swift:16-18` — `isAvailable()` is a cheap in-memory check (`resourceMonitor.hasSufficientMemoryForPrimaryRuntime()`).
- `Sources/AutoSuggestApp/Inference/OnlineLLMInferenceRuntime.swift:20-22` — `isAvailable()` is `!apiKey.isEmpty` (cheap).
- `Sources/AutoSuggestApp/Suggestions/AXTextInsertionEngine.swift:137` — `Thread.sleep(forTimeInterval: 0.05)` between Cmd+V and clipboard restore, inside a `@MainActor` method called synchronously from `TypingPipeline.handleShortcut` (`Suggestions/TypingPipeline.swift:155`).
- Find every caller of `isAvailable` / `availableRuntimeNames` before starting:

  ```
  grep -rn "isAvailable()\|availableRuntimeNames" Sources/ Tests/
  ```

  Expected callers beyond the ones above: `InferenceRuntimeFactory`, possibly `ModelCompatibilityAdvisor` and `AppCoordinator` (runtime health reporting), mock runtimes in `Tests/AutoSuggestAppTests/` (`InferenceEngineTests.swift`, `InferenceRuntimeFactoryTests.swift`, `IntegrationTestHarness.swift`, `OnlineLLMInferenceRuntimeTests.swift`). If you find a caller in a context that cannot become async (e.g. a synchronous SwiftUI computed property), see STOP conditions.

## Commands you will need

| Purpose   | Command       | Expected on success |
|-----------|---------------|---------------------|
| Build     | `swift build` | exit 0              |
| Tests     | `swift test`  | all pass            |

## Scope

**In scope** (the only files you should modify):
- `Sources/AutoSuggestApp/Inference/InferenceRuntime.swift`
- `Sources/AutoSuggestApp/Inference/InferenceEngine.swift`
- `Sources/AutoSuggestApp/Inference/LlamaCppInferenceRuntime.swift`
- `Sources/AutoSuggestApp/Inference/OllamaFallbackInferenceRuntime.swift`
- `Sources/AutoSuggestApp/Inference/CoreMLInferenceRuntime.swift`
- `Sources/AutoSuggestApp/Inference/OnlineLLMInferenceRuntime.swift`
- `Sources/AutoSuggestApp/Suggestions/AXTextInsertionEngine.swift` (the sleep only)
- Direct callers discovered by the grep (e.g. `AppCoordinator.swift`, `ModelCompatibilityAdvisor.swift`) — signature propagation only
- Test files that define mock runtimes — signature updates only
- `plans/README.md` (status row)

**Out of scope** (do NOT touch, even though they look related):
- `SuggestionOrchestrator` debounce logic — already async and correct.
- Inference request/response logic inside `generateSuggestion` of any runtime.
- The clipboard snapshot logic from plan 003 — only the *timing* of restore changes.

## Git workflow

- Branch: `advisor/004-async-availability`
- Commit per step; message style: short imperative summary.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Make the protocol async

Change `InferenceRuntime.isAvailable` to `func isAvailable() async -> Bool`. Update the four conformers minimally:
- CoreML and OnlineLLM: just add `async` to the signature (bodies unchanged).
- Ollama: replace the pgrep body with an async HTTP reachability check — `GET \(baseURL)/api/tags` (Ollama's cheapest endpoint) with `timeoutInterval = 1.0`, return true on any HTTP response, false on thrown error. Delete the Process/pgrep code.
- llama.cpp: delete `isProcessRunning`, `isEndpointReachable`, and `ResultBox` entirely. New body: async `HEAD \(baseURL)/completion` request via `try? await URLSession.shared.data(for: request)` with `timeoutInterval = 1.0`; return true when an `HTTPURLResponse` arrives with status in `200..<500`; false otherwise (preserves the current status-code semantics at line 29).

**Verify**: `swift build` → fails ONLY at call sites of `isAvailable` (expected — fixed next). Record the failing call-site list; it must match the grep from "Current state".

### Step 2: Propagate through InferenceEngine with a TTL cache

In `InferenceEngine`:
- `suggest(for:)` line 29 → `guard await isAvailableCached(runtime) else { continue }`.
- Replace the computed `availableRuntimeNames` with `func availableRuntimeNames() async -> [String]` using the same cached check.
- Add the cache (engine is `@MainActor`, so plain stored state is safe):

  ```swift
  private var availabilityCache: [String: (checkedAt: Date, available: Bool)] = [:]
  private let availabilityTTL: TimeInterval = 15

  private func isAvailableCached(_ runtime: InferenceRuntime) async -> Bool {
      if let cached = availabilityCache[runtime.name],
         Date().timeIntervalSince(cached.checkedAt) < availabilityTTL {
          return cached.available
      }
      let available = await runtime.isAvailable()
      availabilityCache[runtime.name] = (Date(), available)
      return available
  }
  ```

- Add `func invalidateAvailabilityCache()` (empty the dict) for callers that need a fresh check (e.g. a future "Retry" button — plan 005 references this).

**Verify**: `swift build` → remaining failures only in non-Inference callers and tests.

### Step 3: Propagate to remaining callers and tests

Update each caller found by the grep. Patterns:
- Async contexts: add `await`.
- `@MainActor` sync contexts that build UI state (likely `AppCoordinator` health reporting): wrap in their existing `Task { @MainActor in ... }` structure — `AppCoordinator` already uses this pattern extensively (see its banner/`Task` usage around lines 780-800).
- Mock runtimes in tests: add `async` to their `isAvailable()`.

Do not restructure any caller beyond what the signature forces.

**Verify**: `swift build` → exit 0; `swift test` → all pass.

### Step 4: Remove the accept-path sleep

In `AXTextInsertionEngine.insertByClipboardPaste` (post-plan-003 shape), replace the synchronous tail:

```swift
Thread.sleep(forTimeInterval: 0.05)
snapshot.restore(to: pasteboard)
UserDefaults.standard.removeObject(forKey: Self.clipboardBackupKey)
return true
```

with a scheduled restore (return immediately; the UserDefaults crash-backup is cleared *inside* the deferred block so a crash in the 50ms window still restores on next launch):

```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
    snapshot.restore(to: pasteboard)
    UserDefaults.standard.removeObject(forKey: Self.clipboardBackupKey)
}
return true
```

(If plan 003 has not landed and the code still uses the string-based backup, STOP — dependency order was violated.)

**Verify**: `grep -n "Thread.sleep" Sources/` → no matches.

### Step 5: Full suite + latency sanity check

**Verify**: `swift test` → exit 0. Also run `grep -rn "DispatchSemaphore\|waitUntilExit" Sources/AutoSuggestApp/Inference/` → no matches.

## Test plan

- Update mock runtimes for the async signature (mechanical).
- New tests in `Tests/AutoSuggestAppTests/InferenceEngineTests.swift` (follow its existing style):
  1. **Cache hit**: a mock runtime counts `isAvailable()` calls; two `suggest(for:)` calls within the TTL → counter == 1.
  2. **Cache invalidation**: after `invalidateAvailabilityCache()`, counter == 2.
  3. **Unavailable runtime skipped**: mock A unavailable, mock B available → suggestion comes from B (this likely exists already — extend, don't duplicate).
- Verification: `swift test` → all pass including new tests.

## Done criteria

- [ ] `swift test` exits 0
- [ ] `grep -rn "DispatchSemaphore" Sources/` → no matches
- [ ] `grep -rn "waitUntilExit" Sources/AutoSuggestApp/Inference/` → no matches
- [ ] `grep -rn "Thread.sleep" Sources/` → no matches
- [ ] `grep -rn "@unchecked Sendable" Sources/AutoSuggestApp/Inference/` → no matches
- [ ] `func isAvailable() async` in all four runtime conformers
- [ ] No files outside the in-scope list are modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:
- A caller of `isAvailable`/`availableRuntimeNames` exists in a context that cannot become async without restructuring beyond ~10 lines (report the file/line and the structural problem).
- Plan 003's `PasteboardSnapshot` is absent from `AXTextInsertionEngine.swift` (dependency not landed).
- Tests that exercised the pgrep path exist and fail for reasons other than the signature change.
- `ModelCompatibilityAdvisor` turns out to define its own *separate* runtime-readiness mechanism that duplicates `isAvailable` — note it as follow-up debt, update only what the compiler forces, and report the duplication.

## Maintenance notes

- The 15s TTL means a freshly-started Ollama server may take up to 15s to be picked up; plan 005's "retry" affordance should call `invalidateAvailabilityCache()`.
- Reviewer should scrutinize: that no runtime's `isAvailable` can still block (search for `Process(`, semaphores), and that the deferred clipboard restore cannot race a second rapid accept (two accepts within 50ms: the second `capture` happens after the first restore is scheduled — acceptable because both restores write the same user snapshot; note this in the PR description).
- Deferred: replacing per-runtime hardcoded confidence values and consolidating the three HTTP adapters (tracked as rejected-for-now in `plans/README.md`).
