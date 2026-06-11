# Plan 001: Add characterization tests for text insertion, context parsing, and pipeline guards

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat f2dae47..HEAD -- Sources/AutoSuggestApp/Suggestions/AXTextInsertionEngine.swift Sources/AutoSuggestApp/Context/AXTextContextProvider.swift Sources/AutoSuggestApp/Suggestions/TypingPipeline.swift Tests/`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
- **Category**: tests

- **Planned at**: commit `f2dae47`, 2026-06-11

## Why this matters

The text-insertion path (`AXTextInsertionEngine`) can silently corrupt user text in any app, and the AX context parser feeds the policy engine that decides whether to suggest in password fields. Neither has a single unit test today — `grep -rl "AXTextInsertionEngine" Tests/` returns nothing. Plans 003 (clipboard fidelity) and 004 (hot-path refactor) will rewrite parts of these files; this plan pins down current behavior first so those refactors can't silently regress. The pure-logic helpers (range math, caret extraction, smart-continuation) are unit-testable today with only visibility changes.

## Current state

- `Sources/AutoSuggestApp/Suggestions/AXTextInsertionEngine.swift` — `@MainActor` class; the testable pure helper is `replacingText(in:selectedRange:replacement:)`:

  ```swift
  // AXTextInsertionEngine.swift:59-65
  private func replacingText(in text: String, selectedRange: NSRange, replacement: String) -> String {
      let nsText = text as NSString
      let safeLocation = max(0, min(selectedRange.location, nsText.length))
      let safeLength = max(0, min(selectedRange.length, nsText.length - safeLocation))
      let safeRange = NSRange(location: safeLocation, length: safeLength)
      return nsText.replacingCharacters(in: safeRange, with: replacement)
  }
  ```

- `Sources/AutoSuggestApp/Context/AXTextContextProvider.swift` — the testable pure helpers:

  ```swift
  // AXTextContextProvider.swift:102-109
  private func extractTextBeforeCaret(fullValue: String, selectedRange: NSRange?) -> String {
      guard let selectedRange else {
          return fullValue
      }
      let nsText = fullValue as NSString
      let caret = max(0, min(selectedRange.location, nsText.length))
      return nsText.substring(to: caret)
  }
  ```

  ```swift
  // AXTextContextProvider.swift:73-91 (excerpt)
  private func stringValue(from value: AnyObject) -> String? {
      if let string = value as? String { return string }
      if let attributed = value as? NSAttributedString { return attributed.string }
      ...
      if let number = value as? NSNumber { return number.stringValue }
      ...
  }
  ```

- `Sources/AutoSuggestApp/Suggestions/TypingPipeline.swift` — `@MainActor` class; two private pure functions hold the staleness/continuation guards that protect against inserting into the wrong field:

  ```swift
  // TypingPipeline.swift:190-209 (signature)
  private func adjustSuggestionForSmartContinuation(
      activeSuggestion: SuggestionCandidate,
      newContext: String
  ) -> SuggestionCandidate?

  // TypingPipeline.swift:211-227 (signature)
  private func isSuggestion(_ suggestion: SuggestionCandidate, validFor context: TextContext) -> Bool
  ```

  `SuggestionCandidate` is defined at `Sources/AutoSuggestApp/Suggestions/SuggestionOrchestrator.swift:3-11` (fields: `requestID`, `completion`, `confidence`, `sourceContext`, `sourceBundleID`, `sourceWindowTitle`, `latencyMs`). `TextContext` and `PolicyContext` are in `Sources/AutoSuggestApp/Context/TextContextProvider.swift` and `Sources/AutoSuggestApp/System/PolicyEngine.swift:21-27`.

- Test conventions: XCTest with `@testable import AutoSuggestApp`; see `Tests/AutoSuggestAppTests/PolicyEngineTests.swift` for the structural pattern (plain `XCTestCase`, one behavior per test, descriptive names like `testSecureFieldIsExcluded`). `Tests/AutoSuggestAppTests/IntegrationTestHarness.swift` shows how a full `TypingPipeline` is constructed with mocks if you need one — but for this plan, prefer testing the two guard functions directly after making them `internal`.
- Baseline: the suite currently has **119 tests, all passing** (`swift test`, ~70s).

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Build     | `swift build`            | exit 0              |
| Tests     | `swift test`             | all pass, ≥119 tests |
| One file  | `swift test --filter AXTextInsertionEngineLogicTests` | new tests pass |

## Scope

**In scope** (the only files you should modify):
- `Sources/AutoSuggestApp/Suggestions/AXTextInsertionEngine.swift` — visibility change only (`private func replacingText` → `func replacingText`)
- `Sources/AutoSuggestApp/Context/AXTextContextProvider.swift` — visibility changes only (`extractTextBeforeCaret`, `stringValue`)
- `Sources/AutoSuggestApp/Suggestions/TypingPipeline.swift` — visibility changes only (`adjustSuggestionForSmartContinuation`, `isSuggestion(_:validFor:)`)
- `Tests/AutoSuggestAppTests/AXTextInsertionEngineLogicTests.swift` (create)
- `Tests/AutoSuggestAppTests/AXTextContextParsingTests.swift` (create)
- `Tests/AutoSuggestAppTests/TypingPipelineGuardTests.swift` (create)
- `plans/README.md` (status row)

**Out of scope** (do NOT touch, even though they look related):
- Any behavior change in the three source files — this plan changes `private` → internal visibility ONLY. If a test reveals a bug, write the test to document the *current* behavior with a `// CHARACTERIZATION:` comment and report the bug in your final summary; do not fix it here.
- The clipboard paste path (`insertByClipboardPaste`, `restoreClipboardIfNeeded`) — plan 003 rewrites it; testing the global pasteboard here would be wasted work.
- `IntegrationTestHarness.swift` — leave existing integration tests as they are.

## Git workflow

- Branch: `advisor/001-characterization-tests`
- Commit per step; message style: short imperative summary (repo examples: "Add online LLM, training export, CI & assets").
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Make the pure helpers internal

Remove the `private` keyword from exactly these five functions (no other signature change):
1. `AXTextInsertionEngine.replacingText(in:selectedRange:replacement:)` (line ~59)
2. `AXTextContextProvider.extractTextBeforeCaret(fullValue:selectedRange:)` (line ~102)
3. `AXTextContextProvider.stringValue(from:)` (line ~73)
4. `TypingPipeline.adjustSuggestionForSmartContinuation(activeSuggestion:newContext:)` (line ~190)
5. `TypingPipeline.isSuggestion(_:validFor:)` (line ~211)

**Verify**: `swift build` → exit 0.

### Step 2: Tests for `replacingText`

Create `Tests/AutoSuggestAppTests/AXTextInsertionEngineLogicTests.swift`. Note `AXTextInsertionEngine` is `@MainActor`, so mark the test class `@MainActor` (XCTest supports `@MainActor final class ... : XCTestCase`). Cases:
- Insert at caret (range length 0) in the middle of text.
- Replace a non-empty selection.
- `location` beyond text length → clamps, appends at end (characterize the clamp at lines 61-63).
- `length` overrunning the end → clamps to available length.
- Empty source text + insertion.
- Replacement containing an emoji (NSString UTF-16 semantics — assert the exact output so future Swift.String refactors don't shift grapheme handling silently).

**Verify**: `swift test --filter AXTextInsertionEngineLogicTests` → all new tests pass.

### Step 3: Tests for context parsing

Create `Tests/AutoSuggestAppTests/AXTextContextParsingTests.swift` covering:
- `extractTextBeforeCaret`: caret mid-text; `selectedRange == nil` → returns full value; location 0 → empty string; location beyond length → full value (clamped).
- `stringValue(from:)`: a Swift `String`, an `NSAttributedString` (returns `.string`), an `NSNumber` (returns `stringValue`).

**Verify**: `swift test --filter AXTextContextParsingTests` → all new tests pass.

### Step 4: Tests for pipeline guards

Create `Tests/AutoSuggestAppTests/TypingPipelineGuardTests.swift` (`@MainActor`). Construct a `TypingPipeline` using the mock pattern from `IntegrationTestHarness.swift` (copy its construction of mocks; do not modify the harness). Cases for `isSuggestion(_:validFor:)`:
- Same bundle ID + same window title + context extends sourceContext → valid.
- Different bundle ID → invalid.
- Different non-empty window titles → invalid.
- Both window titles empty/nil → title check skipped (characterize lines 215-221).
- Context that neither extends nor prefixes sourceContext → invalid.

Cases for `adjustSuggestionForSmartContinuation`:
- User typed a prefix of the completion → returns candidate with the typed part trimmed off and `sourceContext` updated.
- User typed text that diverges from the completion → returns nil.
- User typed the entire completion → returns nil (line 199: empty remaining).
- New context doesn't extend sourceContext at all → returns nil.
- New context identical to sourceContext → returns the original candidate unchanged.

**Verify**: `swift test --filter TypingPipelineGuardTests` → all new tests pass.

### Step 5: Full suite

**Verify**: `swift test` → exit 0, total test count ≥ 119 + (your new tests; expect ~135+), 0 failures.

## Test plan

This plan *is* the test plan — see steps 2–4. Model all files after `Tests/AutoSuggestAppTests/PolicyEngineTests.swift`.

## Done criteria

- [ ] `swift build` exits 0
- [ ] `swift test` exits 0 with ≥16 new tests across 3 new files
- [ ] `git diff Sources/` shows ONLY `private ` keyword removals (no logic edits): verify with `git diff Sources/ | grep '^[+-]' | grep -v '^[+-][+-]' | grep -v 'private func\|    func'` → empty
- [ ] No files outside the in-scope list are modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:
- The code at the locations in "Current state" doesn't match the excerpts.
- Making a helper `internal` causes a Swift 6 concurrency error you cannot resolve by annotating the *test* (e.g. `@MainActor` on the test class) — do not add `@unchecked Sendable` or `nonisolated` to source types.
- Constructing `TypingPipeline` in tests requires modifying `IntegrationTestHarness.swift` or any source file beyond the visibility changes.
- A characterization test reveals behavior so broken the test would enshrine a crash — report the bug instead of asserting it.

## Maintenance notes

- Plans 003 and 004 modify `AXTextInsertionEngine`; these tests are their safety net. If plan 004 changes `isAvailable` signatures, these tests should be unaffected (they don't touch runtimes).
- Reviewer should scrutinize: that no `private` removal widened access to something stateful (all five functions are pure).
- Deferred: tests for the clipboard backup/restore flow (written in plan 003 against the new snapshot API), and real-AX integration tests (impossible in CI without TCC permissions — documented limitation).
