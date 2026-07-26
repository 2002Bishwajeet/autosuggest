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
| `MarkerRange` | WebKit `AXSelectedTextMarkerRange` bounds, printed as dimensions. This is `extractCaretRect`'s last fallback, so it is only usable at **height > 0** — `zero-height` means no anchor. |
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

`answers (height not measured)` means the row was collected before the probe reported
marker-bounds dimensions — the call answered, but whether the rect is usable
(height > 0) was not recorded. It only matters where both `AXBoundsForRange` columns are
`zero-rect`, since that is the only case where the marker range is load-bearing.

| App / surface | Role | AXValue | Caret | Bounds (caret) | Bounds (1-char) | Marker | Font | Secure |
|---|---|---|---|---|---|---|---|---|
| **TextEdit** plain text | `AXTextArea` | len 44 | 44 | `453,92 0x13` | `447,105 7x13` | no | Menlo-Regular 11 | no |
| **Safari** textarea | `AXTextArea` | len 44 | 44 | `367,218 2x18` | `363,218 6x18` | answers (height not measured) | Helvetica 16 | no |
| **Safari** input | `AXTextField` | len 38 | 38 | `233,217 2x13` | `226,217 9x13` | answers (height not measured) | .SFNS-Regular 11 | no |
| **Safari** password | `AXTextField:AXSecureTextField` | len 16 | 16 | `156,217 2x13` | `149,217 9x13` | answers (height not measured) | .SFNS-Regular 11 | **YES** |
| **Safari** contenteditable | `AXTextArea` | len 51 | 1 | `58,222 2x18` | `47,222 13x18` | answers (height not measured) | Helvetica 16 | no |
| **Safari** address bar | `AXTextField` | len 133 | 133 | `1007,37 0x16` | `1004,53 3x16` | no | — | no |
| **Brave** textarea | `AXTextArea` | len 44 | 44 | `362,240 0x18` | `358,240 4x18` | answers (height not measured) | (size 16 only) | no |
| **Brave** input | `AXTextField` | len 38 | 38 | `253,240 0x15` | `246,240 7x15` | answers (height not measured) | (size 13.3 only) | no |
| **Brave** password | `AXTextField:AXSecureTextField` | len 16 | 16 | `117,240 0x15` | `112,240 5x15` | answers (height not measured) | (size 13.3 only) | **YES** |
| **Brave** contenteditable | `AXTextArea:AXApplicationGroup` | len 51 | 1 | **zero-rect** | **zero-rect** | **0x18 usable** | (size 16 only) | no |
| **Brave** address bar | `AXTextField` | len 133 | 133 | **zero-rect** | **zero-rect** | no | — | no |
| **Firefox** textarea | `AXTextArea:AXUnknown` | len 44 | 44 | `363,210 1x16` | `358,210 4x16` | answers (height not measured) | Helvetica 16 | no |
| **Firefox** input | `AXTextField:AXUnknown` | len 38 | 38 | `264,210 1x16` | `257,210 8x16` | answers (height not measured) | .SF NS 13 | no |
| **Firefox** password | `AXTextField:AXSecureTextField` | len 16 | 16 | `141,210 1x16` | `135,210 6x16` | answers (height not measured) | .SF NS 13 | **YES** |
| **Firefox** contenteditable | `AXTextArea:AXApplicationGroup` | len 51 | 1 | `58,216 1x16` | `47,216 12x16` | answers (height not measured) | Helvetica 16 | no |
| **VS Code** editor (Monaco) | `AXTextArea` | len 50 | 50 | **zero-rect** | **zero-rect** | answers (height not measured) | (size 12 only) | no |
| **VS Code** quick-open | `AXStaticText` | len 19 | 0 | zero-rect | FAIL | answers (height not measured) | (size 13 only) | no |
| **Antigravity** editor | `AXWebArea` | len 0 | 0 | zero-rect | FAIL | answers (height not measured) | (size 16 only) | no |
| **Notes** note body | `AXTextArea` | len 395 | 394 | `657,613 0x16` | `651,629 7x16` | no | .AppleSystemUIFont 13 | no |
| **Mail** subject | `AXTextField` | len 5 | 5 | `270,174 0x16` | `262,190 8x16` | no | .AppleSystemUIFont 13 | no |
| **Mail** compose body | `AXWebArea` | FAIL | FAIL | FAIL | FAIL | yes (bounds ok, string ok) | FAIL | no |
| **Messages** composer (empty) | `AXTextField` | FAIL | 0 | `614,766 0x16` | FAIL | no | FAIL | no |
| **WhatsApp** composer | `AXTextArea` | len 16 | 16 | `604,848 0x17` | `596,848 9x17` | no | .SFNS-Regular 13 | no |
| **Slack** composer | `AXTextArea` | len 8 | 8 | **zero-rect** | **zero-rect** | answers (height not measured) | (size 15 only) | no |
| **Discord** composer | `AXTextArea` | len 25 | 25 | **zero-rect** | **zero-rect** | answers (height not measured) | (size 16 only) | no |
| **Telegram** | — | no AX content exposed at all (see below) | | | | | | |
| **AppKit** `NSSecureTextField` | `AXTextField:AXSecureTextField` | len 20 (masked) | 20 | `488,546 0x16` | `480,562 8x16` | no | FAIL | **YES** |
| **Terminal.app** | `AXTextArea` | len 71 | 48 | zero-rect | `647,140 7x14` | no | FAIL | no |
| **Ghostty** | `AXTextArea` | len 2286 | 0 | FAIL | FAIL | no | FAIL | no |

### Not yet covered

| App | Why |
|---|---|
| Xcode | Not probed. Low value for now: it is in `codingBundleIDs`, so `PolicyEngine` blocks suggestions there regardless. |
| 1Password, Bitwarden, KeePassXC, LastPass | Blocked by bundle ID, so their subrole behaviour is untested. |
| Chrome, Edge, Arc, Signal, Obsidian, Notion | Not installed on the probe machine. |

Composer rows were collected by locating each app's text element in its AX tree and
reading it in place, rather than clicking at guessed coordinates. `AXFocusedUIElement`
alone is not enough on these apps: activating Slack, Discord, Notes or Mail resolves focus
to a list, dialog or `AXWebArea` root, and only a tree walk finds the real composer.

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

**This does not make Chromium composers unanchorable** — `extractCaretRect` has a third
fallback, `AXBoundsForTextMarkerRange`, and on the same Brave `contenteditable` it returns
`59,246 0x18`: zero *width* (a collapsed caret, expected) but a real height of 18. That is
a usable caret rect, so ghost text anchors via the marker path.

> Correction: an earlier revision of this document claimed Chromium rich composers could
> not show ghost text at all. That was wrong. It came from the probe's old `MarkerRange`
> column, which printed "bounds ok" whenever the call merely *answered*, without checking
> whether the rect had a non-zero height. The column now prints the dimensions
> (`0x18 usable` / `zero-height`) so the distinction cannot be missed again.

What *is* genuinely unanchorable is the **Chromium omnibox**: it reports no
`AXSelectedTextMarkerRange` at all, so there is no third fallback and every bounds read is
zero-rect. (Safari's address bar is a plain `AXTextField` whose role does not contain
"url", so `PolicyEngine`'s URL check does not catch it by role either.)

The Slack and Discord composers are Electron `contenteditable`s that behaved like the Brave
test page on every column measured — `AXValue` and caret offset correct, marker range
answering, both `AXBoundsForRange` reads zero-rect. Their marker-bounds *height* was not
re-measured before the apps were closed, so "usable" is inferred from the shared engine
rather than observed; re-run the probe against them to confirm.

### Telegram exposes no accessible content at all

Walking Telegram's AX tree returns 214 nodes: 189 `AXMenuItem`, 15 `AXMenu`, 6
`AXMenuBarItem`, 2 `AXMenuBar`, 1 `AXApplication` and 1 `AXWindow`. The window has **no
children** — not an empty text field, not a group, nothing. There is no text surface to
read and no caret to anchor to, so Telegram is unsupported and nothing in the app can
change that from our side.

Worth distinguishing from the Chromium case: Slack and Discord expose text we cannot
*position*; Telegram exposes no text at all.

### Mail's compose body is reachable only through the marker range

Focus in a Mail compose window resolves to an `AXWebArea` whose `AXValue` and
`AXSelectedTextRange` both fail. The WebKit `AXSelectedTextMarkerRange` family does answer
(bounds and string both resolve), which is exactly what `extractTextFromSelectedMarkerRange`
and `boundsForSelectedMarkerRange` exist for — this is the first measured confirmation that
those fallbacks carry a real app rather than being defensive dead code.

Mail's subject line is an ordinary `AXTextField` and works on the primary path.

### Terminals expose a shell prompt as a text field (blocklisted)

Terminal.app reports the visible prompt line as `AXValue` with a working 1-char caret
rect. Ghostty reports the **entire 2286-character scrollback** with the caret pinned at
offset 0, so the completion context is simply wrong. Both are now in
`PolicyRules.default.blacklistedBundleIDs`, along with the other common terminals, guarded
by `PolicyEngineTests.testTerminalBundlesAreExcluded`.

### Secure-field detection holds everywhere it was tested

No safety finding. `AXSubrole == AXSecureTextField` is reported correctly for
`<input type=password>` in Safari, Brave **and** Firefox, and for a native AppKit
`NSSecureTextField`.

The native case was measured with a purpose-built harness (`NSSecureTextField` holding a
known sentinel) rather than a real credential, so the leak question could be answered
directly instead of inferred:

- `AXValue` returns a string of the **correct length** whose characters are all the
  private-use glyph `U+F79A` — Apple's mask. The plaintext does **not** appear.
- `AXSelectedText` and `AXStringForRange` both return nil on the secure field.

So the field's **length** is observable through AX but its **contents** are not. That is an
acceptable exposure: `PolicyEngine.shouldSuggest` rejects on `isSecureField` before any
suggestion is requested, and nothing on that path logs or persists field text
(`CLAUDE.md` privacy invariant).

Still unverified: the password managers already on `blacklistedBundleIDs` (1Password,
Bitwarden, KeePassXC, LastPass) are blocked by bundle ID and were not probed, so whether
*their* fields self-report as secure is unknown — the bundle-ID block is what protects
them, not the subrole check.

### Firefox reports `AXUnknown` as the subrole

Firefox text fields come back as `AXTextArea:AXUnknown` / `AXTextField:AXUnknown` rather
than with an empty subrole. Harmless today because `PolicyEngine` only pattern-matches
`"url"` against the role, but any future role *allowlist* must not assume the subrole is
empty or absent.

### System-wide focus reads can fail where per-app reads succeed (fixed)

`AXUIElementCreateSystemWide()` + `AXFocusedUIElement` returned
`kAXErrorAPIDisabled (-25204)` consistently for the probe process, while
`AXUIElementCreateApplication(pid)` + `AXFocusedUIElement` succeeded against the same
frontmost app. Every row above was therefore collected via the per-app path.

`AXTextContextProvider.currentContext()` used the system-wide element **only** (as did
`extractFocusedWindowTitle`), so under that condition it returned nil and the feature died
silently. It now falls back to `AXUIElementCreateApplication(pid)` via
`focusedElementAndRoot(pid:)`, which returns the root alongside the element — the focused
*window* has to be read from whichever root answered.

Honest scope: this was observed in a differently-trusted helper process, **not** in the
signed app, so it is not confirmed to have affected shipping AutoSuggest. The fallback costs
no extra AX IPC on the happy path (it only runs after the system-wide read already failed)
and the failure mode is total, which is why it went in anyway.

Only the "no root answers" contract is unit-tested — the live success paths need a focused
app and cannot run in CI, per the repo's existing AX testing constraint. The probe is what
exercises them.

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
