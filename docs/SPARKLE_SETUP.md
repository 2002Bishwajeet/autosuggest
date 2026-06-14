# Sparkle auto-update — maintainer activation checklist

AutoSuggest ships with the [Sparkle](https://sparkle-project.org) auto-update
framework wired in, but **disabled-by-default with placeholders** so it cannot
ship updates until you complete the steps below. Nothing in the repo contains a
real key or feed URL; everything here is the maintainer's (user-only) job.

## What's already wired (no action needed)

- **App target dependency** — Sparkle is declared in `macos/project.yml`
  (`packages: Sparkle` + the `AutoSuggestDesktop` dependency) and resolved into
  the committed `macos/AutoSuggestDesktop.xcodeproj`. It is intentionally **not**
  in the SwiftPM `Package.swift` (auto-update is an app-bundle concern).
- **Updater object** — `HostDelegate` in
  `macos/AutoSuggestDesktop/AutoSuggestDesktopApp.swift` creates an
  `SPUStandardUpdaterController(startingUpdater: true, …)`. With
  `SUEnableAutomaticChecks = true` and `SUScheduledCheckInterval = 86400`, it
  checks for updates once a day in the background.
- **Manual "Check for Updates…"** — because this is a menu-bar accessory app
  with no standard menu bar, the affordance lives in the status popover
  (`Sources/AutoSuggestApp/UI/StatusPopoverView.swift`). It calls back through
  `AutoSuggestService.onCheckForUpdates` → `updaterController.updater.checkForUpdates()`.
  The control only appears when the host wired the callback, so the SwiftPM
  runner is unaffected.
- **Release pipeline** — `.github/workflows/release.yml` has a
  `Generate & sign Sparkle appcast` step that runs **only** when the
  `SPARKLE_EDDSA_PRIVATE_KEY` secret is set. Until you add the secret, releases
  keep working exactly as before and no appcast is produced.

## Activation steps (do these once)

### (a) Generate the EdDSA key pair

Sparkle ships its tools in the "Sparkle binary utilities" archive on its
[releases page](https://github.com/sparkle-project/Sparkle/releases). Download
it, then run:

```sh
./bin/generate_keys
```

This creates an ed25519 key pair. The **private** key is stored in your login
keychain; `generate_keys` prints the **public** key to stdout. To re-print the
public key later, or to export the private key for CI, run:

```sh
./bin/generate_keys -p          # print the public key
./bin/generate_keys -x private-key.pem   # export the private key to a file
```

> Keep the private key secret. Anyone with it can sign updates your users will
> install. Never commit it.

### (b) Put the PUBLIC key in `Info.plist`

Edit `macos/AutoSuggestDesktop/Info.plist` and replace the placeholder:

```xml
<key>SUPublicEDKey</key>
<string>REPLACE_WITH_EDDSA_PUBLIC_KEY</string>
```

with the public key string from step (a). (If you regenerate
`AutoSuggestDesktop.xcodeproj`, the Info.plist is referenced, not copied, so this
edit persists.)

### (c) `SUFeedURL` — already set (no action)

`Info.plist` already points at
`https://github.com/2002Bishwajeet/autosuggest/releases/latest/download/appcast.xml`.
GitHub redirects `releases/latest/download/<asset>` to the newest release's
asset, so the feed is served straight from the GitHub Release with no extra
hosting. Only touch this if the repo moves.

### (d) Add the PRIVATE key as a GitHub secret

In the repo: **Settings → Secrets and variables → Actions → New repository
secret**.

- Name: `SPARKLE_EDDSA_PRIVATE_KEY`
- Value: the contents of the private key exported in step (a)
  (`generate_keys -x private-key.pem`).

Once this secret exists, the release workflow's appcast step activates on the
next tagged release: it downloads the Sparkle tools, runs `generate_appcast`
(feeding the key on stdin so it never touches disk), and produces a **signed**
`appcast.xml` — Sparkle writes the EdDSA signature and length into each
`<enclosure>`. The signed `appcast.xml` is attached to the GitHub Release for
inspection.

### (e) Appcast hosting — automated (no action)

On each tagged release the workflow generates the signed `appcast.xml` (with
each `<enclosure url>` pointing at that release's GitHub asset, via
`--download-url-prefix`) and **attaches it to the GitHub Release as an asset**.
Sparkle reads it through the `releases/latest/download/appcast.xml` redirect, so
there is no separate host to deploy and nothing to commit anywhere.

Confirm after your first activated release:

```sh
curl -fsSL https://github.com/2002Bishwajeet/autosuggest/releases/latest/download/appcast.xml | head -40
```

You should see a `<rss>` document whose `<enclosure>` tags carry
`sparkle:edSignature` + `length`, with `url`s on `github.com/.../releases/download/…`.

## Quick verification after activation

1. Tag a release (`git tag vX.Y.Z && git push --tags`) — the workflow signs the
   appcast and attaches it to the GitHub Release.
2. Install the **previous** signed/notarized build, then use the status popover's
   **Check for Updates…** — Sparkle should offer the new version and verify it
   against `SUPublicEDKey` before installing.
