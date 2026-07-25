# UI Overhaul — Phase 3: MenuBarExtra Conversion

**Date:** 2026-07-25
**Status:** Approved (design), pending implementation plan
**Branch:** `ui-overhaul-phase3`
**Depends on:** Phase 1 (`fb2a604`) + Phase 2 (`40fd99b`), both merged to `main`.

## Context

Phase 3 of the five-phase UI overhaul. It converts the macOS app's menu-bar surface from
imperative AppKit (`NSStatusItem` + `NSPopover` + a right-click overflow `NSMenu`) to the
native SwiftUI `MenuBarExtra(.window)` idiom, and collapses the two action surfaces into one.

Today (`Sources/AutoSuggestApp/App/StatusBarController.swift`): left-click opens an
`NSPopover` hosting `StatusPopoverView`; right-click opens an overflow `NSMenu` that
duplicates Settings/Quit and *uniquely* holds About + Export Diagnostics. The right-click
surface is undiscoverable and inconsistent.

Key constraints discovered in the code:
- `MenuBarExtra(.window)` is macOS 13+. Both targets already deploy to 13.0. ✓
- `uiModel` (`AutoSuggestUIModel`, an `ObservableObject`) is created **async** inside
  `AppCoordinator.start()` (after config load, before onboarding). A SwiftUI `Scene` needs it.
- `StatusBarController` is shared: the macOS app **and** the SwiftPM `AutoSuggestRunner`
  (via the library `AppDelegate`) both use it, both through `AppCoordinator`. So it cannot be
  deleted — and `AppCoordinator` must stop eagerly owning it, or the macOS app would show two
  menu-bar icons.
- Phase 2 shipped custom AppKit icon compositing (the brand ghost + status badge) inside
  `StatusBarController`. That logic must be preserved and shared, not rewritten.

## Goals

- macOS app menu bar becomes `MenuBarExtra(.window)` hosting `StatusPopoverView`.
- **One** action surface: drop the overflow `NSMenu`; fold About + Export Diagnostics into the
  popover. `StatusPopoverView`'s custom `QuickActionButton` rows become native controls; the
  fixed `368pt` width is dropped for content-driven sizing.
- Decouple the menu bar from `AppCoordinator`: it stops owning `StatusBarController`; each
  entry point wires its own surface.
- Preserve the Phase 2 badge visuals by extracting the compositing into a shared renderer.
- Keep the SwiftPM runner working (still shows a status item via `StatusBarController`).

## Non-Goals

- No changes to the pipeline, inference, policy, config, or privacy logic.
- Onboarding (Phase 4) and the About window (Phase 5) stay imperative/as-is — still opened via
  `uiModel` callbacks; not converted to scenes.
- No change to the badge *visuals* (extraction only).
- The runner's menu-bar path is preserved, not enhanced.

## Design

### 1. Extract the icon renderer (shared)

Move the icon compositing out of `StatusBarController` into a pure, reusable type:

`enum MenuBarIconRenderer` (`Sources/AutoSuggestApp/App/MenuBarIconRenderer.swift`) with
`static func image(for state: MenuBarIconState) -> NSImage` — containing the current
`ghostBaseImage`, `badgedGhostImage` (deferred `drawingHandler`), `tinted`, `badgeColor`, and
`brandAmber` from `StatusBarController`, unchanged in behavior. Both `StatusBarController`
(runner) and `AppModel` (macOS app) render icons through it. `MenuBarIconState` +
`MenuBarBadge` (Phase 2) are unchanged.

### 2. Decouple the menu bar from `AppCoordinator`

- Remove the `let statusBarController = StatusBarController()` property (line 19) and its two
  call sites: `statusBarController.configure(with:)` (line 83) and `refreshAppearance()`
  (line 364).
- Add a hook `var onUIModelReady: ((AutoSuggestUIModel) -> Void)?` on `AppCoordinator`,
  invoked in `start()` immediately after `self.uiModel = uiModel` / `bindUIModel(uiModel)`
  (≈ line 82) — **before** the onboarding continuation blocks, so the menu bar can appear
  independent of onboarding.
- Expose it on the public library entry point: `AutoSuggestService.onUIModelReady`
  (forwarding to the coordinator, like the existing `onCheckForUpdates`).

### 3. macOS app → `MenuBarExtra` (`macos/AutoSuggestDesktop/`)

Introduce `@MainActor final class AppModel: ObservableObject` (new file
`macos/AutoSuggestDesktop/AppModel.swift`) as the single startup owner:
- Owns the `AutoSuggestService` and Sparkle `SPUStandardUpdaterController` (both moved out of
  `HostDelegate`); sets `NSApp.setActivationPolicy(.accessory)`.
- In a `start()` run from the App's `.task`: wires `service.onCheckForUpdates` to Sparkle and
  `service.onUIModelReady = { [weak self] in self?.uiModel = $0 }`, then `await service.start()`.
- `@Published private(set) var uiModel: AutoSuggestUIModel?`.
- `var menuBarIcon: NSImage` — computed from `uiModel` (via `MenuBarIconState.resolve` +
  `MenuBarIconRenderer.image(for:)`); falls back to the plain ghost when `uiModel` is nil.

The App:
```swift
@main struct AutoSuggestDesktopApp: App {
    @StateObject private var app = AppModel()
    var body: some Scene {
        MenuBarExtra {
            if let uiModel = app.uiModel {
                StatusPopoverView(uiModel: uiModel)
            } else {
                StartingView()   // minimal "Starting AutoSuggest…" placeholder
            }
        } label: {
            Image(nsImage: app.menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }
}
```
`HostDelegate` is removed (its responsibilities move to `AppModel`). `StartingView` is a tiny
placeholder view shown only during the brief pre-ready window.

Reactivity: because `AppModel` is a `@StateObject` and `uiModel` is `@Published`, the label
image recomputes when `uiModel` publishes (permission/enabled changes flow through
`uiModel.objectWillChange`). No manual `refreshAppearance()`.

### 4. Runner keeps `StatusBarController` (`Sources/AutoSuggestApp/App/AppDelegate.swift`)

- The library `AppDelegate` now creates and owns a `StatusBarController`, and wires it via
  `service.onUIModelReady = { statusBarController.configure(with: $0) }`.
- `StatusBarController.refreshAppearance()` is no longer called by `AppCoordinator`. Instead,
  in `configure(with:)`, `StatusBarController` subscribes to `uiModel.objectWillChange` (Combine)
  and calls `refreshAppearance()` itself on change, so its icon stays current without coordinator
  involvement. It renders via `MenuBarIconRenderer.image(for:)`.
- `StatusBarController` keeps its `NSPopover` + overflow `NSMenu` for the runner (the runner is a
  dev harness; consolidating its surface is out of scope). Only the macOS app drops the overflow
  menu, by virtue of using `MenuBarExtra`.

### 5. Single action surface — `StatusPopoverView` (`Sources/AutoSuggestApp/UI/`)

- Add **About** and **Export Diagnostics** actions so the popover is complete on its own. About
  is triggered via a new `uiModel.onShowAbout` hook (wired by `AppCoordinator` to
  `AboutWindowController.shared.showWindow()`); Export via the existing `uiModel.exportDiagnostics()`.
- Replace the custom `QuickActionButton` rows with native controls (plain `Button`s in a
  `VStack`/`Form`-like layout), keeping the existing actions (Open Settings, Pause 1h, Exclude
  App, Retry Model, Check Updates, Quit) plus the two folded-in ones.
- Drop the hardcoded `.frame(width: 368)`; let content drive width (with a sensible `minWidth`
  so it doesn't collapse). Keep the status `GroupBox` table and the Suggestions toggle.

## New / changed interfaces

- `enum MenuBarIconRenderer { static func image(for: MenuBarIconState) -> NSImage }` — pure.
- `AppCoordinator.onUIModelReady: ((AutoSuggestUIModel) -> Void)?`
- `AutoSuggestService.onUIModelReady: ((AutoSuggestUIModel) -> Void)?` (forwards).
- `AutoSuggestUIModel.onShowAbout: (() -> Void)?`
- `AppModel` (macOS target): `@Published private(set) var uiModel`, `var menuBarIcon: NSImage`.

## Testing

- `swift build` exits 0; `swift test` all green (baseline 297); `swiftformat Sources Tests --lint`
  clean — after every task.
- **New unit test** `MenuBarIconRendererTests`: `image(for:)` returns a non-nil image for every
  `MenuBarIconState`; `.active` returns a template image (`isTemplate == true`), badged states
  return non-template (`isTemplate == false`). `MenuBarIconState`/`MenuBarBadge` tests stay green.
- `AppModel` and the SwiftUI scene are not unit-testable (SwiftUI/AppKit lifecycle); verified
  manually via the Xcode app target: cold launch shows the icon, single click opens the popover
  window, every action works (Settings, Pause, Exclude, Retry, Check Updates, **About**,
  **Export Diagnostics**, Quit), the badge still reflects paused / needs-permission, and there is
  **no** right-click menu. Also verify `swift run AutoSuggestRunner` still shows a working status
  item (the runner path).

## Risks

- **Startup ordering** is the primary risk: `uiModel` is nil at first paint. Mitigated by the
  `StartingView` placeholder + plain-ghost fallback icon, and by firing `onUIModelReady` early
  (before onboarding blocks).
- **Lifecycle move** (service + Sparkle + activation policy from `HostDelegate` → `AppModel`):
  verify Sparkle "Check for Updates…" still works and the app stays a Dock-less accessory
  (`.accessory` set in `AppModel`; confirm no Dock icon regresses).
- **Two menu-bar code paths** now exist (MenuBarExtra for the app, `StatusBarController` for the
  runner). Accepted per the runner decision; the shared `MenuBarIconRenderer` keeps the icon
  single-sourced.
- **`AppCoordinator` is load-bearing** — the decoupling removes 3 lines and adds one hook; the
  full pipeline wiring is untouched. The 297-test baseline guards regressions in the library.
- `MenuBarExtra(.window)` windows are system-positioned (no custom anchoring like the old
  popover). Accepted.
