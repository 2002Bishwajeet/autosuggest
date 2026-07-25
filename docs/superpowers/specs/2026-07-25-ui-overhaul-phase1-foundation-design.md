# UI Overhaul — Phase 1: Design Foundation

**Date:** 2026-07-25
**Status:** Approved (design), pending implementation plan
**Scope:** Foundation only — tokens + reusable native components, dropped into existing layouts. No window restructuring.

## Context

AutoSuggest is a menu-bar macOS app (SwiftUI hosted in AppKit). A UI audit against
the macOS HIG found the app reinvents native controls by hand and hardcodes sizes,
while a design-token file (`Sources/AutoSuggestApp/UI/DesignSystem.swift`,
`AutoSuggestTheme`) exists but is largely bypassed. This produces inconsistent
styling, weak Dynamic Type / accessibility behavior, and duplicate components.

This is Phase 1 of a five-phase overhaul. Direction chosen: **native structure with
an amber-forward brand identity** (option B) — HIG-correct controls and layout, with
amber (`AutoSuggestTheme.brand`) as a deliberate accent, amber retained as the brand color.

### The five phases (this doc = Phase 1)

1. **Design foundation** (this doc) — enforce tokens, add reusable native components.
2. **Settings window** — native `TabView` + `Form(.grouped)`, drag-reorder, contrast fixes.
3. **Menu-bar popover** → `MenuBarExtra(.window)`, single action surface.
4. **Onboarding** — step indicator, native paging, dedupe permission row.
5. **About + overlay polish** — standard About panel, overlay a11y/typography.

Each phase gets its own spec → plan → build → verify cycle. `swift build` +
`swift test` (286 tests) must stay green after every phase.

## Goals (Phase 1)

- Make `AutoSuggestTheme` the enforced single source of truth for spacing, radius,
  color, and typography.
- Apply amber as the app-wide tint (deliberate B choice).
- Replace the duplicate hand-rolled components with one canonical native-backed set.
- Do this as clean drop-in swaps into existing layouts — no structural window changes.

## Non-Goals (Phase 1)

- No `TabView` / `MenuBarExtra` / onboarding / About restructuring (later phases).
- No new features. No behavior changes beyond styling/accessibility.
- No changes to inference, policy, config, privacy, or overlay-positioning logic.

## Design

### 1. Tokens & theme

`AutoSuggestTheme` becomes enforced, not decorative.

- **Spacing** — collapse ad-hoc `14/16/24/28` to the existing scale
  (`spacingXS…XXL` = 4/8/12/16/24/32). Single 8pt grid. Fresh pass allows slightly
  more vertical breathing room via these tokens, but stays compact (utility app).
- **Radius** — collapse ad-hoc `8/10/12/14` to `radiusS/M/L`.
- **Color** — amber (`AutoSuggestTheme.brand`) applied as an app-wide `.tint()` so
  selection, key toggles, and primary buttons read amber regardless of the user's
  system accent. Everything else stays semantic (`.primary`/`.secondary`/system
  materials) so Dark Mode, Increase Contrast, and Reduce Transparency work for free.
  No forced `Color.white`-on-accent (that was the white-on-yellow contrast bug);
  rely on native selection styling / semantic label colors.
- **Typography** — semantic styles only (`.title2`/`.headline`/`.body`/`.callout`/
  `.caption`). No hardcoded `systemFont(ofSize:)` in SwiftUI views.

If the token scale is missing a needed step, extend the scale in `AutoSuggestTheme`
rather than hardcoding at the call site.

### 2. Reusable native components

One canonical set, HIG-native underneath, each replacing hand-rolled duplicates.
All live under `Sources/AutoSuggestApp/UI/` (exact file organization decided in the plan).

| Component | Purpose | Replaces |
|---|---|---|
| `SettingsSection` | Titled grouped container (wraps `GroupBox` / grouped `Form` row) | `SettingsCard` **and** `SimplePanel` |
| `StatusBadge` | Granted/Required-style capsule, token opacities | 3 divergent inline capsules (0.12/0.14/0.16) |
| `PermissionRow` | Icon tile + title + badge + action | `PermissionSettingsRow` **and** `PermissionDetailRow` |
| `EmptyStateView` | Icon + guidance for empty lists | Standardizes CoreML/Ollama's existing pattern |
| `InlineErrorCard` | Error message + Retry | Standardizes CoreML's existing pattern |

- `StatusDot` and `SectionHeader` are kept; `StatusDot` changes from a fixed 8px
  circle to a size that scales with Dynamic Type (e.g. `@ScaledMetric`).
- `EmptyStateView` / `InlineErrorCard` are introduced now but only *adopted* where a
  clean drop-in exists in Phase 1; Online-LLM / Diagnostics adopt them in later phases.

### 3. Component contracts (isolation)

Each component must be understandable and testable without reading consumers:

- `SettingsSection(title:) { content }` — no business logic; pure layout + tokens.
- `StatusBadge(text:, style:)` where `style` is a typed enum (e.g. `.granted`,
  `.required`, `.neutral`) — no stringly-typed inputs.
- `PermissionRow(icon:, title:, description:, badge:, action:)` — presentation only;
  caller owns the action.
- `EmptyStateView(icon:, title:, message:)` and `InlineErrorCard(message:, retry:)`
  — presentation only.

## Migration approach

Drop-in swap, surface by surface, verifying build + tests between swaps:

1. Add/adjust tokens in `AutoSuggestTheme` (extend scale if needed).
2. Apply app-wide amber `.tint()` at the hosting-view root(s).
3. Build the canonical components.
4. Replace each duplicate usage with the canonical component. Delete the old
   `SettingsCard`/`SimplePanel`/`PermissionSettingsRow`/`PermissionDetailRow` once no
   references remain.
5. Sweep remaining hardcoded spacing/radius/font values in the touched views to tokens.

## Testing

- `swift build` exits 0.
- `swift test` — all 286 tests green (no regressions).
- `swiftformat Sources Tests --lint` reports 0 files require formatting.
- Any component with non-trivial layout logic (e.g. `StatusDot` scaling) gets a small
  XCTest following the existing `Tests/AutoSuggestAppTests/` mirroring convention.
- Manual verification via the Xcode app target (per CLAUDE.md, AX/permission paths
  can't run in CI): visually confirm Settings/Permissions panels in Light + Dark and
  with a non-amber system accent, confirming amber tint + no white-on-accent.

## Risks

- **Regression surface**: touches many views. Mitigated by keeping Phase 1 to drop-in
  swaps (no restructuring) and verifying build/tests after each swap.
- **Amber tint over system accent**: deliberate; must be validated for contrast in both
  appearances. If amber-on-amber selection ever reads poorly, fall back to semantic
  label color for text on selected rows.
- **Shipping app**: signed/notarized release in the wild — no behavior changes in
  Phase 1 keeps risk to styling only.
