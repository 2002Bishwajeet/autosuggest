# UI Overhaul — Phase 5: Overlay accessibility & typography

Final phase of the five-phase UI overhaul (roadmap in the Phase 1 spec).
Roadmap said "standard About panel, overlay a11y/typography"; the About half is
**dropped by decision** — the existing custom branded About window
(`UI/AboutWindowController.swift`) already fulfills the roadmap's intent and is
better than the stock panel. Phase 5 is overlay-only.

Branch: `ui-overhaul-phase5`, off `main` at `a0b3d6c` (Phase 4 merged).

## Current state

`Sources/AutoSuggestApp/Suggestions/FloatingOverlayRenderer.swift` renders the
inline ghost-text suggestion in a borderless non-activating `NSPanel`.
Already correct: real-field font via AX (`GhostTextLayout.resolvedFont` tier 1),
caret-height-derived fallback size (tier 2), `placeholderTextColor` ghost color,
reduce-motion honored on fades.

Remaining gaps:

1. **Increase Contrast ignored** — ghost text stays `placeholderTextColor`
   (very dim) even when the user enables System Settings → Accessibility →
   Display → Increase contrast.
2. **Final fallback font is hardcoded 13pt** — `GhostTextLayout.resolvedFont`
   tier 3 (`GhostTextLayout.swift:28`) uses `NSFont.systemFont(ofSize: 13)`,
   ignoring the user's system text-size preference.
3. **VoiceOver behavior is implicit** — suggestions are spoken by the
   pipeline's `AccessibilityAnnouncer`; the overlay's label is not explicitly
   hidden from the accessibility tree, so double-speak is prevented only by
   luck of `NSPanel` configuration.

## Goals

- Ghost text becomes legible under Increase Contrast.
- The no-AX-no-caret fallback font follows the system body text preference.
- The overlay's invisibility to VoiceOver becomes an explicit, documented,
  enforced invariant.

## Non-Goals

- No About window changes (dropped, see above).
- No overlay positioning, sizing, animation, or panel-configuration changes.
- No changes to `AccessibilityAnnouncer` or the pipeline.
- No new components or files beyond tests.

## Design

### 1. Contrast-aware ghost color (`FloatingOverlayRenderer`)

- Replace the static `ghostTextColor` constant's use at render time with a pure
  helper on `FloatingOverlayRenderer`:
  `static func ghostColor(increaseContrast: Bool) -> NSColor` — returns
  `.secondaryLabelColor` when `increaseContrast`, else `.placeholderTextColor`.
- `showSuggestion` re-applies
  `ghostColor(increaseContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)`
  to the text field on every call — the setting can change mid-session, and
  per-show reassignment is cheap.
- The existing `ghostTextColor` static stays (it documents the default and is
  referenced in comments/tests) but delegates to `ghostColor(increaseContrast: false)`.

### 2. System-size fallback font (`GhostTextLayout`)

- Tier 3 of `resolvedFont(axFont:caretRect:)` changes from
  `NSFont.systemFont(ofSize: 13, weight: .regular)` to
  `NSFont.preferredFont(forTextStyle: .body)`.
- Tiers 1 (AX font) and 2 (caret-height-derived size) are untouched — when the
  caret rect is known, matching the field's visual size beats the system
  preference.

### 3. Explicit VoiceOver hiding (`FloatingOverlayRenderer.ensurePanel`)

- Set `textField.setAccessibilityElement(false)` and
  `panel.contentView?.setAccessibilityElement(false)` when building the panel,
  with a comment stating the invariant: suggestions are announced by
  `AccessibilityAnnouncer`; the ghost label must stay out of the AX tree or
  VoiceOver users hear every suggestion twice.

## Error handling

No new failure modes — all three changes are pure presentation with total
functions.

## Testing

- `swift build`, `swift test`, `swiftformat Sources Tests --lint` green (the
  standing per-phase gate), plus the Xcode app target builds.
- New unit tests:
  - `ghostColor(increaseContrast: true)` == `.secondaryLabelColor`;
    `false` == `.placeholderTextColor`; `ghostTextColor` == the `false` case.
  - `resolvedFont(axFont: nil, caretRect: nil)` returns
    `NSFont.preferredFont(forTextStyle: .body)`; AX-font and caret-rect tiers
    still take precedence (existing behavior locked).
- Increase Contrast and VoiceOver behavior are not CI-testable; verified
  manually by toggling the setting with the app running.

## Files touched

| File | Change |
| --- | --- |
| `Suggestions/FloatingOverlayRenderer.swift` | ghost color helper + per-show application + AX hiding |
| `Suggestions/GhostTextLayout.swift` | tier-3 fallback font |
| `Tests/AutoSuggestAppTests/FloatingOverlayRendererTests.swift` | color helper tests (new file) |
| `Tests/AutoSuggestAppTests/GhostTextLayoutTests.swift` | fallback font test (extend existing) |
