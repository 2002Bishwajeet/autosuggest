# macOS App Target Setup

The repo now includes a dedicated macOS app wrapper under `macos/`.

## Recommended Workflow

1. Generate or refresh the Xcode project:

```bash
cd macos
xcodegen generate
```

2. Open [AutoSuggestDesktop.xcodeproj](/Users/biswa/Documents/GitHub/autosuggest/macos/AutoSuggestDesktop.xcodeproj).
3. Select scheme `AutoSuggestDesktop`.
4. Run the app with `Cmd+R`.
5. Grant:
   - Accessibility
   - Input Monitoring

This is now the preferred route because it gives AutoSuggest a stable app identity:
- bundle identifier: `dev.autosuggest.desktop`
- product name: `AutoSuggest`
- real `.app` bundle for TCC/Privacy & Security

## Project Layout

- project spec: [project.yml](/Users/biswa/Documents/GitHub/autosuggest/macos/project.yml)
- app entry: [AutoSuggestDesktopApp.swift](/Users/biswa/Documents/GitHub/autosuggest/macos/AutoSuggestDesktop/AutoSuggestDesktopApp.swift)
- plist: [Info.plist](/Users/biswa/Documents/GitHub/autosuggest/macos/AutoSuggestDesktop/Info.plist)

The app target links the local Swift package product `AutoSuggestApp` and starts the existing host service from the package.

## Verification Command

For command-line verification outside Xcode:

```bash
xcodebuild -project macos/AutoSuggestDesktop.xcodeproj \
  -scheme AutoSuggestDesktop \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build
```

In restricted environments you may need custom cache paths for `DerivedData` and SwiftPM caches.

## SwiftPM Runner

`swift run AutoSuggestRunner` still exists for fast package iteration, but it is no longer the recommended path for permissions or onboarding validation.

## Next Hardening Steps

1. Replace the placeholder bundle identifier with your real team/app identifier.
2. Enable signing in Xcode with your development team.
3. Add app icon assets.
4. Add release/archive configuration.
5. Add notarization once the app target is stable enough for distribution.
