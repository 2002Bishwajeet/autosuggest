# AX Compatibility Matrix

Per-app behaviour of the accessibility reads the inline ghost text pipeline depends on
(`AXValue`, `AXSelectedTextRange`, `AXBoundsForRange`, the WebKit `AXTextMarker` family,
`AXAttributedStringForRange`, `AXSecureTextField`). Tracking issue: #30.

This is observation-only reverse engineering of the same public AX surface VoiceOver uses —
no injection, no private frameworks.

> Not the same file as `docs/accessibility-compatibility-matrix.md`, which is the
> VoiceOver / Switch Control QA checklist for our own UI.

## Running the probe

```sh
swift scripts/ax-probe.swift                        # watch mode — one row per new app/field
swift scripts/ax-probe.swift --once                 # probe whatever is focused right now
swift scripts/ax-probe.swift --once --expect <bid>  # ...but fail if focus is not that app
```

`--expect` exists for scripted collection: focus can move between the keystroke that
targets an app and the read, and a row silently attributed to the wrong app is worse
than no row.

The probe needs Accessibility permission for **the terminal running it**
(System Settings → Privacy & Security → Accessibility → add Terminal / iTerm / Ghostty).
Without it every read returns `kAXErrorAPIDisabled (-25204)` and the script exits 1 with
instructions. It prints text *lengths*, never contents — safe to paste into this file.

In watch mode: click into a text field in each target app, type a few characters, and a
markdown row prints. Work down the table below, then paste the rows into Results.

Two things learned driving this in bulk, worth knowing before re-running it:

- Opening a file in an editor does **not** focus its text surface. VS Code first reported
  `AXValue` len 0 and only exposed text after a real click into the editor — an unfocused
  probe reads as "app unsupported" when it is nothing of the kind. Confirm the caret is in
  the field before trusting a `FAIL`.
- Tabbing between fields is unreliable (it escapes into browser chrome). Single-field pages
  that call `.focus()` themselves are far more repeatable.

## How to read the columns

| Column | Meaning / what a failure implies |
|---|---|
| `Focus path` | Which element resolved `AXFocusedUIElement`. `per-app` means the system-wide read failed — see "System-wide focus reads" below. |
| `AXValue` | Full field text readable. `FAIL` → no context to complete from; app is unsupported. |
| `AXSelectedTextRange` | Collapsed caret offset. Flagged `OUT OF BOUNDS` if past the text length. Also reports UTF-16 vs grapheme length when they diverge (emoji/CJK off-by-N risk). |
| `Bounds (caret)` | `AXBoundsForRange` on the zero-length caret range. `zero-rect` → app returns `.zero` instead of an error; we fall back. |
| `Bounds (1-char)` | The 1-char-before-caret fallback `extractCaretRect` uses. If both bounds columns fail, we cannot anchor ghost text and must not draw. |
| `MarkerRange` | WebKit `AXSelectedTextMarkerRange` present, and whether bounds/string work off it. Expected path for Safari. |
| `Font` | `AXAttributedStringForRange` → `.font`. `FAIL` → renderer falls back to the caret-height heuristic. |
| `Secure` | `AXSubrole == AXSecureTextField`. **Any password field that reports `no` here is a hard safety finding — file it immediately and blocklist the app.** |
| `Native suggestion` | Apple inline-prediction markers present (double-ghost suppression, B5). |

## Targets

Engine column verified on this machine by inspecting each bundle for
`Contents/Frameworks/Electron Framework.framework`; bundle IDs read from each `Info.plist`.

| App | Bundle ID | Engine | Unlock listed? |
|---|---|---|---|
| TextEdit | `com.apple.TextEdit` | AppKit | n/a |
| Notes | `com.apple.Notes` | AppKit | n/a |
| Mail | `com.apple.mail` | AppKit | n/a |
| Messages | `com.apple.MobileSMS` | AppKit | n/a |
| Xcode | `com.apple.dt.Xcode` | AppKit | n/a |
| Safari | `com.apple.Safari` | WebKit | n/a |
| Chrome | `com.google.Chrome` | Chromium | yes |
| Brave | `com.brave.Browser` | Chromium | yes |
| Edge | `com.microsoft.edgemac` | Chromium | yes |
| Arc | `company.thebrowser.Browser` | Chromium | yes |
| Firefox | `org.mozilla.firefox` | Gecko | no — separate AX stack, probe before assuming anything |
| VS Code | `com.microsoft.VSCode` | Electron | yes (added, was missing) |
| Antigravity | `com.google.antigravity` | Electron | yes (added, was missing) |
| Slack | `com.tinyspeck.slackmacgap` | Electron | yes |
| Discord | `com.hnc.Discord` | Electron | yes |
| Signal | `org.whispersystems.signal-desktop` | Electron | yes (added, was missing) |
| Obsidian | `md.obsidian` | Electron | yes (added, was missing) |
| Notion | `notion.id` | Electron | yes |
| WhatsApp | `net.whatsapp.WhatsApp` | native | n/a |
| Telegram | `ru.keepcoder.Telegram` | native (Swift) | n/a |
| Terminal | `com.apple.Terminal` | AppKit | n/a — expected unsupported, confirm then blocklist |
| Ghostty | `com.mitchellh.ghostty` | custom | n/a — expected unsupported, confirm then blocklist |

## Results

Collected 2026-07-26, macOS 15 (Darwin 25.5.0), Apple Silicon. Web rows come from local
single-field pages (`textarea`, `input`, `input type=password`, `contenteditable`) so the
same content is compared across engines. Bounds are AX screen coordinates.

| App / surface | Role | AXValue | Caret | Bounds (caret) | Bounds (1-char) | Marker | Font | Secure |
|---|---|---|---|---|---|---|---|---|
| **TextEdit** plain text | `AXTextArea` | len 44 | 44 | `453,92 0x13` | `447,105 7x13` | no | Menlo-Regular 11 | no |
| **Safari** textarea | `AXTextArea` | len 44 | 44 | `367,218 2x18` | `363,218 6x18` | yes | Helvetica 16 | no |
| **Safari** input | `AXTextField` | len 38 | 38 | `233,217 2x13` | `226,217 9x13` | yes | .SFNS-Regular 11 | no |
| **Safari** password | `AXTextField:AXSecureTextField` | len 16 | 16 | `156,217 2x13` | `149,217 9x13` | yes | .SFNS-Regular 11 | **YES** |
| **Safari** contenteditable | `AXTextArea` | len 51 | 1 | `58,222 2x18` | `47,222 13x18` | yes | Helvetica 16 | no |
| **Safari** address bar | `AXTextField` | len 133 | 133 | `1007,37 0x16` | `1004,53 3x16` | no | — | no |
| **Brave** textarea | `AXTextArea` | len 44 | 44 | `362,240 0x18` | `358,240 4x18` | yes | (size 16 only) | no |
| **Brave** input | `AXTextField` | len 38 | 38 | `253,240 0x15` | `246,240 7x15` | yes | (size 13.3 only) | no |
| **Brave** password | `AXTextField:AXSecureTextField` | len 16 | 16 | `117,240 0x15` | `112,240 5x15` | yes | (size 13.3 only) | **YES** |
| **Brave** contenteditable | `AXTextArea:AXApplicationGroup` | len 51 | 1 | **zero-rect** | **zero-rect** | yes | (size 16 only) | no |
| **Brave** address bar | `AXTextField` | len 133 | 133 | **zero-rect** | **zero-rect** | no | — | no |
| **Firefox** textarea | `AXTextArea:AXUnknown` | len 44 | 44 | `363,210 1x16` | `358,210 4x16` | yes | Helvetica 16 | no |
| **Firefox** input | `AXTextField:AXUnknown` | len 38 | 38 | `264,210 1x16` | `257,210 8x16` | yes | .SF NS 13 | no |
| **Firefox** password | `AXTextField:AXSecureTextField` | len 16 | 16 | `141,210 1x16` | `135,210 6x16` | yes | .SF NS 13 | **YES** |
| **Firefox** contenteditable | `AXTextArea:AXApplicationGroup` | len 51 | 1 | `58,216 1x16` | `47,216 12x16` | yes | Helvetica 16 | no |
| **VS Code** editor (Monaco) | `AXTextArea` | len 50 | 50 | **zero-rect** | **zero-rect** | yes | (size 12 only) | no |
| **VS Code** quick-open | `AXStaticText` | len 19 | 0 | zero-rect | FAIL | yes | (size 13 only) | no |
| **Antigravity** editor | `AXWebArea` | len 0 | 0 | zero-rect | FAIL | yes | (size 16 only) | no |
| **Messages** composer (empty) | `AXTextField` | FAIL | 0 | `614,766 0x16` | FAIL | no | FAIL | no |
| **Terminal.app** | `AXTextArea` | len 71 | 48 | zero-rect | `647,140 7x14` | no | FAIL | no |
| **Ghostty** | `AXTextArea` | len 2286 | 0 | FAIL | FAIL | no | FAIL | no |

### Not yet covered

| App | Why |
|---|---|
| Notes, Mail | Focus landed on `AXTable` (note/message list). The compose surface needs a human click — run watch mode. |
| Slack, Discord, WhatsApp, Telegram | Focus landed on `AXGroup:AXApplicationDialog` / `AXWebArea` root / `AXButton` / `AXWindow`. Composers need a human click; blind-clicking a live chat app risks hitting a channel, link or message action. |
| Xcode | Not probed. |
| Chrome, Edge, Arc, Signal, Obsidian, Notion | Not installed on the probe machine. |

Slack and Discord *did* return a reachable, font-carrying AX tree after the
`AXManualAccessibility` ping, so the unlock itself works there — only the focused
element was wrong.

## Findings

### Font was read from the wrong attribute in every app (fixed)

`AXFontExtraction` looked for the font under `NSAttributedString.Key.font` and
`kCTFontAttributeName`. **No app populates either.** Every app that exposes a font does it
under AX's own `AXFont` key (`kAXFontTextAttribute`), whose value is a *dictionary*:

```
AXFont = { AXFontName = "Menlo-Regular"; AXFontFamily = Menlo; AXFontSize = 11; }
```

So `extractCaretFont` returned nil everywhere and the overlay always fell back to the
caret-height heuristic — the font plumbing was dead code from the start. The unit tests
did not catch it because they mocked `.font`/`kCTFontAttributeName` attributed strings,
shapes real AX never returns.

Fixed by reading the `AXFont` dictionary first, with `AXFontExtractionTests` cases built
from the payloads actually observed (Safari's Helvetica 16, TextEdit's Menlo-Regular 11).

Chromium is a special case: its dictionary carries **only `AXFontSize`**, no name or
family. The size is the part that matters for line metrics, so an unresolvable face falls
back to the system font at the reported size rather than nil.

### Chromium returns zero-rect bounds for contenteditable and the omnibox

Brave returns a valid `AXBoundsForRange` for `<textarea>` and `<input>`, but `zero-rect`
for both the caret and the 1-char fallback in **`contenteditable`** — which is what Gmail,
Slack-web, Notion and most rich composers use. Safari and Firefox return real rects for
the same page, so this is a Chromium AX limitation, not a page-structure issue.

Consequence: in Chromium, ghost text cannot be anchored in rich composers. Context is
readable, so the suggestion is generated and then has nowhere to draw. The renderer must
treat zero-rect as "do not draw" rather than drawing at the origin.

The Chromium omnibox is also zero-rect (and Safari's address bar is a plain `AXTextField`
whose role does not contain "url", so `PolicyEngine`'s URL check does not catch it by role).

### Terminals expose a shell prompt as a text field (blocklisted)

Terminal.app reports the visible prompt line as `AXValue` with a working 1-char caret
rect. Ghostty reports the **entire 2286-character scrollback** with the caret pinned at
offset 0, so the completion context is simply wrong. Both are now in
`PolicyRules.default.blacklistedBundleIDs`, along with the other common terminals, guarded
by `PolicyEngineTests.testTerminalBundlesAreExcluded`.

### Secure-field detection holds everywhere it was tested

No safety finding. `AXSubrole == AXSecureTextField` was reported correctly for
`<input type=password>` in Safari, Brave **and** Firefox. The chat and password-manager
surfaces have not been probed yet — that check remains open.

### Firefox reports `AXUnknown` as the subrole

Firefox text fields come back as `AXTextArea:AXUnknown` / `AXTextField:AXUnknown` rather
than with an empty subrole. Harmless today because `PolicyEngine` only pattern-matches
`"url"` against the role, but any future role *allowlist* must not assume the subrole is
empty or absent.

### System-wide focus reads can fail where per-app reads succeed

`AXUIElementCreateSystemWide()` + `AXFocusedUIElement` returned
`kAXErrorAPIDisabled (-25204)` consistently for the probe process, while
`AXUIElementCreateApplication(pid)` + `AXFocusedUIElement` succeeded against the same
frontmost app. Every row above was therefore collected via the per-app path.

`AXTextContextProvider.currentContext()` uses the system-wide element **only** (and so does
`extractFocusedWindowTitle`), so under that condition it returns nil and the feature dies
silently. This was observed in a differently-trusted helper process, not in the signed app,
so it is **not** confirmed to affect shipping AutoSuggest — but the per-app fallback is a
few lines and the failure mode is total. Worth a follow-up.

### Electron apps missing from the AX unlock list (fixed)

`AXTextContextProvider.chromiumBundleMarkers` gates the `AXManualAccessibility` opt-in that
makes an Electron app's text tree readable at all. Electron apps ship whatever bundle ID the
vendor chooses, so there is no prefix pattern that catches them — each must be listed by hand.

VS Code, Antigravity, Signal and Obsidian matched no entry and therefore never got the opt-in.
Added, with `AXTextContextParsingTests.testChromiumUnlockCoversHighTrafficElectronApps` as the
regression guard. Any new Electron target needs a line in both.

Scope correction: VS Code is already in `PolicyRules.default.codingBundleIDs`, so
`PolicyEngine` blocks suggestions there regardless of the unlock — adding it changes nothing
user-visible today, and probing confirms Monaco returns zero-rect bounds anyway. The apps that
actually gain from this fix are **Signal, Obsidian and Antigravity**, which are not blocked by
policy. The fix is still correct (it keeps the marker list honest, and VS Code would become
readable if the coding-bundle block were ever lifted), but it is not the high-traffic
regression it first looked like.

## Re-running after app updates

Vendors change their AX surface on major releases. Re-run the probe and diff the Results table
when a target app ships a major version, or when a user reports ghost text silently not
appearing in one specific app — that symptom is almost always an AX read that started failing.
