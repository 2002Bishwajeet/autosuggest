# Plan 003: Preserve full clipboard contents when accepting a suggestion

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat f2dae47..HEAD -- Sources/AutoSuggestApp/Suggestions/AXTextInsertionEngine.swift Tests/AutoSuggestAppTests/`
> Plan 001 adds tests and removes one `private` keyword in this file — that is
> expected drift. Any *logic* change in `insertByClipboardPaste` /
> `restoreClipboardIfNeeded` is a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: plans/001-insertion-context-characterization-tests.md
- **Category**: bug
- **Planned at**: commit `f2dae47`, 2026-06-11

## Why this matters

The default insertion path is clipboard-paste-first (`strictUndoSemantics` defaults to `true`, so paste is effectively the *only* path). Before pasting, the engine backs up the clipboard — but only the plain-string representation. If the user has an image, a file, rich text, or any non-string content on the clipboard, accepting a suggestion silently and permanently destroys it. For a tool that fires dozens of times an hour, that is recurring, invisible data loss. The fix is to snapshot and restore all pasteboard items with all their types.

## Current state

- `Sources/AutoSuggestApp/Suggestions/AXTextInsertionEngine.swift` — `@MainActor` class. The flawed backup/restore:

  ```swift
  // AXTextInsertionEngine.swift:104-145
  private static let clipboardBackupKey = "autosuggest.clipboardBackup"

  static func restoreClipboardIfNeeded() {
      guard let backup = UserDefaults.standard.string(forKey: clipboardBackupKey) else { return }
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.setString(backup, forType: .string)
      UserDefaults.standard.removeObject(forKey: clipboardBackupKey)
  }

  private func insertByClipboardPaste(_ suggestion: String) -> Bool {
      let pasteboard = NSPasteboard.general
      let existing = pasteboard.string(forType: .string)

      // Back up clipboard to UserDefaults in case app crashes mid-paste
      if let existing {
          UserDefaults.standard.set(existing, forKey: Self.clipboardBackupKey)
      }

      pasteboard.clearContents()
      pasteboard.setString(suggestion, forType: .string)

      guard sendCommandV() else {
          if let existing {
              pasteboard.clearContents()
              pasteboard.setString(existing, forType: .string)
          }
          UserDefaults.standard.removeObject(forKey: Self.clipboardBackupKey)
          return false
      }

      // Brief delay so paste event can be processed before clipboard restore
      Thread.sleep(forTimeInterval: 0.05)

      if let existing {
          pasteboard.clearContents()
          pasteboard.setString(existing, forType: .string)
      }
      UserDefaults.standard.removeObject(forKey: Self.clipboardBackupKey)
      return true
  }
  ```

- `restoreClipboardIfNeeded()` is the crash-recovery path — find its caller with `grep -rn "restoreClipboardIfNeeded" Sources/` (expected: app startup in `AppCoordinator` or `AppDelegate`).
- Leave `Thread.sleep` exactly where it is — plan 004 removes it. This plan changes *what* is backed up/restored, not *when*.
- Bugs to fix beyond the string-only backup: when `existing == nil` (empty or non-string clipboard), the current code never clears the suggestion off the clipboard after pasting, and restores nothing — an image-only clipboard is simply lost.

## Commands you will need

| Purpose   | Command       | Expected on success |
|-----------|---------------|---------------------|
| Build     | `swift build` | exit 0              |
| Tests     | `swift test`  | all pass            |
| New tests | `swift test --filter PasteboardSnapshotTests` | all pass |

## Scope

**In scope** (the only files you should modify):
- `Sources/AutoSuggestApp/Suggestions/AXTextInsertionEngine.swift`
- `Tests/AutoSuggestAppTests/PasteboardSnapshotTests.swift` (create)
- `plans/README.md` (status row)

**Out of scope** (do NOT touch, even though they look related):
- `Thread.sleep(forTimeInterval: 0.05)` and the synchronous structure of `insertSuggestion` — plan 004's job.
- The AX-value and CGEvent-typing fallback paths (lines 26-57, 147-160).
- `TypingPipeline.swift` — the caller doesn't change.

## Git workflow

- Branch: `advisor/003-clipboard-fidelity`
- Commit per step; message style: short imperative summary.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Add a pasteboard snapshot type

In `AXTextInsertionEngine.swift`, add (internal so tests can reach it):

```swift
struct PasteboardSnapshot: Codable {
    /// One entry per pasteboard item; each maps raw type identifiers to data.
    let items: [[String: Data]]

    @MainActor
    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            var entry: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    entry[type.rawValue] = data
                }
            }
            return entry
        }
        return PasteboardSnapshot(items: items)
    }

    @MainActor
    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let pbItems = items.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (rawType, data) in entry {
                item.setData(data, forType: NSPasteboard.PasteboardType(rawType))
            }
            return item
        }
        pasteboard.writeObjects(pbItems)
    }
}
```

Caveat to honor: some pasteboard types are promise-based and `data(forType:)` may be nil or expensive for huge payloads. Guard the snapshot: if the *total* captured size exceeds 16 MB, fall back to capturing only the `.string` representation (current behavior) — losing a >16 MB clipboard to memory pressure is worse than the status quo. Implement that cap inside `capture(from:)`.

**Verify**: `swift build` → exit 0.

### Step 2: Use the snapshot in `insertByClipboardPaste`

Rewrite the backup/restore to use `PasteboardSnapshot`:
- `let snapshot = PasteboardSnapshot.capture(from: pasteboard)` before mutating.
- Crash backup: encode the snapshot with `PropertyListEncoder` and store the `Data` in `UserDefaults` under the existing key `autosuggest.clipboardBackup`. If encoding fails or the snapshot is > 1 MB, store only the string form (UserDefaults is the wrong place for huge blobs); otherwise the data blob.
- On `sendCommandV()` failure and on the post-sleep restore: `snapshot.restore(to: pasteboard)` — unconditionally, including when the snapshot is empty (this fixes the "empty clipboard ends up holding the suggestion" bug).
- Remove the old `existing` string variable entirely.

**Verify**: `swift build` → exit 0; `grep -n "string(forType: .string)" Sources/AutoSuggestApp/Suggestions/AXTextInsertionEngine.swift` → no match inside `insertByClipboardPaste`.

### Step 3: Upgrade `restoreClipboardIfNeeded` with backward compatibility

The stored value may be (a) new-format `Data` (plist-encoded `PasteboardSnapshot`), or (b) old-format `String` from a previous app version's crash. Handle both:

```swift
static func restoreClipboardIfNeeded() {
    let defaults = UserDefaults.standard
    defer { defaults.removeObject(forKey: clipboardBackupKey) }
    let pasteboard = NSPasteboard.general
    if let data = defaults.data(forKey: clipboardBackupKey),
       let snapshot = try? PropertyListDecoder().decode(PasteboardSnapshot.self, from: data) {
        snapshot.restore(to: pasteboard)
    } else if let legacy = defaults.string(forKey: clipboardBackupKey) {
        pasteboard.clearContents()
        pasteboard.setString(legacy, forType: .string)
    }
}
```

Note `restoreClipboardIfNeeded` is `static` on a `@MainActor` type; keep its isolation consistent with the current caller (check with the grep from "Current state" — if the caller is not main-actor-isolated, mark the function `@MainActor` and `await`/dispatch at the call site as the existing code structure dictates).

**Verify**: `swift build` → exit 0.

### Step 4: Tests

Create `Tests/AutoSuggestAppTests/PasteboardSnapshotTests.swift` (`@MainActor` test class, pattern: `Tests/AutoSuggestAppTests/PolicyEngineTests.swift`). Use a **private named pasteboard** so tests never touch the user's real clipboard:

```swift
let pasteboard = NSPasteboard(name: NSPasteboard.Name("autosuggest.tests.\(UUID().uuidString)"))
```

Cases:
- Round-trip a plain string (capture → clear → restore → `string(forType: .string)` equals original).
- Round-trip a multi-type item (set both `.string` and `.html` data on one `NSPasteboardItem`; assert both types survive).
- Round-trip two items (two `NSPasteboardItem`s; assert `pasteboardItems?.count == 2` after restore).
- Empty pasteboard → capture → restore → `pasteboardItems` is empty (and a stray string written in between is cleared).
- Plist round-trip: encode snapshot with `PropertyListEncoder`, decode, restore, contents equal.

**Verify**: `swift test --filter PasteboardSnapshotTests` → all pass. Then `swift test` → full suite green.

### Step 5: Manual smoke test (only if you can run the app)

If you are in an environment with a GUI and permissions: run `swift run AutoSuggestRunner`, copy an image (screenshot to clipboard via Cmd+Ctrl+Shift+4), accept a suggestion in Notes, then paste into Preview → the image must still paste. If you cannot run a GUI, state that this step was skipped in your summary.

## Test plan

See step 4 — five new tests in `PasteboardSnapshotTests.swift`, modeled on `PolicyEngineTests.swift`. Plan 001's characterization tests for `replacingText` must still pass untouched.

## Done criteria

- [ ] `swift test` exits 0; ≥5 new tests in `PasteboardSnapshotTests.swift`
- [ ] `grep -n "pasteboard.string(forType: .string)" Sources/AutoSuggestApp/Suggestions/AXTextInsertionEngine.swift` → only inside `restoreClipboardIfNeeded` legacy branch (or zero matches)
- [ ] Restore is unconditional after paste (no `if let existing` guard remains around the restore)
- [ ] No files outside the in-scope list are modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:
- `insertByClipboardPaste` no longer matches the excerpt (beyond plan 001's visibility change).
- `pasteboardItems` returns nil/empty for a pasteboard that demonstrably has a string on it in tests (named-pasteboard quirk) — report rather than switching tests to `NSPasteboard.general`.
- The caller of `restoreClipboardIfNeeded` is structured so that making it `@MainActor` requires touching more than one call site.

## Maintenance notes

- Plan 004 will replace `Thread.sleep` with an async restore — the snapshot restore call moves inside that scheduled block; the snapshot API from this plan is what makes that safe.
- Reviewer should scrutinize: the 16 MB / 1 MB caps (are they sensible), and that transient pasteboard types (e.g. `org.chromium.*` private types) round-trip without crashing.
- Known residual limitation: clipboard managers that watch change-count will still see the suggestion flash onto the clipboard for ~50ms. Documented, not fixable with the paste approach.
