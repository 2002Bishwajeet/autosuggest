# UI Overhaul — Phase 1: Design Foundation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `AutoSuggestTheme` the enforced design system and replace the duplicate hand-rolled UI components with one canonical native-backed set, dropped into existing layouts with no window restructuring.

**Architecture:** Add/extend tokens in `DesignSystem.swift`; build canonical components (`StatusBadge`, `SettingsSection`, `PermissionRow`, `EmptyStateView`, `InlineErrorCard`) alongside the existing `StatusDot`/`SectionHeader`; apply amber as the app-wide `.tint()` inside each top-level SwiftUI view body; migrate call sites and delete the superseded components. Pure-layout swaps are verified by `swift build` + `swiftformat --lint` + the existing 286-test suite; the small amount of resolvable logic (badge style mapping, dot scaling) gets XCTests.

**Tech Stack:** Swift, SwiftUI (hosted in AppKit via `NSHostingController`), XCTest, SwiftFormat 0.61.x.

## Global Constraints

- `swift build` exits 0 after every task.
- `swift test` — all existing tests plus new ones green after every task (no regressions; baseline 286).
- `swiftformat Sources Tests --lint` reports `0/… files require formatting` after every task (paths before the flag).
- Log via `Logger(scope:)`, never `print` (not expected to be needed in this phase).
- Test files mirror source names under `Tests/AutoSuggestAppTests/` and use `@testable import AutoSuggestApp`.
- No behavior changes: inference, policy, config, privacy, and overlay-positioning logic are untouched. Styling + accessibility only.
- Amber brand color is `AutoSuggestTheme.brand` (already defined). Do not introduce new hardcoded hex.
- Branch: `ui-overhaul` (already created; the Phase 1 spec is committed there).

---

### Task 1: Extend tokens + amber tint entry point

**Files:**
- Modify: `Sources/AutoSuggestApp/UI/DesignSystem.swift`
- Test: `Tests/AutoSuggestAppTests/DesignSystemTests.swift` (create)

**Interfaces:**
- Produces:
  - `AutoSuggestTheme.badgeFillOpacity: Double` (= `0.15`) — single canonical capsule/tile fill opacity replacing ad-hoc `0.12/0.14/0.16`.
  - `AutoSuggestTheme.radiusExtraSmall: CGFloat` (= `6`) — for the small keycap/snippet radius (`10` at those call sites collapses to this + `radiusSmall`).
  - A `View` extension `func autoSuggestTinted() -> some View` returning `self.tint(AutoSuggestTheme.brand)`. This is the one place the app-wide amber tint is defined so later tasks apply it consistently.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/AutoSuggestAppTests/DesignSystemTests.swift
import XCTest
@testable import AutoSuggestApp

final class DesignSystemTests: XCTestCase {
    func testBadgeFillOpacityIsCanonical() {
        XCTAssertEqual(AutoSuggestTheme.badgeFillOpacity, 0.15, accuracy: 0.0001)
    }

    func testRadiusScaleIsMonotonic() {
        XCTAssertLessThan(AutoSuggestTheme.radiusExtraSmall, AutoSuggestTheme.radiusSmall)
        XCTAssertLessThan(AutoSuggestTheme.radiusSmall, AutoSuggestTheme.radiusMedium)
        XCTAssertLessThan(AutoSuggestTheme.radiusMedium, AutoSuggestTheme.radiusLarge)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DesignSystemTests`
Expected: FAIL — `badgeFillOpacity`/`radiusExtraSmall` are not members of `AutoSuggestTheme`.

- [ ] **Step 3: Implement the tokens + tint helper**

In `DesignSystem.swift`, add to `AutoSuggestTheme` (after the existing corner-radius block):

```swift
    static let radiusExtraSmall: CGFloat = 6

    // MARK: - Badge / tile fill

    /// Canonical fill opacity for status capsules and icon tiles. Replaces the
    /// ad-hoc 0.12 / 0.14 / 0.16 values that had drifted across views.
    static let badgeFillOpacity: Double = 0.15
```

At the end of the file (outside the enum), add:

```swift
// MARK: - App-wide tint

extension View {
    /// Applies AutoSuggest's amber brand tint. Deliberate design choice: amber
    /// drives selection, key toggles, and primary buttons regardless of the
    /// user's system accent. Apply once at each top-level SwiftUI view body.
    func autoSuggestTinted() -> some View {
        tint(AutoSuggestTheme.brand)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter DesignSystemTests`
Expected: PASS.

- [ ] **Step 5: Verify build + lint**

Run: `swift build && swiftformat Sources Tests --lint`
Expected: build exits 0; lint reports 0 files require formatting.

- [ ] **Step 6: Commit**

```bash
git add Sources/AutoSuggestApp/UI/DesignSystem.swift Tests/AutoSuggestAppTests/DesignSystemTests.swift
git commit -m "feat(ui): add badge opacity + radius tokens and amber tint helper"
```

---

### Task 2: `StatusBadge` component (replaces the 3 inline capsules)

**Files:**
- Create: `Sources/AutoSuggestApp/UI/Components/StatusBadge.swift`
- Test: `Tests/AutoSuggestAppTests/StatusBadgeTests.swift` (create)

**Interfaces:**
- Consumes: `AutoSuggestTheme.badgeFillOpacity`, `.success`, `.warning`, `.textSecondary`.
- Produces:
  - `enum StatusBadge.Style { case granted, required, neutral }`
  - `static func StatusBadge.tint(for: Style) -> Color` (testable style→color mapping)
  - `struct StatusBadge: View` with `init(_ text: String, style: Style)`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/AutoSuggestAppTests/StatusBadgeTests.swift
import SwiftUI
import XCTest
@testable import AutoSuggestApp

final class StatusBadgeTests: XCTestCase {
    func testTintMapping() {
        XCTAssertEqual(StatusBadge.tint(for: .granted), AutoSuggestTheme.success)
        XCTAssertEqual(StatusBadge.tint(for: .required), AutoSuggestTheme.warning)
        XCTAssertEqual(StatusBadge.tint(for: .neutral), AutoSuggestTheme.textSecondary)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter StatusBadgeTests`
Expected: FAIL — `StatusBadge` is undefined.

- [ ] **Step 3: Implement `StatusBadge`**

```swift
// Sources/AutoSuggestApp/UI/Components/StatusBadge.swift
import SwiftUI

/// Small capsule status label (e.g. "Granted" / "Required"). One definition
/// replacing the divergent inline capsules that used 0.12 / 0.14 / 0.16 fills.
struct StatusBadge: View {
    enum Style {
        case granted, required, neutral
    }

    let text: String
    let style: Style

    init(_ text: String, style: Style) {
        self.text = text
        self.style = style
    }

    static func tint(for style: Style) -> Color {
        switch style {
        case .granted: AutoSuggestTheme.success
        case .required: AutoSuggestTheme.warning
        case .neutral: AutoSuggestTheme.textSecondary
        }
    }

    var body: some View {
        let color = StatusBadge.tint(for: style)
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, AutoSuggestTheme.spacingSM)
            .padding(.vertical, AutoSuggestTheme.spacingXS)
            .background(Capsule().fill(color.opacity(AutoSuggestTheme.badgeFillOpacity)))
            .foregroundStyle(color)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter StatusBadgeTests`
Expected: PASS.

- [ ] **Step 5: Verify build + lint**

Run: `swift build && swiftformat Sources Tests --lint`
Expected: build 0, lint clean.

- [ ] **Step 6: Commit**

```bash
git add Sources/AutoSuggestApp/UI/Components/StatusBadge.swift Tests/AutoSuggestAppTests/StatusBadgeTests.swift
git commit -m "feat(ui): add canonical StatusBadge component"
```

---

### Task 3: `SettingsSection` container (replaces `SettingsCard` + `SimplePanel`)

**Files:**
- Create: `Sources/AutoSuggestApp/UI/Components/SettingsSection.swift`
- Test: none (pure layout; verified by build/lint + later adoption).

**Interfaces:**
- Consumes: `AutoSuggestTheme.spacing*`, `.radiusMedium`, `.surfaceSecondary`.
- Produces:
  - `struct SettingsSection<Content: View>: View` with `init(_ title: String? = nil, systemImage: String? = nil, @ViewBuilder content: () -> Content)`.
  - Behavior: optional header via `SectionHeader`, then a `VStack(alignment: .leading, spacing: spacingMD)` of content, padded `spacingLG`, filled `surfaceSecondary` at `radiusMedium`, `maxWidth: .infinity, alignment: .leading`. This is the union of what `SettingsCard` (no header, `padding 14`) and `SimplePanel` (internal `spacing 10`, `padding 14`) did.

- [ ] **Step 1: Implement `SettingsSection`**

```swift
// Sources/AutoSuggestApp/UI/Components/SettingsSection.swift
import SwiftUI

/// Titled grouped container for settings content. Canonical replacement for the
/// near-duplicate `SettingsCard` and `SimplePanel`.
struct SettingsSection<Content: View>: View {
    let title: String?
    let systemImage: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AutoSuggestTheme.spacingMD) {
            if let title {
                SectionHeader(title, systemImage: systemImage)
            }
            content
        }
        .padding(AutoSuggestTheme.spacingLG)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AutoSuggestTheme.radiusMedium, style: .continuous)
                .fill(AutoSuggestTheme.surfaceSecondary)
        )
    }
}
```

- [ ] **Step 2: Verify build + lint**

Run: `swift build && swiftformat Sources Tests --lint`
Expected: build 0, lint clean. (Component compiles; not yet adopted.)

- [ ] **Step 3: Commit**

```bash
git add Sources/AutoSuggestApp/UI/Components/SettingsSection.swift
git commit -m "feat(ui): add canonical SettingsSection container"
```

---

### Task 4: `PermissionRow` component (replaces `PermissionSettingsRow` + `PermissionDetailRow`)

**Files:**
- Create: `Sources/AutoSuggestApp/UI/Components/PermissionRow.swift`
- Test: none (pure layout).

**Interfaces:**
- Consumes: `StatusBadge`, `AutoSuggestTheme.spacing*`, `.radiusSmall`, `.radiusMedium`, `.badgeFillOpacity`, `.success`, `.warning`, `.surfaceSecondary`, `.border`.
- Produces:
  - `struct PermissionRow: View` with:
    ```swift
    init(
        systemImage: String,
        title: String,
        description: String,
        granted: Bool,
        primary: (label: String, action: () -> Void),
        secondary: (label: String, action: () -> Void)? = nil
    )
    ```
  - Superset of both old rows: single `primary` (settings row) plus optional `secondary` (onboarding row's two-button case). `granted` naming (onboarding's `ready` maps to `granted`). Icon tile 40×40, `@ScaledMetric` so it scales with Dynamic Type. Uses `StatusBadge(granted ? "Granted" : "Required", style: granted ? .granted : .required)`. Combined accessibility label matching the existing settings row.

- [ ] **Step 1: Implement `PermissionRow`**

```swift
// Sources/AutoSuggestApp/UI/Components/PermissionRow.swift
import SwiftUI

/// System-permission status row: icon tile + title + status badge + action(s).
/// Canonical replacement for `PermissionSettingsRow` (single action) and
/// `PermissionDetailRow` (two actions).
struct PermissionRow: View {
    let systemImage: String
    let title: String
    let description: String
    let granted: Bool
    let primary: (label: String, action: () -> Void)
    let secondary: (label: String, action: () -> Void)?

    @ScaledMetric(relativeTo: .headline) private var tileSize: CGFloat = 40

    init(
        systemImage: String,
        title: String,
        description: String,
        granted: Bool,
        primary: (label: String, action: () -> Void),
        secondary: (label: String, action: () -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.description = description
        self.granted = granted
        self.primary = primary
        self.secondary = secondary
    }

    private var accent: Color {
        granted ? AutoSuggestTheme.success : AutoSuggestTheme.warning
    }

    var body: some View {
        HStack(alignment: .top, spacing: AutoSuggestTheme.spacingMD) {
            ZStack {
                RoundedRectangle(cornerRadius: AutoSuggestTheme.radiusSmall, style: .continuous)
                    .fill(accent.opacity(AutoSuggestTheme.badgeFillOpacity))
                    .frame(width: tileSize, height: tileSize)
                Image(systemName: granted ? "checkmark.shield.fill" : systemImage)
                    .font(.headline)
                    .foregroundStyle(accent)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AutoSuggestTheme.spacingXS) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    StatusBadge(granted ? "Granted" : "Required", style: granted ? .granted : .required)
                }
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !granted {
                    HStack(spacing: AutoSuggestTheme.spacingSM) {
                        Button(primary.label, action: primary.action)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        if let secondary {
                            Button(secondary.label, action: secondary.action)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                    .padding(.top, AutoSuggestTheme.spacingXS)
                }
            }
        }
        .padding(AutoSuggestTheme.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: AutoSuggestTheme.radiusMedium, style: .continuous)
                .fill(AutoSuggestTheme.surfaceSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: AutoSuggestTheme.radiusMedium, style: .continuous)
                        .stroke(granted ? AutoSuggestTheme.success.opacity(0.2) : AutoSuggestTheme.border, lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(granted ? "Granted" : "Required"). \(description)")
    }
}
```

- [ ] **Step 2: Verify build + lint**

Run: `swift build && swiftformat Sources Tests --lint`
Expected: build 0, lint clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/AutoSuggestApp/UI/Components/PermissionRow.swift
git commit -m "feat(ui): add canonical PermissionRow component"
```

---

### Task 5: `EmptyStateView` + `InlineErrorCard`

**Files:**
- Create: `Sources/AutoSuggestApp/UI/Components/StateViews.swift`
- Test: none (pure layout).

**Interfaces:**
- Consumes: `AutoSuggestTheme.spacing*`, `.radiusMedium`, `.error`, `.surfaceSecondary`.
- Produces:
  - `struct EmptyStateView: View` — `init(icon: String, title: String, message: String)`. Centered SF Symbol + title + secondary message.
  - `struct InlineErrorCard: View` — `init(message: String, retry: (label: String, action: () -> Void)? = nil)`. Error-tinted card with optional Retry button.

- [ ] **Step 1: Implement both**

```swift
// Sources/AutoSuggestApp/UI/Components/StateViews.swift
import SwiftUI

/// Centered empty-state placeholder for lists with no items.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: AutoSuggestTheme.spacingSM) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(AutoSuggestTheme.spacingXL)
        .accessibilityElement(children: .combine)
    }
}

/// Inline error message with an optional Retry action.
struct InlineErrorCard: View {
    let message: String
    let retry: (label: String, action: () -> Void)?

    init(message: String, retry: (label: String, action: () -> Void)? = nil) {
        self.message = message
        self.retry = retry
    }

    var body: some View {
        HStack(alignment: .top, spacing: AutoSuggestTheme.spacingSM) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AutoSuggestTheme.error)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let retry {
                Button(retry.label, action: retry.action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(AutoSuggestTheme.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AutoSuggestTheme.radiusMedium, style: .continuous)
                .fill(AutoSuggestTheme.error.opacity(AutoSuggestTheme.badgeFillOpacity))
        )
        .accessibilityElement(children: .combine)
    }
}
```

- [ ] **Step 2: Verify build + lint**

Run: `swift build && swiftformat Sources Tests --lint`
Expected: build 0, lint clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/AutoSuggestApp/UI/Components/StateViews.swift
git commit -m "feat(ui): add EmptyStateView and InlineErrorCard"
```

---

### Task 6: Apply amber tint at roots + scale `StatusDot` + fix white-on-accent

**Files:**
- Modify: `Sources/AutoSuggestApp/UI/DesignSystem.swift` (StatusDot scaling)
- Modify: `Sources/AutoSuggestApp/UI/StatusPopoverView.swift` (tint)
- Modify: `Sources/AutoSuggestApp/UI/Settings/SettingsRootView.swift` (tint + white-on-accent fix)
- Modify: `Sources/AutoSuggestApp/UI/OnboardingFlowView.swift` (tint)
- Modify: `Sources/AutoSuggestApp/UI/AboutWindowController.swift` (tint on `AboutView`)
- Test: `Tests/AutoSuggestAppTests/DesignSystemTests.swift` (add StatusDot scaling assertion is not feasible for `@ScaledMetric`; instead verify the default constant via a plain stored property — see step 1)

**Interfaces:**
- Consumes: `View.autoSuggestTinted()` from Task 1.
- Produces: no new public API. `StatusDot` gains `@ScaledMetric` sizing.

- [ ] **Step 1: Scale `StatusDot`**

In `DesignSystem.swift`, change `StatusDot` to scale with Dynamic Type:

```swift
struct StatusDot: View {
    enum Status {
        case active, paused, error, inactive
    }

    let status: Status
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }

    private var color: Color {
        switch status {
        case .active: AutoSuggestTheme.success
        case .paused: AutoSuggestTheme.warning
        case .error: AutoSuggestTheme.error
        case .inactive: AutoSuggestTheme.textTertiary
        }
    }
}
```

- [ ] **Step 2: Apply the tint at each top-level view body**

`StatusPopoverView.swift` — append `.autoSuggestTinted()` to the outermost view in `body` (the root `VStack`).

`OnboardingFlowView.swift` — append `.autoSuggestTinted()` to the outermost view in `body`.

`AboutWindowController.swift` — where `aboutView` is built (line ~16), wrap: change `let hostingController = NSHostingController(rootView: aboutView)` to apply the tint on the view, e.g. `NSHostingController(rootView: aboutView.autoSuggestTinted())` **only if** the controller does not depend on the concrete `AboutView` type elsewhere (it does not — verify no `as? NSHostingController<AboutView>` cast exists; grep confirms only `PreferencesWindowController` casts a root type). If a cast did exist, apply `.autoSuggestTinted()` inside `AboutView.body` instead.

- [ ] **Step 3: Apply tint + fix white-on-accent in `SettingsRootView`**

`SettingsRootView.swift`:
- Append `.autoSuggestTinted()` to the outermost view in `body`. Because `PreferencesWindowController` casts the root to `NSHostingController<SettingsRootView>` (line 26), the tint MUST be applied **inside** `SettingsRootView.body` (not on the constructed `rootView`), so the root type stays `SettingsRootView`.
- Fix the forced white-on-accent selected-row text at lines 57 and 60. Replace:

```swift
                    .foregroundStyle(isSelected ? Color.white : Color.secondary)
```
```swift
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
```

with, respectively:

```swift
                    .foregroundStyle(isSelected ? AnyShapeStyle(.selection) : AnyShapeStyle(.secondary))
```
```swift
                    .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.primary))
```

If the selected row's background fill is `Color.accentColor` (verify around lines 40–70), also switch that fill to `AutoSuggestTheme.brand` so selection reads amber, and keep the selected label as `.primary` (readable on the amber fill in both appearances) rather than forcing white. The concrete rule: selected label uses `.primary`; never `Color.white`.

- [ ] **Step 4: Verify build + lint + full suite**

Run: `swift build && swiftformat Sources Tests --lint && swift test`
Expected: build 0, lint clean, all tests green (baseline 286, plus DesignSystemTests + StatusBadgeTests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoSuggestApp/UI/DesignSystem.swift \
        Sources/AutoSuggestApp/UI/StatusPopoverView.swift \
        Sources/AutoSuggestApp/UI/Settings/SettingsRootView.swift \
        Sources/AutoSuggestApp/UI/OnboardingFlowView.swift \
        Sources/AutoSuggestApp/UI/AboutWindowController.swift
git commit -m "feat(ui): apply amber tint at roots, scale StatusDot, fix white-on-accent"
```

---

### Task 7: Migrate call sites, delete superseded components, token sweep

**Files:**
- Modify: `Sources/AutoSuggestApp/UI/Settings/PermissionsSettingsView.swift` (use `PermissionRow`, `SettingsSection`; delete private `PermissionSettingsRow`)
- Modify: `Sources/AutoSuggestApp/UI/Settings/GeneralSettingsView.swift` (`SimplePanel` → `SettingsSection`)
- Modify: `Sources/AutoSuggestApp/UI/Onboarding/OnboardingComponents.swift` (delete `PermissionDetailRow`; retarget `SuggestionPreviewCard`/`ShortcutActionCard` `SettingsCard` → `SettingsSection`)
- Modify: `Sources/AutoSuggestApp/UI/OnboardingFlowView.swift` (swap `PermissionDetailRow` usage → `PermissionRow`)
- Modify: `Sources/AutoSuggestApp/UI/Settings/SettingsComponents.swift` (delete `SettingsCard` and `SimplePanel` once unreferenced; keep `BannerView`)
- Modify: any other file referencing `SettingsCard`/`SimplePanel` (find via grep in step 1)

**Interfaces:**
- Consumes: `SettingsSection`, `PermissionRow` from Tasks 3–4.
- Produces: deletion of `SettingsCard`, `SimplePanel`, `PermissionSettingsRow`, `PermissionDetailRow`.

- [ ] **Step 1: Enumerate all call sites**

Run:
```bash
grep -rn "SettingsCard\|SimplePanel\|PermissionSettingsRow\|PermissionDetailRow" Sources
```
Expected: a list of usages to migrate. Every hit outside the definition files must be swapped before the definitions are deleted.

- [ ] **Step 2: Migrate `PermissionsSettingsView`**

- Replace both `PermissionSettingsRow(...)` usages (lines ~31, ~41) with `PermissionRow(...)`, mapping `granted:` through and wrapping the action as `primary: ("Open System Settings", { ... })`. Example for the Accessibility row:

```swift
            PermissionRow(
                systemImage: "accessibility",
                title: "Accessibility",
                description: "Lets AutoSuggest read the text around your cursor and insert completions into any text field.",
                granted: uiModel.permissionHealth.accessibilityTrusted,
                primary: ("Open System Settings", { uiModel.openAccessibilitySettings() })
            )
```

- Replace the three `SimplePanel { SectionHeader(...) ... }` blocks (Privacy & Telemetry, Personalization, Training Data) with `SettingsSection("Privacy & Telemetry", systemImage: "hand.raised") { ... }` etc., removing the now-redundant inner `SectionHeader` call (the title moves into `SettingsSection`). Preserve `.onAppear { uiModel.onRefreshPersonalizationStats?() }` on the Personalization section.
- Delete the `private struct PermissionSettingsRow` (lines ~146–208).

- [ ] **Step 3: Migrate `GeneralSettingsView` and onboarding components**

- In `GeneralSettingsView.swift`, swap each `SimplePanel { ... }` for `SettingsSection { ... }` (or `SettingsSection("Title") { ... }` where a header exists).
- In `OnboardingComponents.swift`, change `SuggestionPreviewCard` and `ShortcutActionCard` bodies from `SettingsCard { ... }` to `SettingsSection { ... }`. Delete `struct PermissionDetailRow` (lines ~4–73).
- In `OnboardingFlowView.swift`, replace the `PermissionDetailRow(... ready: ..., primaryAction: (l, a), secondaryAction: (l, a))` usage with `PermissionRow(systemImage:, title:, description:, granted: <ready value>, primary: (l, a), secondary: (l, a))`. Map `ready:` → `granted:`.

- [ ] **Step 4: Token sweep of the touched views**

In every file modified in this task, replace remaining hardcoded values with tokens: `spacing: 14`→`AutoSuggestTheme.spacingMD`, `padding(14/16)`→`spacingMD`/`spacingLG`, `padding(12)`→`spacingMD`, radii `10`→`radiusSmall`/`radiusExtraSmall`, `14`→`radiusMedium`. Do NOT sweep files not otherwise touched in this task (those belong to later phases).

- [ ] **Step 5: Delete the superseded containers**

Once step 1's grep returns only definition-site hits, delete `SettingsCard` and `SimplePanel` from `SettingsComponents.swift` (keep `BannerView`). Re-run:
```bash
grep -rn "SettingsCard\|SimplePanel\|PermissionSettingsRow\|PermissionDetailRow" Sources
```
Expected: no matches.

- [ ] **Step 6: Verify build + lint + full suite**

Run: `swift build && swiftformat Sources Tests --lint && swift test`
Expected: build 0, lint clean, all tests green.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor(ui): adopt SettingsSection/PermissionRow, delete duplicates, token sweep"
```

---

## Self-Review

**Spec coverage:**
- Tokens enforced (spacing/radius/color/type): Task 1 (adds missing tokens) + Task 7 step 4 (sweep). ✓
- Amber app-wide tint: Task 1 (helper) + Task 6 (applied at 4 roots). ✓
- `SettingsSection` replaces `SettingsCard` + `SimplePanel`: Tasks 3, 7. ✓
- `StatusBadge` replaces 3 capsules: Tasks 2, 7 (via `PermissionRow`) — note the standalone `SetupStatusBadge` in onboarding is left to Phase 4; called out below. ✓ (partial, intentional)
- `PermissionRow` replaces both permission rows: Tasks 4, 7. ✓
- `EmptyStateView`/`InlineErrorCard` introduced: Task 5 (adoption deferred to later phases per spec). ✓
- `StatusDot` scales with Dynamic Type: Task 6. ✓
- White-on-accent contrast fix: Task 6 step 3. ✓
- Build/test/lint green after each task: every task's verify step. ✓

**Deliberate deferrals (documented, not gaps):** `SetupStatusBadge`, `KeycapView`, `CommandSnippetCard` token cleanup and `EmptyStateView`/`InlineErrorCard` adoption live in Phases 2–4 (they belong to windows restructured there). Phase 1 stays drop-in only, per the spec's non-goals.

**Placeholder scan:** No TBD/TODO. Every code step shows real code. The one conditional instruction (Task 6 step 2, About tint) gives an explicit either/or with the grep evidence to decide. ✓

**Type consistency:** `PermissionRow.init` labels (`primary:`/`secondary:` as labeled tuples, `granted:`) are used identically in Tasks 4 and 7. `StatusBadge(_:style:)` and `StatusBadge.Style` cases match across Tasks 2 and 4. `SettingsSection(_:systemImage:content:)` matches across Tasks 3 and 7. `autoSuggestTinted()` defined in Task 1, consumed in Task 6. ✓
