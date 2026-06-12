# AutoSuggest Usability Pass — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the shipped `.app` usable for a normal developer: no main-thread freezes, permissions that update live and self-heal, a correct menu-bar icon, a non-blocking guided first run, and a tidy install.

**Architecture:** Six independently-shippable phases. Phase 1 (de-block the main thread) and Phase 2 (reactive, self-healing permissions) are the load-bearing foundations; the icon, onboarding, decomposition, and install phases build on them. We introduce one new testable unit (`RuntimeDetectionService`) and two pure decision functions (permission re-arm, menu-bar icon state) so the behavior can be unit-tested even though the AppKit/CGEvent/threading paths cannot run in CI (per `CLAUDE.md`).

**Tech Stack:** Swift 6, SwiftPM (`AutoSuggestApp` library + `AutoSuggestRunner` exe), AppKit + SwiftUI, XCTest, SwiftFormat 0.61.x, xcodegen for the `macos/` app shell.

---

## Conventions for every task

- **Build:** `swift build` (exit 0).
- **Test:** `swift test` (full suite; was 158 tests, all green at start).
- **Lint:** `swiftformat Sources Tests --lint` (must report `0/N files require formatting`). After editing, run `swiftformat Sources Tests` to auto-format, then re-lint.
- **Logging:** use `Logger(scope:)`, never `print`.
- **Guardrails (do NOT touch):** `PolicyEngine.swift` and `AXTextContextProvider` secure-field suppression (password-safety boundary); `PIIFilter`, `EncryptedFileStore`, telemetry content-free invariant; `ConfigMigrationManager` (only add a migration if a config schema field changes — none is expected here).
- **Manual-verification steps** (marked **[MANUAL]**) are intentional, not placeholders: AX/CGEvent/threading/SwiftUI-render behavior cannot be exercised in CI. They are verified by building the `macos/` app and running it. Use the `verify`/`run` skills.
- **Commit** after each task with the message shown.

---

# Phase 1 — De-block the main thread

**Outcome:** No synchronous filesystem I/O or subprocess calls run on the main actor. The 1-second refresh loop gathers off-main and publishes cheap snapshots.

**Root causes addressed:** `AppCoordinator.refreshUIState()` does synchronous disk I/O on `@MainActor` every second (`AppCoordinator.swift:299,304`); onboarding detection runs `Process().waitUntilExit()` on the main thread (`OnboardingFlowView.swift:843,935`).

## Task 1.1: `RuntimeDetectionService` — async, injectable runtime detection

**Files:**
- Create: `Sources/AutoSuggestApp/System/RuntimeDetectionService.swift`
- Test: `Tests/AutoSuggestAppTests/RuntimeDetectionServiceTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import AutoSuggestApp

final class RuntimeDetectionServiceTests: XCTestCase {
    func testNotInstalledWhenNoBinary() async {
        let service = RuntimeDetectionService(
            binaryExists: { _ in false },
            processRunning: { _ in true }
        )
        let status = await service.status(for: .ollama)
        XCTAssertEqual(status, .notInstalled)
    }

    func testInstalledNotRunning() async {
        let service = RuntimeDetectionService(
            binaryExists: { _ in true },
            processRunning: { _ in false }
        )
        let status = await service.status(for: .ollama)
        XCTAssertEqual(status, .installedNotRunning)
    }

    func testRunning() async {
        let service = RuntimeDetectionService(
            binaryExists: { _ in true },
            processRunning: { _ in true }
        )
        let status = await service.status(for: .llamaServer)
        XCTAssertEqual(status, .running)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RuntimeDetectionServiceTests`
Expected: FAIL — `cannot find 'RuntimeDetectionService' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// Detects whether a local runtime (Ollama, llama.cpp server) is installed and
/// running. All probing is injectable so the decision logic is unit-testable;
/// `.live` runs filesystem and `pgrep` checks OFF the main thread.
struct RuntimeDetectionService: Sendable {
    enum Runtime: Sendable {
        case ollama
        case llamaServer

        /// Candidate binary paths checked for "installed".
        var binaryPaths: [String] {
            switch self {
            case .ollama:
                ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama", "/usr/bin/ollama"]
            case .llamaServer:
                ["/opt/homebrew/bin/llama-server", "/usr/local/bin/llama-server"]
            }
        }

        /// Process names matched by `pgrep -x` for "running".
        var processNames: [String] {
            switch self {
            case .ollama: ["ollama"]
            case .llamaServer: ["llama-server", "llama.cpp"]
            }
        }
    }

    enum Status: Equatable, Sendable {
        case notInstalled
        case installedNotRunning
        case running
    }

    /// Injected: does a binary exist at this path? (`.live` uses FileManager.)
    let binaryExists: @Sendable (String) -> Bool
    /// Injected: is a process with this exact name running? (`.live` uses pgrep.)
    let processRunning: @Sendable (String) async -> Bool

    func status(for runtime: Runtime) async -> Status {
        let installed = runtime.binaryPaths.contains { binaryExists($0) }
        guard installed else { return .notInstalled }
        for name in runtime.processNames where await processRunning(name) {
            return .running
        }
        return .installedNotRunning
    }

    /// Production instance. Filesystem reads and `pgrep` both run off the main
    /// thread (`processRunning` is async; `binaryExists` is cheap stat()).
    static let live = RuntimeDetectionService(
        binaryExists: { path in FileManager.default.fileExists(atPath: path) },
        processRunning: { name in await Self.pgrep(name) }
    )

    /// Runs `/usr/bin/pgrep -x <name>` on a detached background task and never
    /// blocks the caller's thread. Returns true if the process is running.
    private static func pgrep(_ name: String) async -> Bool {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            process.arguments = ["-x", name]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit() // safe: runs on a detached utility thread
                return process.terminationStatus == 0
            } catch {
                return false
            }
        }.value
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter RuntimeDetectionServiceTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Format + lint + full build**

Run: `swiftformat Sources Tests && swiftformat Sources Tests --lint && swift build`
Expected: `0/N files require formatting`, build exit 0.

- [ ] **Step 6: Commit**

```bash
git add Sources/AutoSuggestApp/System/RuntimeDetectionService.swift Tests/AutoSuggestAppTests/RuntimeDetectionServiceTests.swift
git commit -m "feat: add RuntimeDetectionService for off-main runtime detection"
```

## Task 1.2: Extract model-state gathering off the main actor

**Files:**
- Modify: `Sources/AutoSuggestApp/App/AppCoordinator.swift` (`refreshUIState()` at `:291-350`, `startMetricsRefreshLoop()` at `:268-289`)
- Test: `Tests/AutoSuggestAppTests/AppCoordinatorPresentationTests.swift` (new — pure presentation logic only)

**Context:** `refreshUIState()` currently does, on the main actor: `modelManager.listInstalledModels()` (disk), `modelManager.readActiveModelPath()` (disk), `modelCompatibilityAdvisor.buildReport(...)`. It is called from ~20 synchronous sites plus the 1-second loop. We split it so the disk reads happen off-main and the synchronous sites stay cheap.

**Design:**
- Add a value type `ModelStateSnapshot` holding the gathered model data.
- Add `private var lastModelSnapshot: ModelStateSnapshot` cached on the coordinator.
- Add `nonisolated func gatherModelSnapshot(config:) async -> ModelStateSnapshot` doing the disk reads off-main (verify `ModelManager`/`ModelCompatibilityAdvisor` are not `@MainActor`; they are plain structs — calling them from a `nonisolated` context is fine).
- Split `refreshUIState()` into:
  - `refreshPresentation()` — **synchronous, main, no disk** — rebuilds all `@Published` UI state from `currentConfig`, `permissionManager` checks (these are cheap TCC calls, not disk), and `lastModelSnapshot`.
  - `refreshModelState()` — `async` — `lastModelSnapshot = await gatherModelSnapshot(...)`, then `refreshPresentation()`.
- Replace the ~20 synchronous `refreshUIState()` call sites with `refreshPresentation()`.
- Model-affecting mutations (`switchToInstalledModel`, `rollbackModel`, `saveModelSource`, `moveRuntime`, `applyOnboardingModelChoice`, `retryModelAcquisition`, exclusion changes that call `rebuildRuntimePipelines`) additionally schedule `Task { await refreshModelState() }`.
- The 1-second loop calls `await refreshModelState()` instead of `refreshUIState()` so disk reads run off-main.

- [ ] **Step 1: Write the failing test for the pure presentation builder**

First extract the headline/pause logic into a pure, `nonisolated static` function so it's testable without AppKit. Add this test:

```swift
import XCTest
@testable import AutoSuggestApp

final class AppCoordinatorPresentationTests: XCTestCase {
    func testHeadlineWhenDisabled() {
        let headline = AppCoordinator.statusHeadline(
            enabled: false, pauseReason: nil
        )
        XCTAssertEqual(headline, "Autocomplete is off")
    }

    func testHeadlineWhenPaused() {
        let headline = AppCoordinator.statusHeadline(
            enabled: true, pauseReason: "Paused until 5:00 PM"
        )
        XCTAssertEqual(headline, "Paused until 5:00 PM")
    }

    func testHeadlineWhenLive() {
        let headline = AppCoordinator.statusHeadline(enabled: true, pauseReason: nil)
        XCTAssertEqual(headline, "Suggestions are live")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter AppCoordinatorPresentationTests`
Expected: FAIL — `type 'AppCoordinator' has no member 'statusHeadline'`.

- [ ] **Step 3: Extract the pure function**

In `AppCoordinator.swift`, add:

```swift
nonisolated static func statusHeadline(enabled: Bool, pauseReason: String?) -> String {
    if !enabled {
        return "Autocomplete is off"
    }
    if let pauseReason {
        return pauseReason
    }
    return "Suggestions are live"
}
```

Replace the inline `let headline: String = if ...` block at `:321-327` with:

```swift
let headline = Self.statusHeadline(enabled: currentConfig.enabled, pauseReason: pauseReason)
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter AppCoordinatorPresentationTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Introduce `ModelStateSnapshot` + split refresh (no behavior change)**

Add near the other state structs in `AppCoordinator.swift`:

```swift
/// Disk-derived model state, gathered off the main actor and cached so the
/// synchronous UI refresh never touches the filesystem.
struct ModelStateSnapshot {
    var installedModels: [InstalledModel]
    var activeModelPath: URL?
    var report: ModelCompatibilityReport

    static func empty(report: ModelCompatibilityReport) -> ModelStateSnapshot {
        ModelStateSnapshot(installedModels: [], activeModelPath: nil, report: report)
    }
}
```

Add stored state next to the other `private var`s:

```swift
private var lastModelSnapshot: ModelStateSnapshot?
```

Add the off-main gather (uses only non-`@MainActor` structs):

```swift
nonisolated private func gatherModelSnapshot(config: LocalModelConfig) async -> ModelStateSnapshot {
    let installed = (try? modelManager.listInstalledModels()
        .sorted { $0.path.path < $1.path.path }) ?? []
    let report = modelCompatibilityAdvisor.buildReport(config: config, installedModels: installed)
    let activePath = (try? modelManager.readActiveModelPath()) ?? nil
    return ModelStateSnapshot(installedModels: installed, activeModelPath: activePath, report: report)
}
```

> Note for the executor: `modelManager` and `modelCompatibilityAdvisor` are `let` properties on the `@MainActor` class. To call them from a `nonisolated` method they must be `Sendable`/value types (they are stateless structs). If the compiler objects to capturing `self`, copy the two needed instances into locals before the `await`, e.g. `let manager = modelManager`. Verify with `swift build`.

Now refactor `refreshUIState()` → split into `refreshPresentation()` (synchronous) and `refreshModelState()` (async):

```swift
/// Async: gather disk state off-main, cache it, then publish.
private func refreshModelState() async {
    guard let currentConfig else { return }
    lastModelSnapshot = await gatherModelSnapshot(config: currentConfig.localModel)
    refreshPresentation()
}

/// Synchronous, main, NO disk I/O. Rebuilds @Published UI state from
/// currentConfig + cached model snapshot + cheap permission checks.
private func refreshPresentation() {
    guard let currentConfig, let uiModel else { return }

    let permissionHealth = PermissionHealth(
        accessibilityTrusted: permissionManager.isAccessibilityTrusted(),
        inputMonitoringTrusted: permissionManager.hasInputMonitoringPermission()
    )

    let snapshot = lastModelSnapshot
        ?? .empty(report: modelCompatibilityAdvisor.buildReport(
            config: currentConfig.localModel, installedModels: []
        ))
    let report = snapshot.report
    let installedModels = snapshot.installedModels
    let activeModelPath = snapshot.activeModelPath
    let activeRuntimeLabel = deriveActiveRuntimeLabel(from: report)
    let activeModelLabel = deriveActiveModelLabel(activeModelPath: activeModelPath, config: currentConfig)

    // ... (identical body to the former refreshUIState from the ModelHealth
    // construction at :308 through statusBarController.refreshAppearance() at :349,
    // but reading installedModels/report/activeModelPath from `snapshot` instead
    // of calling modelManager directly) ...
    statusBarController.refreshAppearance()
}
```

> Executor: move the existing body of `refreshUIState()` from line 308 (`let modelHealth = ModelHealth(...)`) through line 349 verbatim into `refreshPresentation()`, deleting only the three disk-reading lines (`:299`, `:300-303`, `:304`) which are now sourced from `snapshot`. Use `Self.statusHeadline(...)` for the headline.

- [ ] **Step 6: Repoint call sites**

- Replace every `refreshUIState()` call in `AppCoordinator.swift` with `refreshPresentation()` (synchronous sites).
- In `startMetricsRefreshLoop()` (`:283`), replace `refreshUIState()` with `await refreshModelState()`.
- After model-mutating operations that already call `rebuildRuntimePipelines`, add `Task { await refreshModelState() }` so installed-model lists refresh off-main. Specifically: `switchToInstalledModel`, `rollbackModel`, `moveRuntime`, `applyOnboardingModelChoice`, and the success branches of `saveModelSource`/`retryModelAcquisition`.
- In `start()` (`:90`), replace `refreshUIState()` with `await refreshModelState()` (we are already in an async context there).

- [ ] **Step 7: Build, lint, full test suite**

Run: `swiftformat Sources Tests && swiftformat Sources Tests --lint && swift build && swift test`
Expected: format clean, build exit 0, full suite green.

- [ ] **Step 8: [MANUAL] Verify no main-thread stall**

Build and run the `macos/` app (`cd macos && xcodegen generate && xcodebuild -scheme AutoSuggest -configuration Debug build`, then launch). Open Settings, switch tabs repeatedly. Confirm no periodic ~1s hitch. (Optional: attach Instruments Time Profiler; the main thread should be idle between interactions.)

- [ ] **Step 9: Commit**

```bash
git add Sources/AutoSuggestApp/App/AppCoordinator.swift Tests/AutoSuggestAppTests/AppCoordinatorPresentationTests.swift
git commit -m "perf: gather model state off-main; split refresh into presentation + async model state

Removes synchronous filesystem I/O from the 1s @MainActor refresh loop."
```

## Task 1.3: Wire onboarding detection to `RuntimeDetectionService`

**Files:**
- Modify: `Sources/AutoSuggestApp/UI/OnboardingFlowView.swift` (`detectOllama()` at `:827-853`, `isProcessRunning()` at `:934-945`, `isReady(config:isCoreMLInstalled:)` at `:912-921`)

- [ ] **Step 1: Replace synchronous `detectOllama()` with async `.task`**

In the Ollama detection view, replace the synchronous body. Change `.onAppear { detectOllama() }` (`:822`) to a `.task` that awaits the service, and the "Recheck" button (`:815`) to launch a `Task`:

```swift
// State already exists: @State private var status: <StatusEnum>
.task { await refreshStatus() }

// Recheck button:
Button("Recheck") { Task { await refreshStatus() } }

private func refreshStatus() async {
    status = .checking
    let result = await RuntimeDetectionService.live.status(for: .ollama)
    status = Self.mapStatus(result)
}

private static func mapStatus(_ s: RuntimeDetectionService.Status) -> <StatusEnum> {
    switch s {
    case .notInstalled: return .notInstalled
    case .installedNotRunning: return .installedNotRunning
    case .running: return .running
    }
}
```

> Executor: read `:790-854` to see the exact `<StatusEnum>` case names and reuse them; do not invent new cases.

- [ ] **Step 2: Replace `isProcessRunning(_:)` calls in `isReady(...)` with cached async state**

`OnboardingModelChoice.isReady(...)` (`:912`) calls the synchronous `isProcessRunning(...)` during view rendering — a freeze. Remove `isProcessRunning(_:)` (`:934-945`) and the `.ollama`/`.llamaCpp` branches' calls to it. Instead the owning step view holds `@State private var readiness: [OnboardingModelChoice: Bool]` populated by a `.task` that awaits `RuntimeDetectionService.live.status(for:)`, and `isReady` reads from that dictionary.

> Executor: read `:159-366` to find the call sites of `isReady(...)` (the displayed-steps logic and the Finish step). Thread the cached `readiness` value in instead of calling `isReady` synchronously. Keep the CoreML branch (`isCoreMLInstalled || config.isModelPresent`) as-is — it does no subprocess work.

- [ ] **Step 3: Grep to prove no synchronous Process remains in UI**

Run: `grep -rnE 'Process\(\)|waitUntilExit' Sources/AutoSuggestApp/UI`
Expected: **no matches.**

- [ ] **Step 4: Build, lint, test**

Run: `swiftformat Sources Tests && swiftformat Sources Tests --lint && swift build && swift test`
Expected: clean, exit 0, green.

- [ ] **Step 5: [MANUAL] Verify onboarding does not freeze**

Run the app with onboarding reset: `defaults delete dev.autosuggest.desktop autosuggest.onboarding.complete.v3` (then relaunch). Step to the Model screen — it must appear instantly and update runtime status without blocking.

- [ ] **Step 6: Commit**

```bash
git add Sources/AutoSuggestApp/UI/OnboardingFlowView.swift
git commit -m "perf: move onboarding runtime detection off the main thread via RuntimeDetectionService"
```

---

# Phase 2 — Reactive, self-healing permissions

**Outcome:** Returning from System Settings updates permission state immediately; granting Input Monitoring re-arms the event tap live (fresh monitor instance), and only if re-arm verifiably fails does the app show an explicit "Relaunch to finish enabling" CTA — never silent failure. Event taps disabled by timeout auto-recover.

## Task 2.1: Pure re-arm decision function

**Files:**
- Create: `Sources/AutoSuggestApp/System/PermissionReArm.swift`
- Test: `Tests/AutoSuggestAppTests/PermissionReArmTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import AutoSuggestApp

final class PermissionReArmTests: XCTestCase {
    func testNoActionWhenAlreadyArmed() {
        let action = PermissionReArm.decide(
            inputMonitoringNowGranted: true, tapCurrentlyActive: true
        )
        XCTAssertEqual(action, .none)
    }

    func testReArmWhenGrantedButTapInactive() {
        let action = PermissionReArm.decide(
            inputMonitoringNowGranted: true, tapCurrentlyActive: false
        )
        XCTAssertEqual(action, .rebuildAndVerify)
    }

    func testNoActionWhenStillDenied() {
        let action = PermissionReArm.decide(
            inputMonitoringNowGranted: false, tapCurrentlyActive: false
        )
        XCTAssertEqual(action, .none)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter PermissionReArmTests`
Expected: FAIL — `cannot find 'PermissionReArm' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Pure decision for what to do when the app regains focus and we re-check
/// Input Monitoring. Separated from AppKit so it is unit-testable.
enum PermissionReArm {
    enum Action: Equatable {
        case none              // nothing to do
        case rebuildAndVerify  // permission present but tap not active: rebuild pipeline, then verify
    }

    static func decide(inputMonitoringNowGranted: Bool, tapCurrentlyActive: Bool) -> Action {
        guard inputMonitoringNowGranted else { return .none }
        return tapCurrentlyActive ? .none : .rebuildAndVerify
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter PermissionReArmTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoSuggestApp/System/PermissionReArm.swift Tests/AutoSuggestAppTests/PermissionReArmTests.swift
git commit -m "feat: pure permission re-arm decision function"
```

## Task 2.2: Tap activity introspection + timeout recovery in the monitors

**Files:**
- Modify: `Sources/AutoSuggestApp/Input/CGEventInputMonitor.swift`
- Modify: `Sources/AutoSuggestApp/Input/CGEventShortcutMonitor.swift`
- Modify: `Sources/AutoSuggestApp/Input/InputMonitor.swift` (the `InputMonitor` protocol — add `var isActive: Bool`)

**Context:** Two fixes. (a) Expose whether the tap is actually installed and enabled so the coordinator can verify re-arm. (b) Handle `tapDisabledByTimeout`/`tapDisabledByUserInput` in the callback so a stalled tap re-enables itself instead of silently dying (obs: `CGEventShortcutMonitor` has no timeout recovery).

- [ ] **Step 1: Add `isActive` to the `InputMonitor` protocol**

Read `Sources/AutoSuggestApp/Input/InputMonitor.swift`. Add to the `InputMonitor` protocol:

```swift
/// True when the event tap is installed and currently enabled.
var isActive: Bool { get }
```

Add the same property requirement to `SuggestionShortcutMonitor` if it is a separate protocol (read the file to confirm where each protocol is declared).

- [ ] **Step 2: Implement `isActive` + timeout recovery in `CGEventInputMonitor`**

Add the property and harden the callback. Replace the callback in `installEventTap()` (`:48-56`) so it re-enables on disable events:

```swift
var isActive: Bool {
    guard let eventTap else { return false }
    return CGEvent.tapIsEnabled(tap: eventTap)
}
```

In the callback, before the `guard let userInfo`:

```swift
let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let userInfo {
            let monitor = Unmanaged<CGEventInputMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            monitor.reEnableTap()
        }
        return Unmanaged.passUnretained(event)
    }
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<CGEventInputMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    monitor.handleCGEvent(type: type, event: event)
    return Unmanaged.passUnretained(event)
}
```

Add:

```swift
private func reEnableTap() {
    guard let eventTap else { return }
    CGEvent.tapEnable(tap: eventTap, enable: true)
    logger.info("Re-enabled input event tap after disable event.")
}
```

- [ ] **Step 3: Mirror `isActive` + timeout recovery in `CGEventShortcutMonitor`**

Same `isActive` computed property and the same `tapDisabledByTimeout`/`tapDisabledByUserInput` handling + `reEnableTap()` in `CGEventShortcutMonitor` (callback at `:39-49`). `CGEventShortcutMonitor` is `@MainActor`; the callback runs on the main run loop, so calling `reEnableTap()` directly is fine.

- [ ] **Step 4: Update mocks to satisfy the protocol**

The mocks in `Tests/AutoSuggestAppTests/IntegrationTestHarness.swift` conform to `InputMonitor`/`SuggestionShortcutMonitor`. Add `var isActive: Bool { true }` (or a settable stub) to each mock so the suite compiles.

- [ ] **Step 5: Build + full test suite**

Run: `swift build && swift test`
Expected: build exit 0, full suite green.

- [ ] **Step 6: Format, lint, commit**

```bash
swiftformat Sources Tests && swiftformat Sources Tests --lint
git add Sources/AutoSuggestApp/Input/ Tests/AutoSuggestAppTests/IntegrationTestHarness.swift
git commit -m "fix: expose event-tap activity + auto-recover taps disabled by timeout"
```

## Task 2.3: Reactive refresh + live re-arm in `AppCoordinator`

**Files:**
- Modify: `Sources/AutoSuggestApp/App/AppCoordinator.swift`
- Modify: `Sources/AutoSuggestApp/UI/AutoSuggestUIModel.swift` (add `needsRelaunchToEnable` published flag)

**Context:** Wire `NSApplication.didBecomeActiveNotification` to re-check permissions immediately, and on a granted-but-tap-inactive condition rebuild the pipeline (fresh `CGEventInputMonitor` → fresh `installEventTap()`). If after rebuild the tap is still inactive, set `needsRelaunchToEnable = true` to surface the relaunch CTA (Task 2.4).

- [ ] **Step 1: Add the published flag**

In `AutoSuggestUIModel.swift`, after `@Published var permissionHealth` (`:300`):

```swift
/// Set when Input Monitoring is granted but the tap could not be armed in this
/// process; the UI shows a one-click "Relaunch to finish enabling" action.
@Published var needsRelaunchToEnable: Bool = false
```

- [ ] **Step 2: Observe activation + re-arm in the coordinator**

Add a stored observer token and a flag tracking the last input-monitoring state:

```swift
private var didBecomeActiveObserver: NSObjectProtocol?
private var lastInputMonitoringTrusted = false
```

In `start()`, after `statusBarController.configure(with: uiModel)` (`:56`), register:

```swift
didBecomeActiveObserver = NotificationCenter.default.addObserver(
    forName: NSApplication.didBecomeActiveNotification,
    object: nil,
    queue: .main
) { [weak self] _ in
    Task { @MainActor in self?.handleDidBecomeActive() }
}
lastInputMonitoringTrusted = permissionManager.hasInputMonitoringPermission()
```

Add the handler:

```swift
private func handleDidBecomeActive() {
    // Cheap TCC re-check + immediate UI update (no disk I/O).
    refreshPresentation()

    let nowGranted = permissionManager.hasInputMonitoringPermission()
    let tapActive = (typingPipeline?.inputMonitorIsActive ?? false)
    let action = PermissionReArm.decide(
        inputMonitoringNowGranted: nowGranted,
        tapCurrentlyActive: tapActive
    )
    lastInputMonitoringTrusted = nowGranted

    switch action {
    case .none:
        if tapActive { uiModel?.needsRelaunchToEnable = false }
    case .rebuildAndVerify:
        guard let currentConfig else { return }
        rebuildRuntimePipelines(using: currentConfig)
        setPipelineEnabledFromCurrentState()
        // Verify after the run loop installs the fresh tap.
        Task { @MainActor in
            let armed = typingPipeline?.inputMonitorIsActive ?? false
            uiModel?.needsRelaunchToEnable = !armed
            if armed {
                uiModel?.showBanner(
                    kind: .success,
                    title: "AutoSuggest enabled",
                    message: "Input Monitoring is now active."
                )
            }
            refreshPresentation()
        }
    }
}
```

- [ ] **Step 3: Expose tap activity through `TypingPipeline`**

In `TypingPipeline.swift`, add:

```swift
var inputMonitorIsActive: Bool { inputMonitor.isActive }
```

- [ ] **Step 4: Clean up the observer**

Add a `deinit`/teardown that removes the observer (the coordinator lives for the app lifetime, but remove for correctness):

```swift
deinit {
    if let didBecomeActiveObserver {
        NotificationCenter.default.removeObserver(didBecomeActiveObserver)
    }
}
```

> Executor: `AppCoordinator` is `@MainActor`; a `deinit` referencing a stored token is fine. If Swift 6 concurrency complains, capture the token in a local before removal.

- [ ] **Step 5: Build + test**

Run: `swift build && swift test`
Expected: exit 0, green.

- [ ] **Step 6: [MANUAL] Verify the live re-arm**

Critical path, CI cannot reach it:
1. Build/run the `macos/` app. Revoke Input Monitoring for AutoSuggest in System Settings (toggle off).
2. With AutoSuggest still running, toggle Input Monitoring back **on**.
3. Click back to AutoSuggest (triggers `didBecomeActive`). Within one focus cycle, suggestions should work **without relaunch**, the permissions UI should read "Granted", and the menu-bar icon should switch to the active ghost.
4. If your macOS build proves the tap genuinely cannot arm in-process, confirm the relaunch CTA appears instead (Task 2.4) — never a silent dead state.

- [ ] **Step 7: Format, lint, commit**

```bash
swiftformat Sources Tests && swiftformat Sources Tests --lint
git add Sources/AutoSuggestApp/App/AppCoordinator.swift Sources/AutoSuggestApp/UI/AutoSuggestUIModel.swift Sources/AutoSuggestApp/Suggestions/TypingPipeline.swift
git commit -m "fix: reactive permission refresh on activation + live event-tap re-arm"
```

## Task 2.4: Honest relaunch CTA in the UI

**Files:**
- Modify: the Permissions settings view + the quick panel (currently in `Sources/AutoSuggestApp/UI/AutoSuggestViews.swift`; after Phase 5 this is `PermissionsSettingsView.swift`/`StatusPopoverView.swift`). Do Phase 2 against the current file locations.

- [ ] **Step 1: Add a relaunch banner driven by `needsRelaunchToEnable`**

In the permissions section (around `AutoSuggestViews.swift:397-437`), add, above the permission rows:

```swift
if uiModel.needsRelaunchToEnable {
    HStack(spacing: 10) {
        Image(systemName: "arrow.clockwise.circle.fill")
        VStack(alignment: .leading, spacing: 2) {
            Text("Finish enabling AutoSuggest").font(.callout.weight(.semibold))
            Text("Input Monitoring was granted but needs a relaunch to take effect.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Button("Relaunch") { uiModel.relaunchApp() }
            .buttonStyle(.borderedProminent)
    }
    .padding(12)
    .background(DesignSystem.Color.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
}
```

> Executor: confirm the `DesignSystem.Color.brand` path by reading `Sources/AutoSuggestApp/UI/DesignSystem.swift`; use the existing accessor name.

- [ ] **Step 2: Build, lint, test, commit**

```bash
swift build && swift test && swiftformat Sources Tests --lint
git add Sources/AutoSuggestApp/UI/
git commit -m "feat: surface relaunch-to-enable CTA when tap re-arm fails"
```

---

# Phase 3 — Menu-bar icon: keep the ghost, fix the states

**Outcome:** With Phase 2 making `permissionHealth.isReady` accurate, the correct glyph shows. The ghost renders crisply as a template; the three states are legible and have distinct tooltips. State→image selection is a pure, testable function.

## Task 3.1: Pure menu-bar icon state function

**Files:**
- Create: `Sources/AutoSuggestApp/App/MenuBarIconState.swift`
- Test: `Tests/AutoSuggestAppTests/MenuBarIconStateTests.swift`

- [ ] **Step 1: Failing test**

```swift
import XCTest
@testable import AutoSuggestApp

final class MenuBarIconStateTests: XCTestCase {
    func testNeedsPermission() {
        XCTAssertEqual(MenuBarIconState.resolve(permissionsReady: false, enabled: true), .needsPermission)
        XCTAssertEqual(MenuBarIconState.resolve(permissionsReady: false, enabled: false), .needsPermission)
    }
    func testPausedWhenReadyButDisabled() {
        XCTAssertEqual(MenuBarIconState.resolve(permissionsReady: true, enabled: false), .paused)
    }
    func testActiveWhenReadyAndEnabled() {
        XCTAssertEqual(MenuBarIconState.resolve(permissionsReady: true, enabled: true), .active)
    }
}
```

- [ ] **Step 2: Run → fail.** `swift test --filter MenuBarIconStateTests` → FAIL.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// The three meaningful menu-bar states, in priority order: a missing
/// permission outranks the on/off toggle.
enum MenuBarIconState: Equatable {
    case active          // amber ghost
    case paused          // pause.circle
    case needsPermission // exclamationmark.shield

    static func resolve(permissionsReady: Bool, enabled: Bool) -> MenuBarIconState {
        guard permissionsReady else { return .needsPermission }
        return enabled ? .active : .paused
    }

    var tooltip: String {
        switch self {
        case .active: "AutoSuggest is active"
        case .paused: "AutoSuggest is paused"
        case .needsPermission: "AutoSuggest needs permission — click to fix"
        }
    }
}
```

- [ ] **Step 4: Run → pass.** `swift test --filter MenuBarIconStateTests` → PASS.

- [ ] **Step 5: Use it in `StatusBarController.refreshAppearance()`**

Replace the `if/else` at `StatusBarController.swift:37-50` with:

```swift
let state = MenuBarIconState.resolve(
    permissionsReady: uiModel.permissionHealth.isReady,
    enabled: uiModel.config.enabled
)
switch state {
case .active:
    button.image = Self.ghostMenuBarImage()
case .paused:
    button.image = Self.symbolImage("pause.circle")
case .needsPermission:
    button.image = Self.symbolImage("exclamationmark.shield")
}
button.title = ""
button.toolTip = state.tooltip
```

Add the helper:

```swift
private static func symbolImage(_ name: String) -> NSImage? {
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: "AutoSuggest") else { return nil }
    image.isTemplate = true
    return image.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .medium))
}
```

- [ ] **Step 6: Build, test, lint, commit**

```bash
swift build && swift test && swiftformat Sources Tests --lint
git add Sources/AutoSuggestApp/App/MenuBarIconState.swift Sources/AutoSuggestApp/App/StatusBarController.swift Tests/AutoSuggestAppTests/MenuBarIconStateTests.swift
git commit -m "refactor: pure menu-bar icon state; distinct tooltips per state"
```

## Task 3.2: Verify the ghost renders crisp

**Files:**
- Inspect: `macos/AutoSuggestDesktop/Assets.xcassets/MenuBarGhost.imageset/` (`Contents.json`, `menubarghost_18.png`, `menubarghost_36.png`)

- [ ] **Step 1: Confirm template metadata**

Read `Contents.json`; confirm `"template-rendering-intent": "template"` is present (it is). A template PNG must be **pure alpha** (shape in opaque pixels, no baked color) or it renders as a solid blob. Inspect the PNGs.

- [ ] **Step 2: [MANUAL] Visual check**

Build/run the `macos/` app with permissions granted and enabled. Confirm the menu-bar glyph is a recognizable ghost (not a filled square), sharp at 1x and 2x, and inverts correctly between light/dark menu bars. If the PNG is not pure-alpha, regenerate it from the source SVG referenced in `DesignSystem` as a template-safe asset (pure black shape on transparent, 18×18 / 36×36). Re-run `cd macos && xcodegen generate` if the asset set changes.

- [ ] **Step 3: Commit (only if assets changed)**

```bash
git add macos/AutoSuggestDesktop/Assets.xcassets/MenuBarGhost.imageset/
git commit -m "fix: ensure MenuBarGhost asset is pure-alpha template for crisp menu-bar rendering"
```

---

# Phase 4 — Reworked guided first-run wizard

**Outcome:** The wizard reflects permission grants live (Phase 2), never freezes on model detection (Phase 1/Task 1.3), and handles relaunch honestly.

## Task 4.1: Live permission state in the wizard

**Files:**
- Modify: `Sources/AutoSuggestApp/UI/OnboardingFlowView.swift`
- Modify: `Sources/AutoSuggestApp/App/OnboardingManager.swift`

**Context:** The wizard currently uses a 1-second heartbeat timer to detect permission grants. With Phase 2's reactive refresh, the wizard should observe the same permission source so its steps advance the instant focus returns from System Settings.

- [ ] **Step 1: Drive the permission step from a shared source**

Read `OnboardingFlowView.swift:150-276`. Replace the internal 1-second heartbeat (`:822` area is for model detection; the permission heartbeat is in the permissions step) with an observation of `NSApplication.didBecomeActiveNotification` (same pattern as Task 2.3) plus an initial check, so `permissionsReady` recomputes on focus return rather than on a fixed poll. Keep the existing `displayedSteps` logic (`:159-164`) — only its input changes.

- [ ] **Step 2: [MANUAL] Verify live advance**

Reset onboarding (`defaults delete dev.autosuggest.desktop autosuggest.onboarding.complete.v3`), run the app. On the Permissions step, grant Accessibility in System Settings, return to the wizard — the card must flip to "Granted" immediately without waiting a second, and the relaunch note for Input Monitoring must be accurate.

- [ ] **Step 3: Build, test, lint, commit**

```bash
swift build && swift test && swiftformat Sources Tests --lint
git add Sources/AutoSuggestApp/UI/OnboardingFlowView.swift Sources/AutoSuggestApp/App/OnboardingManager.swift
git commit -m "feat: onboarding reflects permission grants live on focus return"
```

---

# Phase 5 — Decompose the god-object view files

**Outcome:** `AutoSuggestViews.swift` and `OnboardingFlowView.swift` (each ~930 lines) split into focused files. Pure mechanical, behavior-preserving extraction — verified by an unchanged green test suite. This also reduces the SwiftUI re-render cost (each route view diffs independently).

> **No verbatim code in this phase's steps is a deliberate choice, not a placeholder:** these are file moves of existing, unchanged code. The instruction *is* "move symbol X to file Y." Each task ends with the same hard gate: `swift build && swift test && swiftformat Sources Tests --lint` all green, proving behavior is preserved.

## Task 5.1: Split `AutoSuggestViews.swift` by settings route

**Files (create, moving existing structs unchanged):**
- `Sources/AutoSuggestApp/UI/Settings/SettingsRootView.swift` — `SettingsRootView`, `SettingsDetailContent`, the sidebar.
- `Sources/AutoSuggestApp/UI/Settings/GeneralSettingsView.swift` — `generalSection` → `GeneralSettingsView`.
- `Sources/AutoSuggestApp/UI/Settings/ModelsSettingsView.swift` — `modelsSection`.
- `Sources/AutoSuggestApp/UI/Settings/OnlineLLMSettingsView.swift` — `onlineLLMSection`.
- `Sources/AutoSuggestApp/UI/Settings/PermissionsSettingsView.swift` — `permissionsSection`, `PermissionSettingsRow`, the relaunch CTA from Task 2.4.
- `Sources/AutoSuggestApp/UI/Settings/ExclusionsSettingsView.swift` — `exclusionsSection`.
- `Sources/AutoSuggestApp/UI/Settings/AccessibilitySettingsView.swift` — `accessibilitySection`.
- `Sources/AutoSuggestApp/UI/Settings/DiagnosticsSettingsView.swift` — `diagnosticsSection`.
- `Sources/AutoSuggestApp/UI/StatusPopoverView.swift` — `StatusPopoverView` + `statusRow` helpers.
- `Sources/AutoSuggestApp/UI/Settings/SettingsComponents.swift` — shared row/section helpers used by more than one view.

- [ ] **Step 1: Map before moving** — read `AutoSuggestViews.swift` end to end; list each top-level `struct`/`extension`/private `var section` and its target file from the list above. Anything shared by ≥2 views goes to `SettingsComponents.swift`.
- [ ] **Step 2: Move one view at a time**, building after each move: extract a section into its own `View` struct in its file, replace the inline `case .x: xSection` in `SettingsDetailContent` with `case .x: XSettingsView(uiModel: uiModel)`. Run `swift build` after each extraction.
- [ ] **Step 3: Each detail view takes `@ObservedObject var uiModel: AutoSuggestUIModel`** (not the whole environment) so SwiftUI re-renders only the active route, not the sidebar, on republish.
- [ ] **Step 4: Hard gate** — `swift build && swift test && swiftformat Sources Tests --lint`. All green, 158 tests unchanged.
- [ ] **Step 5: [MANUAL]** Open Settings, click through all seven tabs — each renders identically to before, switching is instant.
- [ ] **Step 6: Commit** — `git add Sources/AutoSuggestApp/UI && git commit -m "refactor: split AutoSuggestViews into per-route setting views (behavior-preserving)"`

## Task 5.2: Split `OnboardingFlowView.swift` by step

**Files (create):**
- `Sources/AutoSuggestApp/UI/Onboarding/WelcomeStepView.swift`
- `Sources/AutoSuggestApp/UI/Onboarding/PermissionsStepView.swift`
- `Sources/AutoSuggestApp/UI/Onboarding/ModelStepView.swift`
- `Sources/AutoSuggestApp/UI/Onboarding/FinishStepView.swift`
- Keep `OnboardingFlowView.swift` as the container (step enum, `displayedSteps`, navigation).
- The `OnboardingModelChoice` display helpers (`:856-932`) move to `Sources/AutoSuggestApp/UI/Onboarding/OnboardingModelChoice+Display.swift`.

- [ ] **Step 1: Move one step view per commit**, `swift build` after each.
- [ ] **Step 2: Hard gate** — `swift build && swift test && swiftformat Sources Tests --lint` all green.
- [ ] **Step 3: [MANUAL]** Reset onboarding and walk the full flow — identical behavior.
- [ ] **Step 4: Commit** — `git commit -m "refactor: split OnboardingFlowView into per-step views (behavior-preserving)"`

---

# Phase 6 — Install polish

**Outcome:** A clean, trustworthy install with accurate first-run guidance and a verified-notarized release.

## Task 6.1: Tighten `install.sh` first-run guidance

**Files:**
- Modify: `scripts/install.sh`

- [ ] **Step 1:** After "Installed … to /Applications." (`:57`), make the first-run note reflect the new live-permission behavior — drop any "you must relaunch" language that the self-healing flow makes unnecessary, and tell the user the app guides them through Accessibility + Input Monitoring on first launch and updates the moment they grant. Keep the self-built `xattr` quarantine note.
- [ ] **Step 2: [MANUAL]** `shellcheck scripts/install.sh` (if available) → no errors; run the script end to end against the latest release on a clean `/Applications` and confirm it mounts, copies, and launches.
- [ ] **Step 3: Commit** — `git commit -m "docs: clearer first-run guidance in install.sh"`

## Task 6.2: Verify the DMG + notarization

**Files:**
- Inspect: the DMG-building step in the release workflow (`.github/workflows/release.yml`) and any `scripts/` packaging helper.

- [ ] **Step 1:** Confirm the DMG includes an `/Applications` symlink so drag-install works (background + symlink). If missing, add it to the packaging step.
- [ ] **Step 2: [MANUAL]** On the published release DMG: `spctl -a -vvv -t install /Volumes/AutoSuggest/AutoSuggest.app` → "accepted, source=Notarized Developer ID"; `xcrun stapler validate /Volumes/AutoSuggest/AutoSuggest.app` → "The validate action worked!". If either fails, the notarization gap flagged in earlier sessions is still open — fix the release workflow before claiming install is "on par."
- [ ] **Step 3: Commit** any packaging fix — `git commit -m "fix: ensure DMG drag-install + valid notarization"`

---

# Final verification (run before opening a PR)

- [ ] `swift build` → exit 0
- [ ] `swift test` → full suite green (≥ 158 tests; new tests from Tasks 1.1, 1.2, 2.1, 3.1 added)
- [ ] `swiftformat Sources Tests --lint` → `0/N files require formatting`
- [ ] `grep -rnE 'Process\(\)|waitUntilExit' Sources/AutoSuggestApp/UI` → no matches
- [ ] **[MANUAL]** Full UX pass on the built `macos/` app: install → onboarding (no freeze) → grant permissions (live update, no surprise relaunch) → correct ghost icon → switch all settings tabs (no hitch) → type in TextEdit and accept a suggestion.
- [ ] Guardrails intact: no edits to `PolicyEngine.swift`, secure-field suppression, `PIIFilter`, `EncryptedFileStore`; `grep -rn "IsSecureEventInputEnabled" Sources` still shows the suppression check in `TypingPipeline.handleInputEvent`.

---

# Self-review (completed by plan author)

- **Spec coverage:** §1 Threading → Phase 1; §2 Permissions → Phase 2; §3 Icon → Phase 3; §4 Onboarding → Phase 4; §5 Decomposition → Phase 5; §6 Install → Phase 6. All six spec sections map to phases.
- **Type consistency:** `RuntimeDetectionService.Status`/`.Runtime`, `PermissionReArm.Action` (`.none`/`.rebuildAndVerify`), `MenuBarIconState` (`.active`/`.paused`/`.needsPermission`), `ModelStateSnapshot`, `needsRelaunchToEnable`, `inputMonitorIsActive`, `isActive` — each defined once and referenced consistently across tasks.
- **Placeholder scan:** the only code-free steps are Phase 5 mechanical moves and **[MANUAL]** AppKit/threading verifications, both of which are explicitly justified by `CLAUDE.md`'s "real AX/CGEvent behavior cannot be exercised in CI" constraint.
