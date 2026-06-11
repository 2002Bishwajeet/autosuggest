# Plan 006: Harden secure-input suppression, keychain storage, and model download integrity

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat f2dae47..HEAD -- Sources/AutoSuggestApp/Privacy/KeychainKeyStore.swift Sources/AutoSuggestApp/Privacy/SecretStore.swift Sources/AutoSuggestApp/System/PolicyEngine.swift Sources/AutoSuggestApp/Suggestions/TypingPipeline.swift Sources/AutoSuggestApp/Model/ModelDownloadManager.swift`
> Plan 002 edits TypingPipeline telemetry lines — expected. Other mismatches
> with the excerpts below are STOP conditions.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: none (001 recommended first; 002's TypingPipeline edits land cleanly alongside)
- **Category**: security
- **Planned at**: commit `f2dae47`, 2026-06-11

## Why this matters

Three defense-in-depth gaps for an app that reads every keystroke and downloads executable-adjacent model artifacts: (1) password suppression relies solely on the focused element reporting subrole `AXSecureTextField` — it misses macOS *secure input mode* (set by `sudo` prompts in Terminal, password managers, browser password fields in some states), which the system exposes via one C call; (2) keychain items (the AES-GCM key for the encrypted store, and BYOK API keys) are added without an accessibility class, defaulting to a migratable, less restrictive class; (3) model downloads skip checksum verification whenever the manifest leaves `sha256` empty or `replace_`-prefixed, and extracted archives are not validated against path escapes.

## Current state

- `Sources/AutoSuggestApp/Context/AXTextContextProvider.swift:34` — `isSecureField: subrole == "AXSecureTextField"` is the only secure-field signal.
- `Sources/AutoSuggestApp/System/PolicyEngine.swift:9-19` — default blacklist contains only `com.apple.loginwindow`; coding apps VSCode/Xcode/IntelliJ. `shouldSuggest` (lines 64-73) checks `context.isSecureField`.
- `Sources/AutoSuggestApp/Suggestions/TypingPipeline.swift:84-114` — `handleInputEvent()` early-exits on IME active (line 86-89) and battery pause (90-93); no secure-input-mode check.
- `Sources/AutoSuggestApp/Privacy/KeychainKeyStore.swift:43-54` — `write(_:)` builds an add query with `kSecClass/kSecAttrService/kSecAttrAccount/kSecValueData` only; **no `kSecAttrAccessible`**.
- `Sources/AutoSuggestApp/Privacy/SecretStore.swift:29-52` — `upsert(account:secret:)` same gap in its `addQuery` (lines 46-48).
- `Sources/AutoSuggestApp/Model/ModelDownloadManager.swift`:

  ```swift
  // :160-165
  private func validateChecksumIfPresent(fileURL: URL, manifest: ModelManifest) throws -> Bool {
      let expected = manifest.sha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      guard !expected.isEmpty, !expected.hasPrefix("replace_") else {
          logger.warn("Model checksum not configured; skipping verification.")
          return true
      }
  ```

  ```swift
  // :225-233 — extraction via /usr/bin/ditto -x -k into installDir; no post-extraction validation
  ```

  Ed25519 signature verification exists (lines 175-198) but is skipped when the manifest omits signature fields — leave signature handling as is (signing infra isn't set up yet; checksum is the enforceable baseline).
- `ModelManifest` is defined in `Sources/AutoSuggestApp/Model/ModelManifest.swift` — read it in step 4 to find the artifact URL field name (needed to distinguish remote vs local `file://` sources).
- Test pattern: `Tests/AutoSuggestAppTests/PolicyEngineTests.swift` (XCTest, `@testable import AutoSuggestApp`); model tests exist in `ModelManifestTests.swift` / `ModelSourceResolverTests.swift`.

## Commands you will need

| Purpose   | Command       | Expected on success |
|-----------|---------------|---------------------|
| Build     | `swift build` | exit 0              |
| Tests     | `swift test`  | all pass            |

## Scope

**In scope** (the only files you should modify):
- `Sources/AutoSuggestApp/Privacy/KeychainKeyStore.swift`
- `Sources/AutoSuggestApp/Privacy/SecretStore.swift`
- `Sources/AutoSuggestApp/System/PolicyEngine.swift`
- `Sources/AutoSuggestApp/Suggestions/TypingPipeline.swift` (one early-exit only)
- `Sources/AutoSuggestApp/Model/ModelDownloadManager.swift`
- `Tests/AutoSuggestAppTests/PolicyEngineTests.swift` (extend)
- `Tests/AutoSuggestAppTests/ModelDownloadIntegrityTests.swift` (create)
- `plans/README.md` (status row)

**Out of scope** (do NOT touch, even though they look related):
- `PIIFilter.swift` regex coverage — separate audit item.
- Signature-verification flow and `trustedPublicKeysByID` — needs release-signing infrastructure first.
- UI for surfacing download warnings (banners) — note as follow-up if you find a natural hook, don't build it.
- `install.sh` — covered by the release plan's maintenance notes.

## Git workflow

- Branch: `advisor/006-secure-input-hardening`
- Commit per step; message style: short imperative summary.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Respect macOS secure input mode

In `TypingPipeline.handleInputEvent()` add an early exit immediately after the IME check (lines ~86-89):

```swift
if IsSecureEventInputEnabled() {
    clearSuggestion()
    return
}
```

`IsSecureEventInputEnabled()` comes from Carbon's HIToolbox — add `import Carbon` at the top of `TypingPipeline.swift`. This catches `sudo` in Terminal, password managers, and any app that calls `EnableSecureEventInput`, regardless of AX subroles. (Note: when secure input is on, the CGEvent tap won't see keys from the secure app anyway, but events from *other* sessions/windows still flow and the system flag is the documented "do not assist" signal.)

**Verify**: `swift build` → exit 0.

### Step 2: Blacklist password managers by default

In `PolicyEngine.swift`, extend `PolicyRules.default.blacklistedBundleIDs` (lines 10-12) with:

```swift
"com.1password.1password",
"com.agilebits.onepassword7",
"com.bitwarden.desktop",
"org.keepassxc.keepassxc",
"com.lastpass.LastPass",
```

**Verify**: `swift build` → exit 0.

### Step 3: Pin keychain accessibility

- `KeychainKeyStore.write(_:)` (line ~44): add `kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` to the query dict.
- `SecretStore.upsert(account:secret:)`: add the same key to `addQuery` (after line 46). Do NOT add it to `updateAttrs` for the `SecItemUpdate` path (changing accessibility on update can fail with `errSecParam` on some macOS versions; new items get the attribute, existing items keep working — acceptable migration posture, note it in your summary).

Rationale for `AfterFirstUnlockThisDeviceOnly`: the app is a login-launched background utility (key may be needed right after login), and `ThisDeviceOnly` prevents the key from migrating in backups/keychain sync.

**Verify**: `swift build` → exit 0; `grep -c "kSecAttrAccessible" Sources/AutoSuggestApp/Privacy/KeychainKeyStore.swift Sources/AutoSuggestApp/Privacy/SecretStore.swift` → 1 each.

### Step 4: Enforce checksums for remote model artifacts

First read `Sources/AutoSuggestApp/Model/ModelManifest.swift` and `ModelDownloadManager.swift` in full to find: (a) the manifest field holding the artifact URL, (b) where `validateArtifactIntegrity` is called relative to download. Then change `validateChecksumIfPresent`:

- Delete the `replace_` bypass entirely (a placeholder checksum is a missing checksum).
- When `expected` is empty AND the artifact came from a **remote** URL (scheme `http`/`https`): `throw ModelDownloadError.missingChecksum` (add this case to the existing `ModelDownloadError` enum with a clear `localizedDescription`, e.g. "Model manifest does not include a sha256 checksum; refusing to install an unverified remote artifact.").
- When `expected` is empty and the source is local (`file://`): keep the warn-and-proceed behavior (documented dev workflow in README "Local Model Setup" Option 3).
- You will need the source URL inside the function — pass it as a parameter from the call site (`validateArtifactIntegrity` and its caller); keep the signature change minimal.

**Verify**: `swift build` → exit 0.

### Step 5: Validate extraction output

After the `ditto` extraction succeeds (`unpackArchiveIfNeeded`, after line ~233), walk `installDir` and fail closed on path escapes:

```swift
let fm = FileManager.default
let installRoot = installDir.resolvingSymlinksInPath().standardizedFileURL.path
if let enumerator = fm.enumerator(at: installDir, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
    for case let entry as URL in enumerator {
        let resolved = entry.resolvingSymlinksInPath().standardizedFileURL.path
        if !resolved.hasPrefix(installRoot) {
            try? fm.removeItem(at: installDir)
            throw ModelDownloadError.unsafeArchiveContents(path: entry.lastPathComponent)
        }
    }
}
```

Add `unsafeArchiveContents(path: String)` to `ModelDownloadError`.

**Verify**: `swift build` → exit 0.

### Step 6: Tests

- Extend `PolicyEngineTests.swift`: a context with `bundleID == "com.1password.1password"` → `shouldSuggest` false (model after `testCodingBundleIsExcluded`).
- Create `Tests/AutoSuggestAppTests/ModelDownloadIntegrityTests.swift`:
  1. Empty `sha256` + remote URL → integrity validation throws `missingChecksum` (construct a `ModelManifest` fixture the way `ModelManifestTests.swift` does).
  2. `sha256` starting with `replace_` + remote URL → throws (bypass removed).
  3. Empty `sha256` + `file://` URL → does not throw.
  4. Correct `sha256` of a small temp file → passes; wrong checksum → throws `checksumMismatch`.
  5. Extraction validation: build a temp directory containing a symlink pointing to `/tmp` outside it, run the validation walk (extract the walk into an internal helper so the test can call it without a real zip) → throws `unsafeArchiveContents`.

(`IsSecureEventInputEnabled` is not unit-testable — it reflects live system state; cover via the manual check below.)

**Verify**: `swift test` → exit 0, all new tests pass.

### Step 7: Manual smoke test (only if you can run a GUI)

Run the app, open Terminal, run `sudo -k && sudo true`, and start typing the password — no overlay must appear. State if skipped.

## Test plan

See step 6 — one extended test + five new tests, modeled on `PolicyEngineTests.swift` and `ModelManifestTests.swift`.

## Done criteria

- [ ] `swift test` exits 0 with ≥6 new/extended tests
- [ ] `grep -n "IsSecureEventInputEnabled" Sources/AutoSuggestApp/Suggestions/TypingPipeline.swift` → 1 match
- [ ] `grep -n "replace_" Sources/AutoSuggestApp/Model/ModelDownloadManager.swift` → no matches
- [ ] `grep -c "kSecAttrAccessible" Sources/AutoSuggestApp/Privacy/*.swift` → 2 total
- [ ] `unsafeArchiveContents` and `missingChecksum` cases exist in `ModelDownloadError`
- [ ] No files outside the in-scope list are modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:
- `import Carbon` fails to resolve in the SwiftPM build (sandboxed module maps can differ) — report; do not vendor a dlsym shim.
- `ModelManifest` has no artifact-URL field reachable from `validateChecksumIfPresent`'s call chain (the remote/local distinction can't be made cleanly) — report the actual call-graph.
- The default remote manifest shipped with the app currently has an empty `sha256` — enforcing would brick first-run model download. Check `ModelManifestProvider`'s fallback manifest content FIRST; if its sha256 is empty/`replace_`-prefixed, STOP and report (the manifest must be fixed in the same change, which needs the maintainer's real artifact hash).
- Existing keychain items cause `read()` failures after adding the accessibility attribute (they shouldn't — reads don't filter on it — but if tests/manual runs show otherwise, stop).

## Maintenance notes

- When release signing lands (plan 008), revisit signature verification: ship `trustedPublicKeysByID` with a real key and make signatures mandatory for the default manifest source.
- Reviewer should scrutinize: the remote/local distinction in step 4 (it's the security boundary), and that step 5's prefix check uses resolved+standardized paths on both sides.
- Future: user-initiated Hugging Face downloads (Settings UI) have no checksum by nature; consider an explicit in-UI confirmation for unverified downloads — UI work deferred.
