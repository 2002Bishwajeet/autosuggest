# Plan 008: Ship a signed, notarized v0.1.0 release pipeline

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat f2dae47..HEAD -- .github/workflows/release.yml macos/project.yml scripts/install.sh`
> Mismatches with the excerpts below are STOP conditions.

## Status

- **Priority**: P1 (the launch gate)
- **Effort**: M
- **Risk**: MED
- **Depends on**: none to wire; cutting the actual `v0.1.0` tag should wait for plans 002 (privacy) and 003 (clipboard) at minimum — see `plans/README.md`
- **Category**: dx / release
- **Planned at**: commit `f2dae47`, 2026-06-11

## Why this matters

There is no GitHub release or tag — every "Download for Mac" button on the website dead-ends (tracked as P0 #1 in `docs/LAUNCH_AUDIT.md`). The current release workflow builds **unsigned** (`CODE_SIGN_IDENTITY="-"`), so even once a release exists, downloads trip Gatekeeper with "AutoSuggest is damaged" — fatal first contact for an app that asks for Accessibility + Input Monitoring. The maintainer has an Apple Developer account and has decided (LAUNCH_AUDIT, "Decisions already locked") to do proper Developer ID signing + notarization. This plan rewrites the release workflow to: test → build signed → DMG → notarize → staple → publish.

## Current state

- `.github/workflows/release.yml` (65 lines) — triggers on `v*` tags; steps: checkout → `brew install xcodegen` → `xcodegen generate` (in `macos/`) → `xcodebuild build` with:

  ```yaml
  # release.yml:27-35
  xcodebuild build \
    -project AutoSuggestDesktop.xcodeproj \
    -scheme AutoSuggestDesktop \
    -configuration Release \
    -derivedDataPath build \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO
  ```

  then locate `.app` → `hdiutil create` DMG → zip → `softprops/action-gh-release@v2`. **No test step. No signing. No notarization.**
- `macos/project.yml` — relevant settings already in place: `ENABLE_HARDENED_RUNTIME: YES`, `CODE_SIGN_ENTITLEMENTS: AutoSuggestDesktop/AutoSuggest.entitlements`, `CODE_SIGN_STYLE: Automatic`, `DEVELOPMENT_TEAM: ""`, `PRODUCT_BUNDLE_IDENTIFIER: dev.autosuggest.desktop`, `MARKETING_VERSION: 0.1.0`.
- `macos/AutoSuggestDesktop/AutoSuggest.entitlements` — `com.apple.security.app-sandbox: false` (required for AX/event taps; fine for Developer ID), `com.apple.security.automation.apple-events: true`. Compatible with hardened runtime + notarization as-is.
- `git tag` → empty; `gh release list` → empty.
- Required GitHub Actions **secrets** (names used below; values supplied by the maintainer, NEVER committed):
  - `MACOS_CERT_P12_BASE64` — base64 of the Developer ID Application cert + key (.p12)
  - `MACOS_CERT_PASSWORD` — .p12 password
  - `APPLE_TEAM_ID` — 10-char team ID
  - `APPLE_ID` — Apple ID email for notarytool
  - `APPLE_APP_SPECIFIC_PASSWORD` — app-specific password for notarytool

## Commands you will need

| Purpose   | Command       | Expected on success |
|-----------|---------------|---------------------|
| Tests     | `swift test`  | all pass            |
| Workflow YAML check | `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))"` | no error |
| (post-tag, maintainer machine) Gatekeeper check | `spctl -a -vvv -t install /Applications/AutoSuggest.app` | `accepted` + `source=Notarized Developer ID` |

## Scope

**In scope** (the only files you should modify):
- `.github/workflows/release.yml`
- `plans/README.md` (status row)

**Out of scope** (do NOT touch, even though they look related):
- `macos/project.yml` — keep `CODE_SIGN_STYLE: Automatic` for local dev; CI overrides signing via xcodebuild flags.
- `scripts/install.sh` — works as-is once releases exist; adding a `codesign --verify` step there is a noted follow-up.
- `website/index.html` download links — they already point at `releases/latest`.
- `.github/workflows/ci.yml` — plan 007's file.
- Creating the actual tag/release — that is the maintainer's action after secrets are configured (Step 6 tells them exactly what to do).

## Git workflow

- Branch: `advisor/008-signed-release`
- One commit for the workflow rewrite; message style: short imperative summary.
- Do NOT push or open a PR unless the operator instructed it. Do NOT create tags.

## Steps

### Step 1: Add a preflight + test job

Rewrite `.github/workflows/release.yml` as two jobs: `test` then `build-sign-notarize` (`needs: test`). The test job runs `swift test` on `macos-14`. The build job starts with a preflight step that fails fast with a readable error if any secret is missing:

```yaml
- name: Preflight secrets
  env:
    CERT: ${{ secrets.MACOS_CERT_P12_BASE64 }}
    CERT_PW: ${{ secrets.MACOS_CERT_PASSWORD }}
    TEAM: ${{ secrets.APPLE_TEAM_ID }}
    AID: ${{ secrets.APPLE_ID }}
    APW: ${{ secrets.APPLE_APP_SPECIFIC_PASSWORD }}
  run: |
    for v in CERT CERT_PW TEAM AID APW; do
      if [ -z "${!v}" ]; then echo "::error::Missing release secret for $v — see plans/008 'Current state' for the list"; exit 1; fi
    done
```

### Step 2: Import the signing certificate into a temporary keychain

```yaml
- name: Import Developer ID certificate
  env:
    MACOS_CERT_P12_BASE64: ${{ secrets.MACOS_CERT_P12_BASE64 }}
    MACOS_CERT_PASSWORD: ${{ secrets.MACOS_CERT_PASSWORD }}
  run: |
    KEYCHAIN=build.keychain
    KEYCHAIN_PW=$(uuidgen)
    echo "$MACOS_CERT_P12_BASE64" | base64 --decode > cert.p12
    security create-keychain -p "$KEYCHAIN_PW" $KEYCHAIN
    security default-keychain -s $KEYCHAIN
    security unlock-keychain -p "$KEYCHAIN_PW" $KEYCHAIN
    security set-keychain-settings -t 3600 -u $KEYCHAIN
    security import cert.p12 -k $KEYCHAIN -P "$MACOS_CERT_PASSWORD" -T /usr/bin/codesign
    security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PW" $KEYCHAIN
    rm cert.p12
```

### Step 3: Build signed with hardened runtime

Keep xcodegen generation as today, then replace the unsigned build flags:

```yaml
- name: Build signed app
  working-directory: macos
  env:
    APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
  run: |
    xcodebuild build \
      -project AutoSuggestDesktop.xcodeproj \
      -scheme AutoSuggestDesktop \
      -configuration Release \
      -derivedDataPath build \
      CODE_SIGN_STYLE=Manual \
      CODE_SIGN_IDENTITY="Developer ID Application" \
      DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
      OTHER_CODE_SIGN_FLAGS="--timestamp" \
      ENABLE_HARDENED_RUNTIME=YES
- name: Verify signature
  working-directory: macos
  run: |
    APP_PATH=$(find build -name "AutoSuggest.app" -type d | head -1)
    codesign --verify --deep --strict --verbose=2 "$APP_PATH"
    codesign -d --entitlements - "$APP_PATH"
    echo "app_path=$APP_PATH" >> "$GITHUB_OUTPUT"
  id: locate
```

### Step 4: DMG → notarize → staple

Keep the existing `hdiutil create` DMG step (staging dir + UDZO), then add:

```yaml
- name: Notarize DMG
  env:
    APPLE_ID: ${{ secrets.APPLE_ID }}
    APPLE_APP_SPECIFIC_PASSWORD: ${{ secrets.APPLE_APP_SPECIFIC_PASSWORD }}
    APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
  run: |
    xcrun notarytool submit AutoSuggest.dmg \
      --apple-id "$APPLE_ID" \
      --password "$APPLE_APP_SPECIFIC_PASSWORD" \
      --team-id "$APPLE_TEAM_ID" \
      --wait --timeout 30m
- name: Staple
  run: |
    xcrun stapler staple AutoSuggest.dmg
    xcrun stapler validate AutoSuggest.dmg
```

For the ZIP artifact: staple the `.app` itself before zipping (`xcrun stapler staple "<app path>"`), then zip with `ditto -c -k --keepParent` (preserves resource forks/quarantine metadata better than `zip -r` — replace the existing zip step). Order: notarize DMG → staple DMG → staple app → ditto-zip app.

Note: the app inside the DMG was already part of the notarized DMG submission; stapling the standalone app uses the same notarization ticket (tickets attach to the bundle's code signature). If `stapler staple` on the app fails with "ticket not found", submit the zip for notarization as a second `notarytool submit` and staple after — include this fallback inline in the workflow with a comment.

### Step 5: Publish

Keep `softprops/action-gh-release@v2` with `generate_release_notes: true` and both artifacts. Final workflow job order: checkout → preflight → import cert → install xcodegen → generate → build signed → verify → DMG → notarize → staple → zip → release.

**Verify (steps 1–5 together)**: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))"` → no error. If `actionlint` is available, run it → exit 0. `git diff --name-only` → only `release.yml` (+ plans/README.md).

### Step 6: Hand-off instructions for the maintainer (include verbatim in your completion summary)

1. Export the **Developer ID Application** certificate (with private key) from Keychain Access as `.p12`; `base64 -i cert.p12 | pbcopy`.
2. Create the 5 repo secrets listed in "Current state" (`gh secret set MACOS_CERT_P12_BASE64`, etc.).
3. `git tag v0.1.0 && git push origin v0.1.0` — watch the workflow.
4. On a Mac that has never seen the build: download the DMG from the release page, open it, drag to /Applications, launch. Expect **no** Gatekeeper warning.
5. Run `spctl -a -vvv -t install /Applications/AutoSuggest.app` → `accepted`, `source=Notarized Developer ID`.
6. Run `bash scripts/install.sh` end-to-end → app installs and launches.
7. Update `docs/LAUNCH_AUDIT.md` items #1 and #2 to done.

## Test plan

No unit tests (workflow-only change). Gates: YAML validity + `actionlint` locally; the real verification is the maintainer's tag run (Step 6), which exercises every step including notarization.

## Done criteria

- [ ] `release.yml` contains: a `test` job, preflight secret check, cert import, `CODE_SIGN_IDENTITY="Developer ID Application"`, `codesign --verify`, `notarytool submit --wait`, `stapler staple` + `stapler validate`, `ditto -c -k` zip
- [ ] `grep -n "CODE_SIGNING_ALLOWED=NO" .github/workflows/release.yml` → no matches
- [ ] YAML parses; `actionlint` clean if available
- [ ] No secrets or secret *values* appear anywhere in the diff (`git diff | grep -iE "p12|password" ` shows only secret *references* `${{ secrets.* }}`)
- [ ] No files outside the in-scope list are modified (`git status`)
- [ ] `plans/README.md` status row updated (status: DONE-pending-tag — note the maintainer action)

## STOP conditions

Stop and report back (do not improvise) if:
- `release.yml` no longer matches the "Current state" structure.
- You are tempted to commit any certificate, password, or base64 blob — never; secrets exist only in GitHub Actions secrets.
- You cannot validate YAML locally (no python3/actionlint) — say so rather than shipping unvalidated YAML.
- The operator asks you to create the tag/release yourself — that requires the secrets to exist first; per scope it's the maintainer's step.

## Maintenance notes

- After the first successful notarized release: add `codesign --verify` + `spctl` checks to `scripts/install.sh` (LAUNCH_AUDIT item #7 follow-up), and consider Sparkle auto-updates (see plan 009's sibling direction notes in `plans/README.md` — Sparkle requires exactly this signing setup as a prerequisite).
- Reviewer should scrutinize: that the temp keychain is the default during codesign, the `--timestamp` flag (notarization rejects unsigned timestamps), and the ditto-vs-zip artifact step.
- Re-tagging: notarytool submissions are idempotent per binary; re-running on the same tag after a failed notarize is safe.
- The CI build job runs on `macos-14` — if Xcode on the runner ever defaults below the Swift 6.2 toolchain the package needs, add `xcode-select` pinning (`maxim-lobanov/setup-xcode`) — not needed at the time of writing (CI currently builds fine on macos-14).
