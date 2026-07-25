# UI Overhaul Phase 4: Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a dot step indicator and direction-aware paging to the onboarding wizard, and dedupe the Accessibility/Input-Monitoring permission pair into one shared `PermissionsChecklist` with canonical copy.

**Architecture:** Two new leaf components in `UI/Components/` (`OnboardingStepIndicator`, `PermissionsChecklist` + `PermissionCopy`), then adoption edits in `OnboardingFlowView` and `PermissionsSettingsView`. No logic changes outside the UI layer.

**Tech Stack:** Swift 6 / SwiftUI (macOS), SwiftPM, XCTest, SwiftFormat.

**Spec:** `docs/superpowers/specs/2026-07-25-ui-overhaul-phase4-onboarding-design.md`

## Global Constraints

- Branch: `ui-overhaul-phase4` (already checked out).
- Gate after every task: `swift build` exit 0, `swift test` 0 failures, `swiftformat Sources Tests --lint` reports 0 files require formatting. Run all three before each commit.
- Design tokens come from `AutoSuggestTheme` (`Sources/AutoSuggestApp/UI/DesignSystem.swift`): `brand`, `spacingXS=4`, `spacingSM=8`, `spacingMD=12`, `radiusSmall=8`. Never hardcode colors/spacings that have a token.
- Respect `@Environment(\.accessibilityReduceMotion)` for any animation added.
- The wizard's step list is DYNAMIC: `displayedSteps` is `[.welcome, .model, .finish]` when permissions are pre-granted, else all four. All indicator math must use `displayedSteps`, never `OnboardingStep.allCases`.
- Canonical permission copy (exact strings, used verbatim in Task 2):
  - Accessibility: "Lets AutoSuggest read the text around your cursor and insert completions into any text field. Required for suggestions to work."
  - Input Monitoring: "Lets AutoSuggest detect Tab, Enter, and Esc so you can accept or dismiss suggestions. Requires a relaunch after granting."
- Log via `Logger(scope:)`, never `print`. UI strings hardcoded English (no localization layer).

---

### Task 1: `OnboardingStepIndicator` component

**Files:**
- Create: `Sources/AutoSuggestApp/UI/Components/OnboardingStepIndicator.swift`
- Test: `Tests/AutoSuggestAppTests/OnboardingStepIndicatorTests.swift`

**Interfaces:**
- Consumes: `AutoSuggestTheme.brand`, `.spacingSM`.
- Produces: `OnboardingStepIndicator(total: Int, current: Int)` (SwiftUI `View`) and `OnboardingStepIndicator.clampedIndex(_ current: Int, total: Int) -> Int` (static, pure) — Task 4 instantiates the view.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/AutoSuggestAppTests/OnboardingStepIndicatorTests.swift
import XCTest
@testable import AutoSuggestApp

final class OnboardingStepIndicatorTests: XCTestCase {
    func testIndexWithinRangeIsUnchanged() {
        XCTAssertEqual(OnboardingStepIndicator.clampedIndex(2, total: 4), 2)
        XCTAssertEqual(OnboardingStepIndicator.clampedIndex(0, total: 4), 0)
        XCTAssertEqual(OnboardingStepIndicator.clampedIndex(3, total: 4), 3)
    }

    func testNegativeIndexClampsToZero() {
        XCTAssertEqual(OnboardingStepIndicator.clampedIndex(-1, total: 4), 0)
    }

    func testOverflowIndexClampsToLast() {
        XCTAssertEqual(OnboardingStepIndicator.clampedIndex(9, total: 4), 3)
    }

    func testDegenerateTotalYieldsZero() {
        XCTAssertEqual(OnboardingStepIndicator.clampedIndex(0, total: 0), 0)
        XCTAssertEqual(OnboardingStepIndicator.clampedIndex(5, total: 1), 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter OnboardingStepIndicatorTests`
Expected: compile FAILURE — `cannot find 'OnboardingStepIndicator' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/AutoSuggestApp/UI/Components/OnboardingStepIndicator.swift
import SwiftUI

/// Dot page control for the onboarding wizard: one dot per displayed step,
/// the current dot filled brand-amber and slightly enlarged. Pure view — the
/// caller supplies position; exposes a single accessibility element
/// ("Step N of M").
struct OnboardingStepIndicator: View {
    let total: Int
    let current: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Clamps `current` into `0..<total` (0 when `total` < 1) so a caller
    /// race (e.g. the dynamic step list shrinking) can never draw out of range.
    static func clampedIndex(_ current: Int, total: Int) -> Int {
        guard total > 0 else { return 0 }
        return min(max(current, 0), total - 1)
    }

    var body: some View {
        let active = Self.clampedIndex(current, total: total)
        HStack(spacing: AutoSuggestTheme.spacingSM) {
            ForEach(0 ..< max(total, 1), id: \.self) { index in
                Circle()
                    .fill(index == active ? AutoSuggestTheme.brand : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .scaleEffect(index == active && !reduceMotion ? 1.25 : 1.0)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: active)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(active + 1) of \(max(total, 1))")
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter OnboardingStepIndicatorTests`
Expected: 4 tests, 0 failures.

- [ ] **Step 5: Gate and commit**

```bash
swift build && swift test && swiftformat Sources Tests --lint
git add Sources/AutoSuggestApp/UI/Components/OnboardingStepIndicator.swift Tests/AutoSuggestAppTests/OnboardingStepIndicatorTests.swift
git commit -m "feat(ui): OnboardingStepIndicator dot page control"
```

---

### Task 2: `PermissionsChecklist` + `PermissionCopy`

**Files:**
- Create: `Sources/AutoSuggestApp/UI/Components/PermissionsChecklist.swift`
- Test: `Tests/AutoSuggestAppTests/PermissionsChecklistTests.swift`

**Interfaces:**
- Consumes: `PermissionRow` (`Sources/AutoSuggestApp/UI/Components/PermissionRow.swift`) — signature `PermissionRow(systemImage:title:description:granted:primary:secondary:)` where `primary`/`secondary` are `(label: String, action: () -> Void)` tuples, `secondary` optional.
- Produces (used by Task 3):
  - `enum PermissionCopy` with `static let accessibilityTitle/accessibilityDescription/inputMonitoringTitle/inputMonitoringDescription: String`.
  - `struct PermissionsChecklistActions { var requestAccessibility, openAccessibilitySettings, requestInputMonitoring, openInputMonitoringSettings: () -> Void }`.
  - `struct PermissionsChecklist: View` with `init(context: PermissionsChecklist.Context, accessibilityGranted: Bool, inputMonitoringGranted: Bool, actions: PermissionsChecklistActions)`; `Context` is `enum { case onboarding, settings }`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/AutoSuggestAppTests/PermissionsChecklistTests.swift
import XCTest
@testable import AutoSuggestApp

/// Locks the canonical permission copy. Both onboarding and Settings render
/// `PermissionsChecklist`, which reads only these strings — so this test is
/// the regression lock keeping the two screens' wording identical.
final class PermissionsChecklistTests: XCTestCase {
    func testCanonicalAccessibilityCopy() {
        XCTAssertEqual(PermissionCopy.accessibilityTitle, "Accessibility")
        XCTAssertEqual(
            PermissionCopy.accessibilityDescription,
            "Lets AutoSuggest read the text around your cursor and insert completions into any text field. Required for suggestions to work."
        )
    }

    func testCanonicalInputMonitoringCopy() {
        XCTAssertEqual(PermissionCopy.inputMonitoringTitle, "Input Monitoring")
        XCTAssertEqual(
            PermissionCopy.inputMonitoringDescription,
            "Lets AutoSuggest detect Tab, Enter, and Esc so you can accept or dismiss suggestions. Requires a relaunch after granting."
        )
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PermissionsChecklistTests`
Expected: compile FAILURE — `cannot find 'PermissionCopy' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/AutoSuggestApp/UI/Components/PermissionsChecklist.swift
import SwiftUI

/// Single source of truth for the wording of the two system permissions.
/// Onboarding and Settings previously carried diverged copies of these
/// strings; both now render through `PermissionsChecklist`.
enum PermissionCopy {
    static let accessibilityTitle = "Accessibility"
    static let accessibilityDescription =
        "Lets AutoSuggest read the text around your cursor and insert completions into any text field. Required for suggestions to work."
    static let inputMonitoringTitle = "Input Monitoring"
    static let inputMonitoringDescription =
        "Lets AutoSuggest detect Tab, Enter, and Esc so you can accept or dismiss suggestions. Requires a relaunch after granting."
}

/// Closures the checklist forwards to; each call site wires these to its own
/// backing object (`PermissionManager` in onboarding, `AutoSuggestUIModel`
/// in Settings).
struct PermissionsChecklistActions {
    var requestAccessibility: () -> Void
    var openAccessibilitySettings: () -> Void
    var requestInputMonitoring: () -> Void
    var openInputMonitoringSettings: () -> Void
}

/// The canonical Accessibility + Input Monitoring row pair. `context` selects
/// the action affordances: onboarding shows an active TCC-prompt button plus
/// an Open Settings fallback; Settings shows a single Open System Settings
/// button (macOS never re-prompts once denied, so an active prompt there
/// would silently no-op).
struct PermissionsChecklist: View {
    enum Context {
        case onboarding
        case settings
    }

    let context: Context
    let accessibilityGranted: Bool
    let inputMonitoringGranted: Bool
    let actions: PermissionsChecklistActions

    var body: some View {
        Group {
            PermissionRow(
                systemImage: "accessibility",
                title: PermissionCopy.accessibilityTitle,
                description: PermissionCopy.accessibilityDescription,
                granted: accessibilityGranted,
                primary: context == .onboarding
                    ? ("Show Prompt", actions.requestAccessibility)
                    : ("Open System Settings", actions.openAccessibilitySettings),
                secondary: context == .onboarding
                    ? ("Open Settings", actions.openAccessibilitySettings)
                    : nil
            )

            PermissionRow(
                systemImage: "keyboard",
                title: PermissionCopy.inputMonitoringTitle,
                description: PermissionCopy.inputMonitoringDescription,
                granted: inputMonitoringGranted,
                primary: context == .onboarding
                    ? ("Register App", actions.requestInputMonitoring)
                    : ("Open System Settings", actions.openInputMonitoringSettings),
                secondary: context == .onboarding
                    ? ("Open Settings", actions.openInputMonitoringSettings)
                    : nil
            )
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PermissionsChecklistTests`
Expected: 2 tests, 0 failures.

- [ ] **Step 5: Gate and commit**

```bash
swift build && swift test && swiftformat Sources Tests --lint
git add Sources/AutoSuggestApp/UI/Components/PermissionsChecklist.swift Tests/AutoSuggestAppTests/PermissionsChecklistTests.swift
git commit -m "feat(ui): PermissionsChecklist with canonical PermissionCopy"
```

---

### Task 3: Adopt `PermissionsChecklist` in both screens

**Files:**
- Modify: `Sources/AutoSuggestApp/UI/OnboardingFlowView.swift` (the two `PermissionRow(...)` blocks inside `permissionsStep`, ~lines 254–279)
- Modify: `Sources/AutoSuggestApp/UI/Settings/PermissionsSettingsView.swift` (the two `PermissionRow(...)` blocks inside `Section("Permissions")`, ~lines 33–49)

**Interfaces:**
- Consumes: `PermissionsChecklist`, `PermissionsChecklistActions`, `PermissionsChecklist.Context` from Task 2. Onboarding backs actions with `permissionManager` (`PermissionManager`); Settings backs them with `uiModel` (`AutoSuggestUIModel`).
- Produces: nothing new — behavior-preserving replacement.

- [ ] **Step 1: Replace the pair in `OnboardingFlowView.permissionsStep`**

Replace the two `PermissionRow(...)` blocks (keep the relaunch banner above and the "All permissions granted" footer below untouched) with:

```swift
            PermissionsChecklist(
                context: .onboarding,
                accessibilityGranted: permissionManager.isAccessibilityTrusted(),
                inputMonitoringGranted: permissionManager.hasInputMonitoringPermission(),
                actions: PermissionsChecklistActions(
                    requestAccessibility: { _ = permissionManager.requestAccessibilityPermission() },
                    openAccessibilitySettings: { permissionManager.openAccessibilitySettings() },
                    // "Register App" both fires the TCC request and opens the
                    // pane — preserving the pre-checklist behavior exactly.
                    requestInputMonitoring: {
                        permissionManager.requestInputMonitoringPermission()
                        permissionManager.openInputMonitoringSettings()
                    },
                    openInputMonitoringSettings: { permissionManager.openInputMonitoringSettings() }
                )
            )
```

- [ ] **Step 2: Replace the pair in `PermissionsSettingsView`**

Replace the two `PermissionRow(...)` blocks inside `Section("Permissions")` (keep the "Recheck"/"Relaunch Now" controls below them untouched) with:

```swift
                PermissionsChecklist(
                    context: .settings,
                    accessibilityGranted: uiModel.permissionHealth.accessibilityTrusted,
                    inputMonitoringGranted: uiModel.permissionHealth.inputMonitoringTrusted,
                    actions: PermissionsChecklistActions(
                        requestAccessibility: { uiModel.openAccessibilitySettings() },
                        openAccessibilitySettings: { uiModel.openAccessibilitySettings() },
                        requestInputMonitoring: { uiModel.openInputMonitoringSettings() },
                        openInputMonitoringSettings: { uiModel.openInputMonitoringSettings() }
                    )
                )
```

(In `.settings` context only the `open*Settings` closures are reachable; the `request*` closures are filled with the same open-settings calls to keep the struct total — no optionals.)

- [ ] **Step 3: Verify no other `PermissionRow` call sites drifted**

Run: `grep -rn "PermissionRow(" Sources/`
Expected: matches only in `UI/Components/PermissionRow.swift` (the definition and its own body) and `UI/Components/PermissionsChecklist.swift`. If any other call site appears, stop and reassess.

- [ ] **Step 4: Gate**

Run: `swift build && swift test && swiftformat Sources Tests --lint`
Expected: build exit 0; 0 test failures (306 tests: 300 baseline + 4 from Task 1 + 2 from Task 2); lint 0 files.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoSuggestApp/UI/OnboardingFlowView.swift Sources/AutoSuggestApp/UI/Settings/PermissionsSettingsView.swift
git commit -m "refactor(ui): both permission screens render shared PermissionsChecklist"
```

---

### Task 4: Step indicator + direction-aware paging in `OnboardingFlowView`

**Files:**
- Modify: `Sources/AutoSuggestApp/UI/OnboardingFlowView.swift` — state block (~line 19), `body` (~lines 52–125), `moveForward()`/`moveBackward()` (~lines 525–543)

**Interfaces:**
- Consumes: `OnboardingStepIndicator(total:current:)` from Task 1; existing `displayedSteps`/`currentStep` computed vars (dynamic — 3 steps when permissions pre-granted, else 4).
- Produces: nothing new — presentation change only.

- [ ] **Step 1: Add direction + reduce-motion state**

In the `@State` block add, and alongside the other `@Environment`-less properties:

```swift
    // True when the last navigation was forward; drives the slide direction
    // of the step transition.
    @State private var isAdvancing = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
```

- [ ] **Step 2: Record direction in the navigation helpers and slow the animation to match the slide**

Replace `moveForward()` and `moveBackward()` bodies:

```swift
    private func moveForward() {
        let steps = displayedSteps
        guard let currentIndex = steps.firstIndex(of: currentStep), currentIndex < steps.count - 1 else {
            return
        }
        isAdvancing = true
        withAnimation(.easeInOut(duration: 0.25)) {
            step = steps[currentIndex + 1]
        }
    }

    private func moveBackward() {
        let steps = displayedSteps
        guard let currentIndex = steps.firstIndex(of: currentStep), currentIndex > 0 else {
            return
        }
        isAdvancing = false
        withAnimation(.easeInOut(duration: 0.25)) {
            step = steps[currentIndex - 1]
        }
    }
```

- [ ] **Step 3: Add the transition + indicator to `body`**

Add a computed transition near the other computed vars:

```swift
    /// Slide+fade in the direction of travel; plain crossfade under Reduce
    /// Motion.
    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: isAdvancing ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: isAdvancing ? .leading : .trailing).combined(with: .opacity)
        )
    }
```

In `body`, insert the indicator between the title `VStack` and the `ScrollView`:

```swift
            OnboardingStepIndicator(
                total: displayedSteps.count,
                current: displayedSteps.firstIndex(of: currentStep) ?? 0
            )
            .frame(maxWidth: .infinity)
```

And on the `Group` inside the `ScrollView` (the one holding the `switch currentStep`), after its existing `.frame(maxWidth:alignment:)` modifier, add:

```swift
                .id(currentStep)
                .transition(stepTransition)
```

Also add `.clipped()` to the `ScrollView` itself so the sliding page cannot draw outside the content area during the transition:

```swift
            ScrollView {
                ...
            }
            .clipped()
```

- [ ] **Step 4: Gate**

Run: `swift build && swift test && swiftformat Sources Tests --lint`
Expected: build exit 0, 0 test failures, lint 0 files. (No new unit tests — transition behavior is not CI-testable per CLAUDE.md; covered by Task 5's manual verification.)

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoSuggestApp/UI/OnboardingFlowView.swift
git commit -m "feat(ui): onboarding step indicator + direction-aware paging"
```

---

### Task 5: Manual verification + docs

**Files:**
- Modify: none (verification); optionally `docs/superpowers/specs/2026-07-25-ui-overhaul-phase4-onboarding-design.md` if reality diverged.

**Interfaces:**
- Consumes: the built app.
- Produces: verified Phase 4; branch ready to merge.

- [ ] **Step 1: Build and launch the app shell**

```bash
cd macos && xcodegen generate && xcodebuild -project AutoSuggestDesktop.xcodeproj -scheme AutoSuggestDesktop -configuration Debug build | tail -5
```

Expected: `BUILD SUCCEEDED`. Launch the built app (or use the XcodeBuildMCP flow from project memory: `xcode-mcp-macos-verification`). To force onboarding, follow the reset noted in that memory (or temporarily clear the onboarding-completed flag in `~/Library/Application Support/AutoSuggestApp/config.json`).

- [ ] **Step 2: Verify the checklist**

- Onboarding permissions step shows the two rows with the canonical copy, "Show Prompt"/"Register App" primaries and "Open Settings" secondaries.
- Settings → Permissions shows the same two rows (same wording) with a single "Open System Settings" primary each.
- Relaunch banner and Recheck/Relaunch controls still present in their screens.

- [ ] **Step 3: Verify indicator + paging**

- Dots match the displayed step count (4 dots when permissions not yet granted; 3 when pre-granted — grant both, relaunch, re-run onboarding to see 3).
- Active dot is amber and advances/retreats with Continue/Back.
- Continue slides content in from the right; Back slides in from the left.
- With System Settings → Accessibility → Display → Reduce Motion ON: steps crossfade, dots don't scale.
- VoiceOver reads the indicator as "Step N of M".

- [ ] **Step 4: Final gate + push**

```bash
swift build && swift test && swiftformat Sources Tests --lint
git push -u origin ui-overhaul-phase4
```

Expected: all green; branch pushed. Merging to main happens after user sign-off, per the phase cadence.

---

## Self-review notes

- Spec coverage: indicator → Tasks 1+4; native paging → Task 4; dedupe (option A, canonical copy, per-context actions) → Tasks 2+3; testing section → Tasks 1/2 unit tests + Task 5 manual pass. Settings relaunch/recheck + onboarding banner explicitly preserved (Tasks 3 steps 1–2).
- The dynamic `displayedSteps` constraint is enforced at both consumption points (Task 4 step 3) and defended by `clampedIndex` (Task 1).
- Type consistency: `PermissionsChecklistActions` field names match between Task 2 (definition) and Task 3 (both call sites); `OnboardingStepIndicator(total:current:)` matches between Tasks 1 and 4.
