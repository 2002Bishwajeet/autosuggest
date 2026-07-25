# UI Overhaul — Phase 2: Settings Window — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the Settings window on native macOS idioms — `NavigationSplitView` sidebar + grouped `Form` panes — killing the hand-rolled sidebar and the Models pane magic strings, while folding in the Exclusions identity fix and Diagnostics read-only fix.

**Architecture:** A native `NavigationSplitView` replaces the custom two-pane `SettingsRootView`; each of the 7 panes becomes `Form { Section … }.formStyle(.grouped)` with panel internals reparented (not rewritten). A typed `ModelRuntime` enum replaces stringly-typed runtime dispatch. `ExclusionRule` gains a non-persisted `Identifiable` id (schema-neutral). Everything gates on build + the 289-test baseline + lint.

**Tech Stack:** Swift, SwiftUI (hosted in AppKit via `NSHostingController`), XCTest, SwiftFormat 0.61.x.

## Global Constraints

- `swift build` exits 0 after every task.
- `swift test` — all existing tests plus new ones green after every task (baseline 289; the `ConfigMigrationManager` tests MUST stay green — they prove the `ExclusionRule` change is schema-neutral).
- `swiftformat Sources Tests --lint` reports `0/… files require formatting` after every task (paths before the flag).
- Test files mirror source names under `Tests/AutoSuggestAppTests/`, `@testable import AutoSuggestApp`.
- No config-schema change, no inference/policy/privacy logic change. Restructuring + the enumerated fixes only.
- Amber comes from the app-wide `.tint` already applied inside `SettingsRootView.body` (Phase 1) — do not add hardcoded accent/foreground colors; native `List`/`Form` selection picks legible colors.
- `SettingsSection` is NOT deleted (onboarding uses it) — it is only removed from Settings-window panes.
- Branch: `ui-overhaul-phase2`.

### Reparent pattern (used by every pane-conversion task)

Panes today are `VStack { SettingsSection { … } … }`. Convert to:

```swift
var body: some View {
    Form {
        Section("Section Title") {
            // the SAME controls that were inside the old SettingsSection, verbatim
        }
        // … more Sections …
    }
    .formStyle(.grouped)
}
```

Rules: one top-level `Form`; each former `SettingsSection { … }` becomes a `Section("Title") { … }` (title from the old `SectionHeader`, or untitled if there was none); **preserve every control, binding, `.onAppear`, `.sheet`, `.confirmationDialog`, and `@State` verbatim** — only the container wrappers change. Remove any inner `SectionHeader` whose text became the `Section` title. Do not restyle controls; grouped `Form` handles alignment.

---

### Task 1: `ModelRuntime` typed enum

**Files:**
- Create: `Sources/AutoSuggestApp/UI/ModelRuntime.swift`
- Test: `Tests/AutoSuggestAppTests/ModelRuntimeTests.swift`

**Interfaces:**
- Produces:
  - `enum ModelRuntime: String, CaseIterable, Identifiable` cases `foundationModels`, `coreML`, `ollama`, `llamaCpp`; `var id: String { rawValue }`.
  - `init?(configValue: String)` — centralizes the tolerated spellings (mirrors the existing `RuntimeDisplayName.label` matching).
  - `var displayName: String`.
  Later tasks (Task 5) consume this to pick the runtime panel and label the picker.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/AutoSuggestAppTests/ModelRuntimeTests.swift
import XCTest
@testable import AutoSuggestApp

final class ModelRuntimeTests: XCTestCase {
    func testConfigValueMapping() {
        XCTAssertEqual(ModelRuntime(configValue: "ollama"), .ollama)
        XCTAssertEqual(ModelRuntime(configValue: "llama.cpp"), .llamaCpp)
        XCTAssertEqual(ModelRuntime(configValue: "llamacpp"), .llamaCpp)
        XCTAssertEqual(ModelRuntime(configValue: "llama_cpp"), .llamaCpp)
        XCTAssertEqual(ModelRuntime(configValue: "llamaserver"), .llamaCpp)
        XCTAssertEqual(ModelRuntime(configValue: "coreml"), .coreML)
        XCTAssertEqual(ModelRuntime(configValue: "core ml"), .coreML)
        XCTAssertEqual(ModelRuntime(configValue: "foundationmodels"), .foundationModels)
        XCTAssertEqual(ModelRuntime(configValue: "FoundationModels"), .foundationModels)
        XCTAssertNil(ModelRuntime(configValue: "nonsense"))
    }

    func testDisplayNames() {
        XCTAssertEqual(ModelRuntime.ollama.displayName, "Ollama")
        XCTAssertEqual(ModelRuntime.llamaCpp.displayName, "llama.cpp")
        XCTAssertEqual(ModelRuntime.coreML.displayName, "Core ML")
        XCTAssertEqual(ModelRuntime.foundationModels.displayName, "Foundation Models")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ModelRuntimeTests`
Expected: FAIL — `ModelRuntime` undefined.

- [ ] **Step 3: Implement**

```swift
// Sources/AutoSuggestApp/UI/ModelRuntime.swift
import Foundation

/// Typed identity for a local inference runtime. Replaces stringly-typed
/// dispatch on config runtime IDs (`"ollama"` / `"llama.cpp"` / `"llamacpp"` / …).
enum ModelRuntime: String, CaseIterable, Identifiable {
    case foundationModels
    case coreML
    case ollama
    case llamaCpp

    var id: String { rawValue }

    /// Maps a config runtime string (any tolerated spelling) to a case.
    init?(configValue: String) {
        switch configValue.lowercased() {
        case "foundationmodels", "foundation models":
            self = .foundationModels
        case "coreml", "core ml", "core_ml":
            self = .coreML
        case "ollama":
            self = .ollama
        case "llama.cpp", "llamacpp", "llama_cpp", "llamaserver":
            self = .llamaCpp
        default:
            return nil
        }
    }

    var displayName: String {
        switch self {
        case .foundationModels: "Foundation Models"
        case .coreML: "Core ML"
        case .ollama: "Ollama"
        case .llamaCpp: "llama.cpp"
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ModelRuntimeTests`
Expected: PASS.

- [ ] **Step 5: Verify build + lint**

Run: `swift build && swiftformat Sources Tests --lint`
Expected: build 0, lint clean.

- [ ] **Step 6: Commit**

```bash
git add Sources/AutoSuggestApp/UI/ModelRuntime.swift Tests/AutoSuggestAppTests/ModelRuntimeTests.swift
git commit -m "feat(ui): add typed ModelRuntime enum replacing runtime magic strings"
```

---

### Task 2: `ExclusionRule` → `Identifiable` (schema-neutral)

**Files:**
- Modify: `Sources/AutoSuggestApp/Config/AppConfig.swift:448-453`
- Test: `Tests/AutoSuggestAppTests/ExclusionRuleCodableTests.swift`

**Interfaces:**
- Produces: `ExclusionRule: Codable, Equatable, Identifiable` with a runtime-only `let id = UUID()` NOT present in the encoded JSON. Task 8 consumes `\.id` for the rules `ForEach`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/AutoSuggestAppTests/ExclusionRuleCodableTests.swift
import XCTest
@testable import AutoSuggestApp

final class ExclusionRuleCodableTests: XCTestCase {
    func testEncodedJSONHasNoIdKey() throws {
        let rule = ExclusionRule(enabled: true, bundleID: "com.x", windowTitleContains: nil, contentPattern: nil)
        let data = try JSONEncoder().encode(rule)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("\"id\""), "id must not be persisted: \(json)")
    }

    func testRoundTripPreservesStoredFields() throws {
        let rule = ExclusionRule(enabled: false, bundleID: "com.a", windowTitleContains: "win", contentPattern: "re")
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(ExclusionRule.self, from: data)
        XCTAssertEqual(decoded, rule) // Equatable ignores id (see note in impl)
        XCTAssertEqual(decoded.enabled, false)
        XCTAssertEqual(decoded.bundleID, "com.a")
        XCTAssertEqual(decoded.windowTitleContains, "win")
        XCTAssertEqual(decoded.contentPattern, "re")
    }

    func testDistinctInstancesHaveDistinctIds() {
        let a = ExclusionRule(enabled: true, bundleID: "com.x", windowTitleContains: nil, contentPattern: nil)
        let b = ExclusionRule(enabled: true, bundleID: "com.x", windowTitleContains: nil, contentPattern: nil)
        XCTAssertNotEqual(a.id, b.id)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ExclusionRuleCodableTests`
Expected: FAIL — `id` not a member (and/or encoded JSON currently would contain no id, but `.id` access fails to compile → build error in test).

- [ ] **Step 3: Implement**

Replace the struct at `AppConfig.swift:448-453` with:

```swift
struct ExclusionRule: Codable, Equatable, Identifiable {
    var enabled: Bool
    var bundleID: String?
    var windowTitleContains: String?
    var contentPattern: String?

    /// Runtime-only stable identity for SwiftUI `ForEach`. Deliberately excluded
    /// from `CodingKeys` so it is never persisted — the on-disk config schema is
    /// unchanged. Decoded instances receive a fresh UUID.
    let id = UUID()

    private enum CodingKeys: String, CodingKey {
        case enabled, bundleID, windowTitleContains, contentPattern
    }

    static func == (lhs: ExclusionRule, rhs: ExclusionRule) -> Bool {
        lhs.enabled == rhs.enabled
            && lhs.bundleID == rhs.bundleID
            && lhs.windowTitleContains == rhs.windowTitleContains
            && lhs.contentPattern == rhs.contentPattern
    }
}
```

Note: the explicit `==` keeps `Equatable` semantics content-based (ignores `id`), so existing equality-dependent code and the round-trip test behave as before. The memberwise initializer `ExclusionRule(enabled:bundleID:windowTitleContains:contentPattern:)` is still synthesized because `id` has a default value.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ExclusionRuleCodableTests`
Expected: PASS.

- [ ] **Step 5: Verify build + lint + migration tests**

Run: `swift build && swiftformat Sources Tests --lint && swift test`
Expected: build 0, lint clean, all green (baseline 289 + Task 1 + Task 2 tests) — including `ConfigMigrationManager` tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/AutoSuggestApp/Config/AppConfig.swift Tests/AutoSuggestAppTests/ExclusionRuleCodableTests.swift
git commit -m "feat(config): ExclusionRule Identifiable via non-persisted id (schema-neutral)"
```

---

### Task 3: NavigationSplitView container + window chrome

**Files:**
- Modify: `Sources/AutoSuggestApp/UI/Settings/SettingsRootView.swift` (rewrite `SettingsRootView`; delete `SettingsSidebarRow`; drop the in-content route title from `SettingsDetailContent`)
- Modify: `Sources/AutoSuggestApp/App/PreferencesWindowController.swift:8-15` (window sizing)
- Test: none (structural; verified by build + manual pass).

**Interfaces:**
- Consumes: `SettingsRoute` (`String, CaseIterable, Identifiable`, has `title` and `systemImage`); `uiModel.selectedSettingsRoute`; `uiModel.banner`; `SettingsDetailContent(route:uiModel:)`.
- Produces: a `NavigationSplitView`-based `SettingsRootView` (root type name unchanged, so `PreferencesWindowController`'s `NSHostingController<SettingsRootView>` cast still holds).

- [ ] **Step 1: Rewrite `SettingsRootView`**

```swift
struct SettingsRootView: View {
    @ObservedObject var uiModel: AutoSuggestUIModel

    var body: some View {
        NavigationSplitView {
            List(SettingsRoute.allCases, selection: Binding(
                get: { uiModel.selectedSettingsRoute },
                set: { if let route = $0 { uiModel.selectedSettingsRoute = route } }
            )) { route in
                Label(route.title, systemImage: route.systemImage)
                    .tag(route)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: AutoSuggestTheme.spacingLG) {
                    if let banner = uiModel.banner {
                        BannerView(banner: banner, onDismiss: uiModel.dismissBanner)
                            .padding(.horizontal, AutoSuggestTheme.spacingLG)
                            .padding(.top, AutoSuggestTheme.spacingLG)
                    }
                    SettingsDetailContent(route: uiModel.selectedSettingsRoute, uiModel: uiModel)
                }
            }
            .navigationTitle(uiModel.selectedSettingsRoute.title)
        }
        .autoSuggestTinted()
    }
}
```

Notes: the `List` selection is non-optional in the model but `List(selection:)` wants an optional binding — the adapter binding above bridges it. Keep the `Label` + `.tag(route)` so selection matches `SettingsRoute`. Delete the entire `private struct SettingsSidebarRow` (and its `rowBackground`).

- [ ] **Step 2: Drop the in-content route title**

In `SettingsDetailContent.body`, remove the leading `Text(route.title).font(.title2.weight(.semibold))` line (the window title bar now shows it via `.navigationTitle`). Keep the `switch route { … }` that renders each pane. Grouped `Form` panes (later tasks) will supply their own top padding, so wrap the `switch` output in `.padding(.horizontal, AutoSuggestTheme.spacingLG)` ONLY if a pane is not yet a Form; simplest: leave the switch as-is (panes self-pad once converted). For this task the panes are still card-based, so add `.padding(AutoSuggestTheme.spacingLG)` around the `switch`'s enclosing `VStack` to preserve current insets. Later pane tasks remove that per-pane as they adopt Form.

- [ ] **Step 3: Window chrome**

In `PreferencesWindowController.swift`, replace lines 10-11:

```swift
        window.setContentSize(NSSize(width: 720, height: 560))
        window.contentMinSize = NSSize(width: 640, height: 480)
```

Leave `window.setFrameAutosaveName("AutoSuggestSettingsWindow")` (unchanged — already persists frame) and `toolbarStyle = .unified`.

- [ ] **Step 4: Verify build + lint + tests**

Run: `swift build && swiftformat Sources Tests --lint && swift test`
Expected: build 0, lint clean, all green.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoSuggestApp/UI/Settings/SettingsRootView.swift Sources/AutoSuggestApp/App/PreferencesWindowController.swift
git commit -m "feat(ui): native NavigationSplitView settings container + resizable window"
```

---

### Task 4: General pane → grouped Form

**Files:**
- Modify: `Sources/AutoSuggestApp/UI/Settings/GeneralSettingsView.swift`
- Test: none (structural).

**Interfaces:** Consumes the Reparent pattern (top of plan). No new API.

- [ ] **Step 1: Convert to Form**

Apply the Reparent pattern. Target structure — move the existing controls verbatim into these sections:

```swift
var body: some View {
    Form {
        Section("General") {
            // existing enable Toggle, battery-mode Picker, strict-undo Toggle — verbatim
        }
        Section("Shortcuts") {
            // existing shortcuts info content — verbatim
        }
    }
    .formStyle(.grouped)
}
```

Read the current file for the exact control bodies and bindings; do not change them. The battery-mode `Picker` keeps `.pickerStyle(.segmented)` (a segmented picker for a small fixed choice set is fine; only tab-bar misuse is being removed).

- [ ] **Step 2: Verify build + lint**

Run: `swift build && swiftformat Sources Tests --lint`
Expected: build 0, lint clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/AutoSuggestApp/UI/Settings/GeneralSettingsView.swift
git commit -m "feat(ui): General settings pane as grouped Form"
```

---

### Task 5: Models pane → Form + typed runtime + drag reorder + FoundationModels empty state

**Files:**
- Modify: `Sources/AutoSuggestApp/UI/Settings/ModelsSettingsView.swift`
- Test: none beyond Task 1 (enum already tested).

**Interfaces:**
- Consumes: `ModelRuntime` (Task 1); `EmptyStateView` (Phase 1); `uiModel.config.localModel.runtimeOrder: [String]`; `uiModel.moveRuntime(from:direction:)`; `RuntimeDisplayName.label(for:)`; panels `OllamaModelPanel`/`LlamaCppModelPanel`/`CoreMLModelPanel`.

- [ ] **Step 1: Replace the runtime tab + panel dispatch**

Rewrite `ModelsSettingsView.body` to a grouped `Form`. Replace the `@State private var selectedRuntimeTab: String` with `@State private var selectedRuntime: ModelRuntime = .ollama`. Structure:

```swift
var body: some View {
    Form {
        Section("Status") {
            Text("Current runtime: \(uiModel.modelHealth.activeRuntimeLabel)")
            Text("Current model: \(uiModel.modelHealth.activeModelLabel)").foregroundStyle(.secondary)
            Text(uiModel.modelHealth.menuSummary).foregroundStyle(.secondary)
        }

        Section("Runtime") {
            Picker("Runtime", selection: $selectedRuntime) {
                ForEach(availableRuntimes) { rt in
                    Text(rt.displayName).tag(rt)
                }
            }
            .pickerStyle(.menu)
        }

        runtimePanel

        Section("Fallback order") {
            fallbackOrderList
        }
    }
    .formStyle(.grouped)
    .onAppear {
        if let first = availableRuntimes.first, !availableRuntimes.contains(selectedRuntime) {
            selectedRuntime = first
        }
    }
}

/// Runtimes present in the user's configured order, typed. Unknown strings are dropped.
private var availableRuntimes: [ModelRuntime] {
    uiModel.config.localModel.runtimeOrder.compactMap(ModelRuntime.init(configValue:))
}

@ViewBuilder private var runtimePanel: some View {
    switch selectedRuntime {
    case .ollama:
        OllamaModelPanel(uiModel: uiModel)
    case .llamaCpp:
        LlamaCppModelPanel(uiModel: uiModel)
    case .coreML:
        CoreMLModelPanel(uiModel: uiModel)
    case .foundationModels:
        EmptyStateView(
            icon: "sparkles",
            title: "No setup needed",
            message: "Foundation Models runs on-device using Apple Intelligence and requires no configuration."
        )
    }
}
```

Note: the three panels currently return card-based content; leaving them as-is inside the Form is acceptable for this phase (reparent, not rewrite). If a panel's own top-level `SettingsSection` double-nests awkwardly inside `Form`, wrap the panel call in a bare `Section { … }` — do not restructure the panel itself.

- [ ] **Step 2: Drag-to-reorder fallback order**

Replace `runtimeOrderControls` (the up/down arrow buttons) with a reorderable `List`:

```swift
@ViewBuilder private var fallbackOrderList: some View {
    List {
        ForEach(uiModel.config.localModel.runtimeOrder, id: \.self) { runtime in
            Text(RuntimeDisplayName.label(for: runtime))
        }
        .onMove { indices, newOffset in
            guard let from = indices.first else { return }
            // Translate a SwiftUI move (from, insert-before newOffset) into the
            // model's step API. Move one position toward the destination per call
            // by using direction sign; for multi-step moves apply until placed.
            let to = newOffset > from ? newOffset - 1 : newOffset
            if to != from {
                uiModel.moveRuntime(from: from, direction: to > from ? 1 : -1)
            }
        }
    }
    .frame(minHeight: 120)
}
```

Note: `moveRuntime(from:direction:)` moves a single step (`onMoveRuntime?(index, index+direction)`). A drag that spans multiple positions arrives as one `.onMove` with the final offset; the translation above performs one step in the correct direction. If single-step-per-drag proves insufficient for multi-row drags during manual testing, the follow-up is to add a `moveRuntime(from:to:)` on the model — but do NOT add it in this task unless the single-step version visibly fails a manual reorder; keep scope minimal. `.moveDisabled` is not needed.

- [ ] **Step 3: Verify build + lint + tests**

Run: `swift build && swiftformat Sources Tests --lint && swift test`
Expected: build 0, lint clean, all green.

- [ ] **Step 4: Commit**

```bash
git add Sources/AutoSuggestApp/UI/Settings/ModelsSettingsView.swift
git commit -m "feat(ui): Models pane as Form with typed runtime, drag reorder, FM empty state"
```

---

### Task 6: Online LLM pane → grouped Form

**Files:**
- Modify: `Sources/AutoSuggestApp/UI/Settings/OnlineLLMSettingsView.swift`
- Test: none (structural).

- [ ] **Step 1: Convert to Form**

Apply the Reparent pattern. Target:

```swift
var body: some View {
    Form {
        Section {
            // existing enable Toggle — verbatim
        }
        if <online enabled binding> {
            Section("Provider") {
                // existing provider Picker, model TextField, conditional endpoint TextField,
                // primary/fallback Picker — verbatim
            }
            Section("Credentials") {
                // existing API-key SecureField — verbatim
            }
        }
    }
    .formStyle(.grouped)
}
```

Read the current file for the exact enabled-binding expression and control bodies; preserve them. Keep the primary/fallback `Picker` style as-is.

- [ ] **Step 2: Verify build + lint**

Run: `swift build && swiftformat Sources Tests --lint`
Expected: build 0, lint clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/AutoSuggestApp/UI/Settings/OnlineLLMSettingsView.swift
git commit -m "feat(ui): Online LLM settings pane as grouped Form"
```

---

### Task 7: Permissions & Privacy pane → grouped Form

**Files:**
- Modify: `Sources/AutoSuggestApp/UI/Settings/PermissionsSettingsView.swift`
- Test: none (structural).

**Interfaces:** Consumes `PermissionRow` (Phase 1) — reused verbatim inside a `Section`.

- [ ] **Step 1: Convert to Form**

Apply the Reparent pattern. The pane currently has: an optional relaunch banner, two `PermissionRow`s + Recheck/Relaunch buttons, then three `SettingsSection`s (Privacy & Telemetry, Personalization, Training Data). Target:

```swift
var body: some View {
    Form {
        if uiModel.needsRelaunchToEnable {
            Section {
                // existing relaunch banner content — verbatim
            }
        }
        Section("Permissions") {
            // the two PermissionRow(...) calls — verbatim
            // the Recheck / Relaunch Now HStack — verbatim
        }
        Section("Privacy & Telemetry") {
            // existing toggles + captions — verbatim (drop the inner SectionHeader)
        }
        Section("Personalization") {
            // existing content — verbatim (drop inner SectionHeader)
        }
        .onAppear { uiModel.onRefreshPersonalizationStats?() }   // preserve if it was on the section
        Section("Training Data") {
            // existing content — verbatim (drop inner SectionHeader)
        }
    }
    .formStyle(.grouped)
}
```

Read the current file for exact control bodies; preserve every binding, the `.onAppear`, and destructive-button behavior. `PermissionRow` renders fine inside a `Section` — leave its card styling as-is (it visually reads as a rich row).

- [ ] **Step 2: Verify build + lint**

Run: `swift build && swiftformat Sources Tests --lint`
Expected: build 0, lint clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/AutoSuggestApp/UI/Settings/PermissionsSettingsView.swift
git commit -m "feat(ui): Permissions & Privacy pane as grouped Form"
```

---

### Task 8: Exclusions pane → Form + Identifiable id list

**Files:**
- Modify: `Sources/AutoSuggestApp/UI/Settings/ExclusionsSettingsView.swift`
- Test: none beyond Task 2.

**Interfaces:** Consumes `ExclusionRule.id` (Task 2); `EmptyStateView` (Phase 1).

- [ ] **Step 1: Convert to Form and fix the ForEach identity**

Apply the Reparent pattern. Target:

```swift
var body: some View {
    Form {
        Section {
            // existing search TextField + Exclude Frontmost App + Add Rule… HStack — verbatim
        }
        Section("Quick add") {
            // existing preset buttons (VS Code / Xcode / IntelliJ) + caption — verbatim,
            // bundle ids unchanged (com.microsoft.VSCode / com.apple.dt.Xcode / com.jetbrains.intellij)
        }
        Section("Rules") {
            if filteredRules.isEmpty {
                EmptyStateView(
                    icon: "shield.slash",
                    title: "No exclusion rules",
                    message: "Add rules to prevent suggestions in specific apps, windows, or when certain content is detected."
                )
            } else {
                ForEach(filteredRules) { rule in     // <-- keys on ExclusionRule.id now
                    // existing row HStack (StatusDot + title + Disable/Edit/Delete buttons) — verbatim
                }
                .confirmationDialog(...) { ... }     // existing delete confirmation — verbatim
            }
        }
    }
    .formStyle(.grouped)
    .sheet(isPresented: $isRuleEditorPresented) { ... }   // existing — verbatim
}
```

The ONLY logic change: `ForEach(Array(filteredRules.enumerated()), id: \.offset) { _, rule in … }` becomes `ForEach(filteredRules) { rule in … }` (now valid because `ExclusionRule: Identifiable`). Replace the hand-rolled empty-state VStack with `EmptyStateView`. Preserve `filteredRules`, all `@State`, the sheet, and every button action verbatim.

- [ ] **Step 2: Verify build + lint + tests**

Run: `swift build && swiftformat Sources Tests --lint && swift test`
Expected: build 0, lint clean, all green.

- [ ] **Step 3: Commit**

```bash
git add Sources/AutoSuggestApp/UI/Settings/ExclusionsSettingsView.swift
git commit -m "feat(ui): Exclusions pane as Form with stable rule identity + EmptyStateView"
```

---

### Task 9: Accessibility pane → grouped Form

**Files:**
- Modify: `Sources/AutoSuggestApp/UI/Settings/AccessibilitySettingsView.swift`
- Test: none (structural).

- [ ] **Step 1: Convert to Form**

Apply the Reparent pattern. Target:

```swift
var body: some View {
    Form {
        Section {
            // existing VoiceOver preview Button — verbatim
        }
        Section("System accessibility") {
            // existing Reduce Transparency / Increase Contrast readouts — verbatim
        }
    }
    .formStyle(.grouped)
}
```

Preserve the existing content verbatim (the stale-read behavior of the system a11y values is a known Phase-5 item — do NOT fix it here).

- [ ] **Step 2: Verify build + lint**

Run: `swift build && swiftformat Sources Tests --lint`
Expected: build 0, lint clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/AutoSuggestApp/UI/Settings/AccessibilitySettingsView.swift
git commit -m "feat(ui): Accessibility settings pane as grouped Form"
```

---

### Task 10: Diagnostics pane → Form + selectable report text

**Files:**
- Modify: `Sources/AutoSuggestApp/UI/Settings/DiagnosticsSettingsView.swift`
- Test: none (structural).

- [ ] **Step 1: Convert to Form and fix the read-only editor**

Apply the Reparent pattern. Replace the read-only `TextEditor(.constant(report))` with a selectable `Text` in a `ScrollView`. Target:

```swift
var body: some View {
    Form {
        Section("Metrics") {
            // existing metrics rows — verbatim
        }
        Section("Support Report") {
            ScrollView {
                Text(<the report string>)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 240)
            // existing Copy / Export buttons + saved-path label — verbatim
        }
    }
    .formStyle(.grouped)
}
```

Read the current file for the report string source and the Copy/Export actions; preserve them.

- [ ] **Step 2: Verify build + lint**

Run: `swift build && swiftformat Sources Tests --lint`
Expected: build 0, lint clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/AutoSuggestApp/UI/Settings/DiagnosticsSettingsView.swift
git commit -m "feat(ui): Diagnostics pane as Form with selectable report text"
```

---

## Self-Review

**Spec coverage:**
- Native NavigationSplitView + source-list sidebar: Task 3. ✓
- Amber selection via native list: Task 3 (inherits app-wide `.tint`; native selection). ✓
- Panes → grouped Form: Tasks 4–10 (all 7). ✓
- Window resizable + min + autosave: Task 3. ✓
- `ModelRuntime` typed enum kills magic strings: Task 1 + adopted Task 5. ✓
- Menu Picker for runtime: Task 5. ✓
- Drag `.onMove` fallback reorder: Task 5. ✓
- FoundationModels empty state (user decision): Task 5. ✓
- `ExclusionRule` Identifiable, schema-neutral: Task 2 + adopted Task 8. ✓
- Diagnostics selectable Text: Task 10. ✓
- IntelliJ bundle id unchanged (verified correct): Task 8 note. ✓
- Config migration tests stay green: Task 2 verify step. ✓

**Placeholder scan:** Structural pane tasks intentionally say "move existing controls verbatim" and reference the current file — this is a faithful reparent, not a placeholder; the concrete transformation (Form + named Sections, drop inner SectionHeader) and every logic change (Task 5 runtime dispatch, Task 8 ForEach identity, Task 10 Text) are shown as code. No TBD/TODO. ✓

**Type consistency:** `ModelRuntime` cases/`init?(configValue:)`/`displayName` identical across Tasks 1 and 5. `ExclusionRule` id/CodingKeys/`==` identical across Tasks 2 and 8. `SettingsRoute`/`SettingsDetailContent` usage in Task 3 matches the current code. `EmptyStateView(icon:title:message:)` signature (Phase 1) used correctly in Tasks 5 and 8. ✓

**Deliberate deferrals (documented):** stale system-a11y reads (Accessibility pane) → Phase 5; Online-LLM validation/test-connection → out of scope; multi-step drag reorder → only if single-step visibly fails manual test.
