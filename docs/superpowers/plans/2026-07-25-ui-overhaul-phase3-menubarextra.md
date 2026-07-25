# UI Overhaul — Phase 3: MenuBarExtra Conversion — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert the macOS app's menu bar to native `MenuBarExtra(.window)` with a single action surface, while decoupling the menu bar from `AppCoordinator` and keeping the SwiftPM runner's `StatusBarController` working.

**Architecture:** Extract the icon compositing into a shared `MenuBarIconRenderer`. Decouple the menu bar from `AppCoordinator` (it stops owning `StatusBarController`; a new `onUIModelReady` hook hands the async-born `uiModel` to whichever entry point owns the surface). The runner's `AppDelegate` owns `StatusBarController`; the macOS app introduces an `AppModel` that owns startup and hosts a `MenuBarExtra` scene. `StatusPopoverView` gains the folded-in actions and goes native.

**Tech Stack:** Swift, SwiftUI (`MenuBarExtra`, macOS 13+), AppKit, Combine, Sparkle (app target), XCTest, SwiftFormat 0.61.x.

## Global Constraints

- `swift build` exits 0 after every task (builds the SwiftPM library + runner).
- `swift test` — all tests green after every task (baseline 297).
- `swiftformat Sources Tests --lint` reports `0/… files require formatting` after every task (paths before the flag).
- **The macOS app target lives in `macos/` and is NOT built by `swift build`.** Any task touching `macos/AutoSuggestDesktop/` must additionally build it: `cd macos && xcodegen generate && xcodebuild -project AutoSuggestDesktop.xcodeproj -scheme AutoSuggestDesktop -configuration Debug build` (exit 0).
- Test files mirror source names under `Tests/AutoSuggestAppTests/`, `@testable import AutoSuggestApp`.
- No pipeline/inference/policy/config/privacy logic changes. Menu-bar surface + bootstrap only.
- macOS 13.0 deployment floor (both targets already set).
- Branch: `ui-overhaul-phase3`.

---

### Task 1: Extract `MenuBarIconRenderer`

**Files:**
- Create: `Sources/AutoSuggestApp/App/MenuBarIconRenderer.swift`
- Modify: `Sources/AutoSuggestApp/App/StatusBarController.swift` (use the renderer; remove the moved helpers)
- Test: `Tests/AutoSuggestAppTests/MenuBarIconRendererTests.swift`

**Interfaces:**
- Produces: `enum MenuBarIconRenderer { static func image(for state: MenuBarIconState) -> NSImage }`. Consumes `MenuBarIconState` + `MenuBarBadge` (Phase 2, unchanged). Later tasks (2, 4) render icons through it.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/AutoSuggestAppTests/MenuBarIconRendererTests.swift
import AppKit
import XCTest
@testable import AutoSuggestApp

final class MenuBarIconRendererTests: XCTestCase {
    func testProducesImageForEveryState() {
        for state in [MenuBarIconState.active, .paused, .needsPermission] {
            let image = MenuBarIconRenderer.image(for: state)
            XCTAssertGreaterThan(image.size.width, 0, "empty image for \(state)")
        }
    }

    func testActiveIsTemplateBadgedIsNot() {
        XCTAssertTrue(MenuBarIconRenderer.image(for: .active).isTemplate)
        XCTAssertFalse(MenuBarIconRenderer.image(for: .paused).isTemplate)
        XCTAssertFalse(MenuBarIconRenderer.image(for: .needsPermission).isTemplate)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MenuBarIconRendererTests`
Expected: FAIL — `MenuBarIconRenderer` undefined.

- [ ] **Step 3: Create the renderer**

Create `MenuBarIconRenderer.swift` by MOVING these members out of `StatusBarController` verbatim (they are currently `private static` funcs/lets on `StatusBarController`): `ghostBaseImage()`, `badgedGhostImage(_:)`, `tinted(_:_:)`, `badgeColor(for:)`, `brandAmber`. Wrap them in an enum and add the `image(for:)` entry point:

```swift
// Sources/AutoSuggestApp/App/MenuBarIconRenderer.swift
import AppKit

/// Renders the menu-bar glyph for a given state: a clean monochrome template
/// ghost when active, or a colored composite with a stacked status badge for
/// attention states. Shared by the macOS app (MenuBarExtra) and the SwiftPM
/// runner (StatusBarController).
enum MenuBarIconRenderer {
    static func image(for state: MenuBarIconState) -> NSImage {
        guard let badge = state.badge else {
            let ghost = ghostBaseImage() ?? NSImage()
            ghost.isTemplate = true
            return ghost
        }
        return badgedGhostImage(badge)
    }

    // ↓ moved verbatim from StatusBarController (make them `static` on this enum):
    //   ghostBaseImage(), badgedGhostImage(_:), tinted(_:_:), badgeColor(for:), brandAmber
}
```

Move the bodies exactly as they are in `StatusBarController` today (the deferred-`drawingHandler` `badgedGhostImage`, the `tinted` isolate-tint helper, `badgeColor`, the `brandAmber` dynamic `NSColor`, and `ghostBaseImage` with its `MenuBarGhost`/`text.cursor` fallback). Do not alter their behavior.

- [ ] **Step 4: Rewire `StatusBarController` to the renderer**

In `StatusBarController.refreshAppearance()`, replace the local `menuBarImage(for:)` call and delete the now-moved `menuBarImage(for:)`, `ghostBaseImage()`, `badgedGhostImage(_:)`, `tinted(_:_:)`, `badgeColor(for:)`, and `brandAmber` from `StatusBarController`. The state switch becomes:

```swift
        let image = MenuBarIconRenderer.image(for: state)
        image.accessibilityDescription = state.tooltip
        button.image = image
        button.title = ""
        button.toolTip = state.tooltip
```

- [ ] **Step 5: Run test + full verify**

Run: `swift test --filter MenuBarIconRendererTests && swift build && swiftformat Sources Tests --lint && swift test`
Expected: renderer tests PASS; build 0; lint clean; all green (baseline 297 + 2 new).

- [ ] **Step 6: Commit**

```bash
git add Sources/AutoSuggestApp/App/MenuBarIconRenderer.swift Sources/AutoSuggestApp/App/StatusBarController.swift Tests/AutoSuggestAppTests/MenuBarIconRendererTests.swift
git commit -m "refactor(ui): extract MenuBarIconRenderer from StatusBarController"
```

---

### Task 2: Decouple the menu bar from `AppCoordinator`; runner owns `StatusBarController`

**Files:**
- Modify: `Sources/AutoSuggestApp/App/AppCoordinator.swift` (remove `statusBarController`; add `onUIModelReady`; remove the `refreshAppearance()` call)
- Modify: `Sources/AutoSuggestApp/App/AutoSuggestService.swift` (forward `onUIModelReady`)
- Modify: `Sources/AutoSuggestApp/App/AppDelegate.swift` (runner: own + wire `StatusBarController`)
- Modify: `Sources/AutoSuggestApp/App/StatusBarController.swift` (self-refresh via `uiModel.objectWillChange`)
- Modify: `Sources/AutoSuggestApp/UI/AutoSuggestUIModel.swift` (add `onShowAbout` hook)
- Modify: `Sources/AutoSuggestApp/App/AppCoordinator.swift` (wire `onShowAbout` in `bindUIModel`)
- Test: none new (verified by build + 297 baseline; the hook needs live startup to fire).

**Interfaces:**
- Consumes: `MenuBarIconRenderer` (Task 1); `AboutWindowController.shared.showWindow()`.
- Produces:
  - `AppCoordinator.onUIModelReady: ((AutoSuggestUIModel) -> Void)?`
  - `AutoSuggestService.onUIModelReady: ((AutoSuggestUIModel) -> Void)?` (forwards to coordinator)
  - `AutoSuggestUIModel.onShowAbout: (() -> Void)?`
  Later: Task 4 sets `service.onUIModelReady`; Task 3 (popover) calls `uiModel.onShowAbout`.

- [ ] **Step 1: Add the `onUIModelReady` hook to `AppCoordinator` and fire it**

In `AppCoordinator.swift`: delete the property `let statusBarController = StatusBarController()` (line ~19). Add near `onCheckForUpdates` (≈ line 62):

```swift
    /// Invoked once, as soon as the UI model exists (before onboarding), so the
    /// host's menu-bar surface can bind without owning the coordinator.
    var onUIModelReady: ((AutoSuggestUIModel) -> Void)?
```

In `start()`, remove `statusBarController.configure(with: uiModel)` (line ~83) and insert, right after `bindUIModel(uiModel)`:

```swift
        onUIModelReady?(uiModel)
```

Remove the `statusBarController.refreshAppearance()` line (≈ line 364 in the quick-panel refresh).

- [ ] **Step 2: Forward the hook on `AutoSuggestService`**

In `AutoSuggestService.swift`, add alongside `onCheckForUpdates`:

```swift
    public var onUIModelReady: ((AutoSuggestUIModel) -> Void)? {
        get { coordinator.onUIModelReady }
        set { coordinator.onUIModelReady = newValue }
    }
```

`AutoSuggestUIModel` is already `public` (the UI consumes it); if not, make it and this hook's type public as needed for the app target to reference it.

- [ ] **Step 3: Add `onShowAbout` to the UI model + wire it**

In `AutoSuggestUIModel.swift`, add a hook property (near the other `on…` callbacks):

```swift
    var onShowAbout: (() -> Void)?
```

and a method:

```swift
    func showAbout() {
        onShowAbout?()
    }
```

In `AppCoordinator.bindUIModel(_:)`, wire it:

```swift
        uiModel.onShowAbout = { AboutWindowController.shared.showWindow() }
```

- [ ] **Step 4: Runner `AppDelegate` owns and wires `StatusBarController`**

Rewrite `AppDelegate.swift` so the runner keeps its status item now that the coordinator no longer creates one:

```swift
// Sources/AutoSuggestApp/App/AppDelegate.swift
import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let service: AutoSuggestService
    private let statusBarController = StatusBarController()

    init(service: AutoSuggestService) {
        self.service = service
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        service.onUIModelReady = { [statusBarController] uiModel in
            statusBarController.configure(with: uiModel)
        }
        Task {
            await service.start()
        }
    }
}
```

- [ ] **Step 5: `StatusBarController` self-refreshes on model changes**

`StatusBarController` currently relies on `AppCoordinator` calling `refreshAppearance()`. Make it observe the model instead. Add `import Combine`, a `private var cancellables = Set<AnyCancellable>()`, and at the end of `configure(with:)`:

```swift
        uiModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshAppearance() }
            .store(in: &cancellables)
```

(`objectWillChange` fires before the change is applied; `receive(on: RunLoop.main)` defers the refresh to the next runloop tick so `refreshAppearance` reads post-change state.)

- [ ] **Step 6: Verify build + lint + tests**

Run: `swift build && swiftformat Sources Tests --lint && swift test`
Expected: build 0, lint clean, all green (297).

- [ ] **Step 7: Commit**

```bash
git add Sources/AutoSuggestApp/App/AppCoordinator.swift Sources/AutoSuggestApp/App/AutoSuggestService.swift Sources/AutoSuggestApp/App/AppDelegate.swift Sources/AutoSuggestApp/App/StatusBarController.swift Sources/AutoSuggestApp/UI/AutoSuggestUIModel.swift
git commit -m "refactor(app): decouple menu bar from AppCoordinator via onUIModelReady hook"
```

---

### Task 3: Rework `StatusPopoverView` (single native action surface)

**Files:**
- Modify: `Sources/AutoSuggestApp/UI/StatusPopoverView.swift`
- Test: none (structural; shared by runner popover + app MenuBarExtra).

**Interfaces:** Consumes `uiModel.onShowAbout`/`showAbout()` and `uiModel.exportDiagnostics()` (existing) (Task 2).

- [ ] **Step 1: Fold in actions, go native, drop the fixed width**

Replace the custom `QuickActionButton` action stack (lines ~73–104) with native `Button`s, and add **About** and **Export Diagnostics**. Delete the `private struct QuickActionButton` entirely. Target for the action block:

```swift
            VStack(alignment: .leading, spacing: 4) {
                Button("Open Settings…") { uiModel.openSettings(.general) }
                Button("Pause for 1 Hour") { uiModel.pauseForHour() }
                Button("Exclude Current App") { uiModel.excludeFrontmostApp() }
                if uiModel.modelHealth.lastError != nil {
                    Button("Retry Model") { uiModel.retryModel() }
                }
                if uiModel.canCheckForUpdates {
                    Button("Check for Updates…") { uiModel.checkForUpdates() }
                }
                Divider()
                Button("About AutoSuggest") { uiModel.showAbout() }
                Button("Export Diagnostics…") { uiModel.exportDiagnostics() }
                Divider()
                Button("Quit AutoSuggest") { uiModel.quitApp() }
            }
            .buttonStyle(.link)
            .frame(maxWidth: .infinity, alignment: .leading)
```

Keep the existing accessibility hints by attaching `.accessibilityHint(...)` to the corresponding buttons (preserve the hint strings that were on the old `QuickActionButton`s: Open Settings → "Opens the settings window", Pause → "Pauses suggestions for one hour", Exclude → "Adds the frontmost app to the exclusion list", Retry → "Retries loading the inference model", Check for Updates → "Checks for a new version of AutoSuggest", Quit → "Quits the application"). Give the two new buttons hints: About → "Shows app version and links", Export Diagnostics → "Saves a diagnostics report to a file".

At the root, replace `.frame(width: 368)` with a content-driven width floor:

```swift
        .padding(16)
        .frame(minWidth: 300, maxWidth: 360, alignment: .leading)
        .autoSuggestTinted()
```

Keep the banner, status header, pause panel, Suggestions toggle, and the status `GroupBox` exactly as they are.

- [ ] **Step 2: Verify build + lint + tests**

Run: `swift build && swiftformat Sources Tests --lint && swift test`
Expected: build 0, lint clean, all green (297).

- [ ] **Step 3: Commit**

```bash
git add Sources/AutoSuggestApp/UI/StatusPopoverView.swift
git commit -m "feat(ui): single native action surface in status popover (About + Export folded in)"
```

---

### Task 4: macOS app → `MenuBarExtra` (`AppModel` + scene)

**Files:**
- Create: `macos/AutoSuggestDesktop/AppModel.swift`
- Modify: `macos/AutoSuggestDesktop/AutoSuggestDesktopApp.swift` (MenuBarExtra scene; delete `HostDelegate`; drop empty `Settings` scene)
- Test: none unit (SwiftUI/AppKit lifecycle); verified by `xcodebuild` + manual.

**Interfaces:** Consumes `AutoSuggestService.onUIModelReady`/`onCheckForUpdates` (Task 2), `MenuBarIconRenderer.image(for:)` (Task 1), `MenuBarIconState.resolve(permissionsReady:enabled:)`, `StatusPopoverView` (Task 3).

- [ ] **Step 1: Create `AppModel`**

```swift
// macos/AutoSuggestDesktop/AppModel.swift
import AppKit
import Combine
import Sparkle
import SwiftUI
import AutoSuggestApp

/// Owns app startup for the MenuBarExtra app: the service, the Sparkle updater,
/// activation policy, and the published UI model that the menu-bar scene binds to.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var uiModel: AutoSuggestUIModel?

    private let service = AutoSuggestService()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    private var uiModelObservation: AnyCancellable?

    init() {
        NSApp.setActivationPolicy(.accessory)
        service.onCheckForUpdates = { [weak self] in
            self?.updaterController.updater.checkForUpdates()
        }
        service.onUIModelReady = { [weak self] uiModel in
            guard let self else { return }
            self.uiModel = uiModel
            // Forward model changes so the menu-bar icon label recomputes.
            self.uiModelObservation = uiModel.objectWillChange
                .sink { [weak self] _ in self?.objectWillChange.send() }
        }
        Task { await service.start() }
    }

    /// The menu-bar glyph for the current state; a plain ghost until the model
    /// exists.
    var menuBarIcon: NSImage {
        guard let uiModel else { return MenuBarIconRenderer.image(for: .active) }
        let state = MenuBarIconState.resolve(
            permissionsReady: uiModel.permissionHealth.isReady,
            enabled: uiModel.config.enabled
        )
        return MenuBarIconRenderer.image(for: state)
    }
}
```

Note: `MenuBarIconRenderer`, `MenuBarIconState`, and `AutoSuggestUIModel` must be `public` for the app target to reference them. If the build reports them as internal, make them (and the members used here: `MenuBarIconState.resolve`, `.active`, `permissionHealth.isReady`, `config.enabled`) `public` in the library — this is a legitimate part of this task.

- [ ] **Step 2: Rewrite the App scene**

```swift
// macos/AutoSuggestDesktop/AutoSuggestDesktopApp.swift
import SwiftUI
import AutoSuggestApp

@main
struct AutoSuggestDesktopApp: App {
    @StateObject private var app = AppModel()

    var body: some Scene {
        MenuBarExtra {
            if let uiModel = app.uiModel {
                StatusPopoverView(uiModel: uiModel)
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Starting AutoSuggest…").foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(width: 260)
            }
        } label: {
            Image(nsImage: app.menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }
}
```

Delete the `HostDelegate` class and the `@NSApplicationDelegateAdaptor` and the old `Settings { EmptyView() }` scene (all in this file). `StatusPopoverView` is `public` already (used cross-module); if not, make it `public` in the library.

- [ ] **Step 3: Build the macOS app**

Run:
```bash
cd macos && xcodegen generate && xcodebuild -project AutoSuggestDesktop.xcodeproj -scheme AutoSuggestDesktop -configuration Debug build
```
Expected: `BUILD SUCCEEDED`. Fix any `public`-access errors by widening the referenced library symbols (Step 1 note).

- [ ] **Step 4: Verify the library still builds + tests + lint**

Run: `swift build && swiftformat Sources Tests --lint && swift test`
Expected: build 0, lint clean, all green (297) — the library changes (public widening) must not regress.

- [ ] **Step 5: Commit**

```bash
git add macos/AutoSuggestDesktop/AppModel.swift macos/AutoSuggestDesktop/AutoSuggestDesktopApp.swift Sources
git commit -m "feat(app): menu bar as MenuBarExtra(.window) via AppModel; retire HostDelegate"
```

---

## Manual verification (after Task 4, before merge)

Not unit-testable; the controller runs these via the Xcode app:
1. Cold launch → the brand ghost icon appears in the menu bar (badge reflects needs-permission on an un-granted build).
2. Single click opens the popover window; no right-click menu exists.
3. Every action works: Open Settings, Pause 1h, Exclude App, Retry (when erroring), Check for Updates, **About**, **Export Diagnostics**, Quit.
4. Toggling Suggestions / granting permission updates the icon badge live.
5. App has no Dock icon (accessory).
6. `swift run AutoSuggestRunner` still shows a working status item with its popover (the runner path).

## Self-Review

**Spec coverage:**
- Extract shared icon renderer: Task 1. ✓
- macOS app → MenuBarExtra(.window): Task 4. ✓
- Single action surface (About + Export folded in, native controls, drop 368pt): Task 3. ✓
- Decouple menu bar from AppCoordinator (`onUIModelReady`): Task 2. ✓
- Runner keeps StatusBarController: Task 2 (AppDelegate owns it; self-refresh). ✓
- `AppModel` owns service + Sparkle + `.accessory`; publishes uiModel; reactive icon: Task 4. ✓
- Delete HostDelegate + empty Settings scene: Task 4. ✓
- `onShowAbout` hook: Task 2 (add+wire) → Task 3 (consume). ✓
- macOS app built via xcodebuild: Task 4 Step 3 + Global Constraints. ✓
- Startup placeholder (StartingView) + plain-ghost fallback: Task 4 (inline placeholder + `menuBarIcon` nil fallback). ✓

**Placeholder scan:** Task 1 moves named members verbatim (their bodies already exist in the repo and were shown in Phase 2); every new symbol (`onUIModelReady`, `onShowAbout`, `AppModel`, the scene) is shown as full code. No TBD/TODO.

**Type consistency:** `MenuBarIconRenderer.image(for:)` signature identical across Tasks 1, 2, 4. `onUIModelReady: ((AutoSuggestUIModel) -> Void)?` identical across Tasks 2 (coordinator+service) and 4 (consumer). `onShowAbout`/`showAbout()` defined Task 2, consumed Task 3. `MenuBarIconState.resolve(permissionsReady:enabled:)` matches the existing signature used in Phase 2.
