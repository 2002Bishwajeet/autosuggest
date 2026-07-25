# UI Overhaul — Phase 2: Settings Window (native)

**Date:** 2026-07-25
**Status:** Approved (design), pending implementation plan
**Branch:** `ui-overhaul-phase2`
**Depends on:** Phase 1 (design foundation) — merged to `main` (`fb2a604`).

## Context

Phase 2 of the five-phase UI overhaul (direction: native structure, amber-forward
brand, option B). Phase 1 delivered the token system and canonical components. Phase 2
rebuilds the **Settings window** to native macOS idioms.

Today the Settings window (`PreferencesWindowController` → `SettingsRootView`) is a
hand-rolled two-pane layout: a custom `ScrollView`+`ForEach` sidebar and per-pane content
built from `SettingsSection` cards. The window is a fixed `980×680`. The audit flagged:
reinvented `NavigationSplitView`, non-native sidebar, magic-string runtime switching in the
Models pane, up/down-arrow reordering instead of drag, `ForEach(id: \.offset)` identity bug
in Exclusions, and a read-only `TextEditor(.constant)` misuse in Diagnostics.

`SettingsRoute` already exists (`Sources/AutoSuggestApp/UI/AutoSuggestUIModel.swift:4`) as
`String, CaseIterable, Identifiable` with `title` and `systemImage` — ready for
`List(selection:)`.

## Goals

- Replace the hand-rolled sidebar with a native `NavigationSplitView` + source-list `List`.
- Convert the 7 panes to grouped `Form` (`.formStyle(.grouped)`), the standard macOS Settings look.
- Land amber selection correctly (the Phase 1 deferral) via native list selection.
- Kill the Models pane magic strings with a typed `ModelRuntime` enum.
- Drag-to-reorder the runtime fallback order (`.onMove`) instead of arrow buttons.
- Fix the Exclusions identity bug migration-free; fix the Diagnostics read-only misuse.
- Make the window properly resizable with sensible minimums.

## Non-Goals

- Menu-bar popover (Phase 3), onboarding (Phase 4), About/overlay (Phase 5).
- No changes to config schema, inference, policy, privacy, or the actual exclusion/model logic.
- No new settings/features. Restructuring + the enumerated audit fixes only.
- `SettingsSection` is **not** deleted (onboarding still uses it in Phase 4); it is simply no
  longer used inside the Settings window.

## Design

### 1. Navigation container

Rebuild `SettingsRootView` around `NavigationSplitView`:

- **Sidebar:** `List(selection: $uiModel.selectedSettingsRoute)` over `SettingsRoute.allCases`,
  each row `Label(route.title, systemImage: route.systemImage)`, `.listStyle(.sidebar)`.
  Native selection + keyboard nav + vibrancy. Amber selection comes from the app-wide
  `.tint` (Phase 1) applied to the native list — contrast is correct because the system
  chooses the selected-row text color. Delete the custom `SettingsSidebarRow` struct.
- **Detail:** the selected pane, with `.navigationTitle(route.title)`. The per-pane title
  `Text` currently rendered inside `SettingsDetailContent` is removed (the window title bar
  shows it instead). The `route` switch that maps to each pane view is retained.
- `.navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)` on the sidebar.
- **Banner:** the existing `BannerView` (kept from Phase 1) renders above the detail content.
- **Entry point:** `PreferencesWindowController.show(route:)` still just sets
  `uiModel.selectedSettingsRoute`; the cast to `NSHostingController<SettingsRootView>` in
  that controller is preserved (root type stays `SettingsRootView`).

### 2. Window chrome (`PreferencesWindowController`)

- Drop the fixed `980×680` / min `860×620`. New: `contentMinSize` ~`640×480`, initial content
  size ~`720×560`, freely resizable.
- Keep `.unified` toolbar style (now meaningful — the split view sits under a unified title bar).
- `setFrameAutosaveName` so window size/position persist across launches (HIG 2.5).

### 3. Panes → grouped `Form`

Each pane view becomes `Form { … }.formStyle(.grouped)` with native `Section`s replacing
`SettingsSection` cards. Toggles/pickers/steppers become plain Form rows (native
label/control alignment). Panes and their section structure:

- **General:** Section "General" (enable toggle, battery-mode picker, strict-undo toggle) +
  Section "Shortcuts" (informational).
- **Models:** see §4.
- **Online LLM:** enable toggle; when on, Section "Provider" + Section "Credentials"
  (`SecureField`). (Deeper Online-LLM validation is out of scope — structure only.)
- **Permissions & Privacy:** Section "Permissions" (two `PermissionRow`s + Recheck/Relaunch),
  Section "Privacy & Telemetry", Section "Personalization", Section "Training Data". The
  `PermissionRow` component (Phase 1) is reused as-is inside the Form.
- **Exclusions:** see §5.
- **Accessibility:** Section with the VoiceOver preview + system a11y state readouts.
- **Diagnostics:** Section "Metrics" + Section "Support Report" — see §6.

### 4. Models pane

- Add `enum ModelRuntime: String, CaseIterable, Identifiable` with cases `ollama`,
  `llamaCpp`, `coreML`; `id { rawValue }`; `title` ("Ollama" / "llama.cpp" / "Core ML").
  This **replaces** the stringly-typed dispatch on `"ollama"`/`"llama.cpp"`/`"llamacpp"`/
  `"llama_cpp"`. A single mapping from the config's stored runtime string to `ModelRuntime`
  lives on the enum (`init?(configValue:)`) so the triple-spelling tolerance is centralized
  and tested, not scattered.
- A `Picker("Runtime", selection:)` with `.pickerStyle(.menu)` selects the active
  `ModelRuntime` (menu, not segmented — segmented-as-tab-bar was the anti-pattern being removed);
  the chosen runtime's existing panel (`OllamaModelPanel` / `LlamaCppModelPanel` /
  `CoreMLModelPanel`) renders below as Form `Section`s. The panels keep their current internals
  (this phase reparents them into the Form, not rewrites them).
- **Fallback order:** replace the `DisclosureGroup` + up/down arrow buttons with a `List`
  using `.onMove` for drag-to-reorder, calling the existing reorder callback with the new
  order. Keyboard reorder affordance retained via the existing move action.

### 5. Exclusions pane

- **Identity fix (migration-free):** conform `ExclusionRule` (`AppConfig.swift:448`,
  `Codable, Equatable`) to `Identifiable` by adding a non-persisted `let id = UUID()` **plus
  an explicit `CodingKeys`** enumerating only the existing stored keys (`enabled`, `bundleID`,
  `windowTitleContains`, `contentPattern`) so `id` is never encoded/decoded and the on-disk
  schema is unchanged. The rules `ForEach` keys on `\.id` instead of `\.offset`.
- Convert the search field + preset buttons + rules list into Form `Section`s. Keep the
  existing per-row Edit/Delete actions and behavior unchanged (delete keeps its confirmation
  dialog) — this task reparents the list into the Form and fixes identity, it does not
  redesign the row actions.
- Preset bundle ids are correct as-is (`com.microsoft.VSCode`, `com.apple.dt.Xcode`,
  `com.jetbrains.intellij` = IntelliJ IDEA Ultimate) — **no change**.
- `ExclusionRuleEditorView` sheet: keep behavior; move its fields into a `Form` for native
  alignment.

### 6. Diagnostics pane

- Replace the read-only `TextEditor(.constant($report))` with a selectable `Text(report)`
  inside a `ScrollView` (`.textSelection(.enabled)`), preserving Copy/Export buttons and the
  saved-path label. Metrics become a Form Section.

## New types & their contracts

- `enum ModelRuntime: String, CaseIterable, Identifiable` — `title: String`,
  `init?(configValue: String)` mapping the tolerated spellings; pure, testable, no UI.
- `ExclusionRule: Identifiable` — runtime-only `id`, persistence unchanged.

## Testing

- `swift build` exits 0; `swift test` all green (baseline 289) plus new tests; `swiftformat
  Sources Tests --lint` clean — after every task.
- **New unit tests (mirroring convention, `@testable import AutoSuggestApp`):**
  - `ModelRuntimeTests` — `init?(configValue:)` maps `"ollama"`→`.ollama`,
    `"llama.cpp"`/`"llamacpp"`/`"llama_cpp"`→`.llamaCpp`, `"coreml"`/`"core_ml"`→`.coreML`,
    unknown→`nil`; `allCases` order and `title`s.
  - `ExclusionRuleCodableTests` — encode→decode round-trip preserves the 4 stored fields and
    the emitted JSON contains **no** `id` key; two rules with equal content have distinct
    `id`s (fresh UUIDs).
  - Config migration tests (`ConfigMigrationManager`) must remain green — proves the
    `ExclusionRule` change is schema-neutral.
- Layout verified via the Xcode app target (`macos/`, `xcodegen generate` first): each pane in
  Light + Dark, sidebar amber selection + contrast, window resize + min size, drag-reorder of
  fallback order.

## Risks

- **`AppConfig.swift` is a critical file** (CLAUDE.md). The `ExclusionRule` change is purely
  additive (non-encoded property + explicit CodingKeys preserving existing keys); the
  migration-test suite is the guardrail.
- **Form(.grouped) restructuring touches all 7 panes** — largest surface of the phase.
  Mitigated by converting one pane per task, gating on build/test each time, and keeping panel
  internals (Ollama/CoreML/etc.) intact — reparented, not rewritten.
- **Amber selection contrast** — resolved by using native `List` selection (system picks the
  selected-text color); no hardcoded foreground.
- **Window autosave name** must be unique and stable so persisted frames restore correctly.
