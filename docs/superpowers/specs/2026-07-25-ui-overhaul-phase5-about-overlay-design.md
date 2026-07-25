# UI Overhaul — Phase 5: About Window + Overlay Polish

**Date:** 2026-07-25
**Status:** Approved (design), pending implementation plan
**Depends on:** Phases 1–4, all merged to `main` (through `a0b3d6c`).

## Context

Final phase of the five-phase UI overhaul. A small, surgical cleanup pass: fix the branded
About window's real bugs, add one missing overlay color token, make one settings screen's
system-state reads live, and delete a dead token. Direction: keep the amber-forward branded
About (option A) rather than swapping to the bare standard panel.

## Goals & Non-Goals

**Goals:** fix the four audit items below without restructuring anything.
**Non-Goals:** no new About/overlay features; no change to overlay positioning/geometry (critical
caret-drawing path — `FloatingOverlayRenderer` / `GhostTextLayout` stay behaviorally identical
except the color token); no change to the About window's branded layout/content beyond the
enumerated fixes; no new dependencies.

## Design

### 1. About window — keep branded, fix the bugs (`UI/AboutWindowController.swift`)

`AboutView` stays (app icon, tagline, version, amber GitHub/issues `Link`s). Fixes:
- **Force-unwrapped URLs** (lines 32–33: `URL(string:)!`) → optional `private let repoURL: URL?` /
  `issuesURL: URL?`, and render each `Link` only inside `if let` so there is no crash path.
- **Stale version fallback** (line 76: `?? "0.3.0"`) → a neutral fallback. If
  `CFBundleShortVersionString` is missing, show `"Version —"`, never a wrong hardcoded number.
  Extract `versionString` building into a tiny pure helper so it is unit-testable.
- **Fixed width** (line 71: `.frame(width: 340)`) → `.frame(minWidth: 300, idealWidth: 340)`;
  the hosting controller already uses `.preferredContentSize`, so content drives height and the
  window sizes itself.

### 2. Overlay ghost-text color token (`UI/DesignSystem.swift`, `Suggestions/FloatingOverlayRenderer.swift`)

- Add `AutoSuggestTheme.ghostText` — a semantic `Color`/`NSColor` for the dimmed inline
  continuation (mapping to `.placeholderTextColor`, the current adaptive value, now named and
  single-sourced).
- `FloatingOverlayRenderer` uses `AutoSuggestTheme.ghostText` (as `NSColor`) instead of the
  inline `.placeholderTextColor`. No geometry, font-resolution, animation, or reduce-motion
  behavior changes — this is a rename-to-token only, so the rendered pixels are identical today
  but the color is now centrally themeable.

### 3. Live accessibility-state reads (`UI/Settings/AccessibilitySettingsView.swift`)

The "Reduce Transparency" / "Increase Contrast" rows read
`NSWorkspace.shared.accessibilityDisplay…` once at render, going stale if the user flips the
system setting while the window is open. Fix: hold the two values in `@State`, seed them on
appear, and refresh them via
`NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)`
(`.onReceive`). The `settingRow` rendering is unchanged; only the data source becomes live.

### 4. Delete the dead `radiusExtraSmall` token (`UI/DesignSystem.swift`, `DesignSystemTests`)

`AutoSuggestTheme.radiusExtraSmall` (added in Phase 1 "for later") has no consumer and no
natural 6pt use in this phase. YAGNI: delete the token and the `radiusExtraSmall` assertion in
`DesignSystemTests.testRadiusScaleIsMonotonic` (keep the remaining `radiusSmall < radiusMedium <
radiusLarge` chain). If a 6pt radius is ever needed, re-add it then.

## Testing

- Per-phase gate: `swift build` exits 0, `swift test` green, `swiftformat Sources Tests --lint`
  clean — after every task.
- **New/changed unit tests:**
  - `AboutView` version helper: given a present short-version + build → `"Version X (Y)"`; given
    a missing short-version → `"Version —"` (no `"0.3.0"`). (Extract the helper as a testable
    pure function, e.g. `AboutVersion.string(shortVersion:build:)`.)
  - `DesignSystemTests`: drop the `radiusExtraSmall` assertion; the remaining monotonic-scale
    test still passes.
- Manual (system/critical paths, per CLAUDE.md): the overlay still renders dimmed ghost text at
  the caret unchanged; toggling macOS Reduce Transparency / Increase Contrast while the
  Accessibility settings pane is open updates the On/Off rows live; the About window opens,
  links work, sizes to content, shows the correct version.

## Risks

- **Concurrent-agent overlap on the About window.** Another agent recorded About-window
  observations on 2026-07-25 (~8:10pm) and a separate `fix-about-window` branch / PR #6 already
  exists that "uses real app icon + correct clickable links, cleaner auto-sized layout." Part 1
  overlaps both. **Before implementing Part 1, reconcile:** confirm whether `fix-about-window`
  (or the concurrent agent) already lands these exact fixes; if so, drop Part 1 and rebase this
  phase onto that work rather than duplicating it. Parts 2–4 do not overlap and are safe to build
  independently.
- **Overlay is a critical caret-drawing path.** Part 2 is deliberately a color-token rename only;
  do not touch positioning, font resolution, or the fade/reduce-motion logic.
- **`radiusExtraSmall` deletion** touches the Phase-1 `DesignSystemTests`; update that one
  assertion in the same task so the suite stays green.
