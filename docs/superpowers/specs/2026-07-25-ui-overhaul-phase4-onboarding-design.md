# UI Overhaul — Phase 4: Onboarding

Phase 4 of the five-phase UI overhaul (see Phase 1 spec for the roadmap and the
amber-forward native direction). Scope per the roadmap: **step indicator, native
paging, dedupe permission row**.

Branch: `ui-overhaul-phase4`, off `main` at `82d6fb8` (Phase 3 merged).

## Current state

`Sources/AutoSuggestApp/UI/OnboardingFlowView.swift` renders a 4-step wizard
(`welcome → permissions → model → finish`) as a manual `switch` inside a
`ScrollView`. Problems this phase fixes:

1. **No progress indication.** The user cannot tell how many steps remain or
   where they are.
2. **No transition.** Step changes swap content with no motion; the wizard feels
   like a page reload, not paging.
3. **Duplicated permission pair.** The Accessibility + Input Monitoring rows are
   built independently in `OnboardingFlowView.permissionsStep` (lines ~254–279)
   and `Settings/PermissionsSettingsView.swift` (lines ~34–49), with **diverged
   copy** (e.g. onboarding says "read what you're typing… Required for core
   functionality", Settings says "read the text around your cursor…") and
   different action sets.

## Goals

- A dot page control communicating position in the 4-step flow.
- Direction-aware animated paging between steps.
- One canonical permission checklist shared by onboarding and Settings, ending
  the copy divergence.

## Non-Goals

- No new/removed/reordered onboarding steps.
- No changes to permission logic (`PermissionManager`), model download logic, or
  any non-UI behavior.
- No rewrite of welcome/model/finish step content beyond wiring in the
  indicator and paging.
- The Settings relaunch banner, "Recheck"/"Relaunch Now" controls, and the
  onboarding relaunch banner stay per-context (they genuinely differ).

## Design

### 1. `OnboardingStepIndicator` (new, `UI/Components/`)

A dot page control. Pure view, no model dependency:

- API: `OnboardingStepIndicator(total: Int, current: Int)`.
- Rendering: `total` circles in an `HStack`, centered. The `current` dot filled
  `AutoSuggestTheme.brand` (amber) with a subtle scale-up; other dots
  `Color.secondary.opacity(…)` at base size. Scale animation disabled under
  `accessibilityReduceMotion`.
- Accessibility: the row exposes a single element, label "Step N of M".
- Placement: in `OnboardingFlowView`, centered below the title/subtitle block,
  above the step content.
- `current` is clamped to `0..<total` defensively; a tiny pure helper
  (`clampedIndex`) carries one unit test.

### 2. Native paging in `OnboardingFlowView`

macOS has no page-style `TabView`, so the native wizard pattern is an animated
transition on content change:

- Track navigation direction: `moveForward()` / `moveBackward()` record
  `isAdvancing` before mutating `step`.
- The step content gets `.transition(.asymmetric(insertion: .move(edge:
  isAdvancing ? .trailing : .leading).combined(with: .opacity), removal:
  .move(edge: isAdvancing ? .leading : .trailing).combined(with: .opacity)))`,
  driven by `withAnimation(.easeInOut(duration: ~0.25))` around the step
  mutation and `.id(step)` on the content group.
- Under `accessibilityReduceMotion`: plain `.opacity` crossfade, no slide.
- The existing single `ScrollView` stays where it is, wrapping the step
  content; the `.id(step)` + transition apply to the group inside it.

### 3. `PermissionsChecklist` (new, `UI/Components/`) — dedupe, option A

One view owning the canonical icon + title + description for the two
permissions, rendering both `PermissionRow`s:

- API: `PermissionsChecklist(context:accessibilityGranted:inputMonitoringGranted:actions:)`
  where `context` is `.onboarding` or `.settings` and `actions` is a small
  struct of closures (`requestAccessibility`, `openAccessibilitySettings`,
  `requestInputMonitoring`, `openInputMonitoringSettings`).
- Canonical copy (single source of truth, replacing both diverged variants):
  - **Accessibility** — "Lets AutoSuggest read the text around your cursor and
    insert completions into any text field. Required for suggestions to work."
  - **Input Monitoring** — "Lets AutoSuggest detect Tab, Enter, and Esc so you
    can accept or dismiss suggestions. Requires a relaunch after granting."
- Per-context actions (behavior of each screen is preserved):
  - `.onboarding`: primary "Show Prompt" / "Register App" (fires the TCC
    prompt), secondary "Open Settings".
  - `.settings`: primary "Open System Settings" only.
- Call sites: `OnboardingFlowView.permissionsStep` and
  `PermissionsSettingsView` each collapse their two `PermissionRow` blocks into
  one `PermissionsChecklist`. Banners/footers around it are untouched.
- Canonical copy is testable: title/description exposed via a small
  `PermissionCopy` enum so a unit test locks the two screens to identical text.

## Error handling

No new failure modes: the indicator and paging are pure presentation; the
checklist forwards to the same `PermissionManager`/`AutoSuggestUIModel` calls
each screen already makes.

## Testing

- `swift build`, `swift test`, `swiftformat --lint` green (the standing
  per-phase gate).
- New unit tests: step-indicator index clamping; `PermissionCopy` canonical
  strings used by both contexts.
- Paging/animation and TCC prompts are not CI-testable (per CLAUDE.md); verify
  by launching the app and stepping through onboarding manually.

## Files touched

| File | Change |
| --- | --- |
| `UI/Components/OnboardingStepIndicator.swift` | new |
| `UI/Components/PermissionsChecklist.swift` | new (incl. `PermissionCopy`) |
| `UI/OnboardingFlowView.swift` | indicator + paging + checklist adoption |
| `UI/Settings/PermissionsSettingsView.swift` | checklist adoption |
| `Tests/AutoSuggestAppTests/OnboardingStepIndicatorTests.swift` | new |
| `Tests/AutoSuggestAppTests/PermissionsChecklistTests.swift` | new |
