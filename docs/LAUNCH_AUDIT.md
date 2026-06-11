# AutoSuggest — Launch Readiness Audit

_Audited: 2026-06-03 · Branch: `main` · Scope: app, website, release pipeline, docs._

This is a prioritized punch-list to take AutoSuggest from "looks done" to
"super professional and shippable." It records the current state, every gap
found, and the concrete fix — ordered so the highest-impact work comes first.

**Decisions already locked (from review):**
- ✅ Apple Developer account available → we do **proper codesign + notarization**, not just a Gatekeeper workaround.
- ✅ Online-LLM (BYOK) messaging → **remove from the site** until the feature actually ships (app currently ships it disabled / post-MVP).
- ✅ This audit doc is written **before** any code changes.

---

## Verdict at a glance

| Area | State | One-line |
|------|-------|----------|
| macOS app | 🟢 Mature | MVP complete, 94 tests, remaining items are explicitly post-MVP. |
| Website design | 🟢 Strong | Real design system, good type, modular CSS, responsive. |
| Website *substance* | 🟡 Thin | No real product imagery; some copy oversells the app. |
| Release / download | 🔴 Broken | **No releases or tags exist** — every Download button dead-ends. |
| Distribution trust | 🔴 Missing | Build is unsigned/un-notarized; scary first launch for a permissions app. |

**Bottom line:** the site *looks* finished but the product isn't downloadable and
some claims don't match the shipped binary. Fix those two things and it goes from
"nice portfolio page" to "credible product."

---

## Priority matrix

Severity: **P0** = blocks launch / breaks trust · **P1** = major professionalism gap ·
**P2** = polish that separates good from great · **P3** = nice-to-have / housekeeping.

| # | P | Item | Effort | Where |
|---|---|------|--------|-------|
| 1 | P0 | No GitHub release/tag — Download buttons dead-end | M | `release.yml`, repo |
| 2 | P0 | Build is unsigned & un-notarized | M | `release.yml:33-35` |
| 3 | P0 | ✅ ~~Site oversells online-LLM (not shipped)~~ — **done** | S | `index.html` hero/features/runtimes |
| 4 | P1 | No real product screenshots or demo video | M | `website/` (fake CSS demo) |
| 5 | P1 | Designed OG/social image (current is placeholder) | S | `website/og-image.png` |
| 6 | P1 | No FAQ / privacy / security trust section | M | `index.html` |
| 7 | P1 | `install.sh` runs unsigned app; no quarantine note | S | `scripts/install.sh`, README |
| 8 | P2 | No dark mode (Mac dev-tool audience expects it) | M | `css/variables.css` |
| 9 | P2 | Google Fonts = perf + privacy leak; self-host | S | `index.html:27-29` |
| 10 | P2 | Accessibility pass on the site itself | S | `index.html`, CSS |
| 11 | P2 | `prefers-reduced-motion` not honored | S | `css/base.css`, JS |
| 12 | P2 | SEO: no canonical, JSON-LD, sitemap, robots | S | `website/` |
| 13 | P3 | Roadmap/changelog link, version sourced once | S | site + `CHANGELOG.md` |
| 14 | P3 | Repo housekeeping (uncommitted files, `.build` tracked?) | S | repo root |

---

## P0 — Must fix before any launch

### 1. There is no release. Every Download CTA dead-ends.
**Evidence:** `gh release list` → empty. `git tag` → empty. The hero "Download for
Mac" (`index.html:81`), the CTA "Download Latest Release" (`index.html:287`), and
`scripts/install.sh` all resolve to `…/releases/latest`, which currently returns
nothing. A visitor who clicks Download today gets a 404 / empty page.

**Fix:**
1. Verify a clean release build locally: `cd macos && xcodegen generate && xcodebuild …` (the same invocation as CI).
2. Push a `v0.1.0` tag → `release.yml` runs → produces `AutoSuggest.dmg` + `.zip` and a GitHub Release.
3. Confirm the DMG mounts, the app launches, and `install.sh` finds the asset end-to-end.

**Acceptance:** clicking every Download button lands on a real release with a working `.dmg`.

### 2. The build is unsigned and un-notarized.
**Evidence:** `release.yml:33-35` builds with `CODE_SIGN_IDENTITY="-"`,
`CODE_SIGNING_REQUIRED=NO`, `CODE_SIGNING_ALLOWED=NO`. A downloaded unsigned app
trips Gatekeeper ("AutoSuggest is damaged and can't be opened"). For an app that
asks for **Accessibility + Input Monitoring**, that first impression is fatal.

**Fix (Developer ID path — you have the account):**
- Add Developer ID Application signing to the release build.
- Notarize with `notarytool` and **staple** the ticket to the `.app`/`.dmg`.
- Store secrets in GitHub Actions: `DEVELOPER_ID_CERT` (base64 .p12), cert
  password, `APPLE_ID`, `APP_SPECIFIC_PASSWORD` (or App Store Connect API key),
  `TEAM_ID`.
- CI step order: build → codesign (hardened runtime, entitlements) → create DMG →
  notarize DMG → staple → publish.

**Acceptance:** a freshly downloaded DMG opens with **no** Gatekeeper warning on a
machine that never saw the build; `spctl -a -vvv AutoSuggest.app` → "accepted, source=Notarized Developer ID".

### 3. The website promises online-LLM, which the app ships disabled.
**Evidence:** README + `checklist.md` say online-LLM is **post-MVP, disabled in
config**. But the site advertises it as current: hero badge "Now with online LLM
support" (`index.html:68`); Fast feature "or online APIs" (`index.html:154`);
hero sub "or your own API key" (`index.html:77`); a full **Online LLM / BYOK**
runtime card (`index.html:233-237`).

**Fix (decision: remove for now):**
- Hero badge → drop "Now with online LLM support" (e.g. just "v0.1.0 — Local-first, private").
- Hero sub → "Powered by local LLMs. Private, fast, open source."
- Fast card → remove "or online APIs".
- Runtimes section → replace the BYOK card with CoreML (a runtime that *does* ship),
  or drop to a 2-card grid. Keep the grid balanced.
- Re-scan the whole page for any other "online/API key/BYOK" copy.

**Acceptance:** every feature claim on the page maps to something the shipped app does.

---

## P1 — Major professionalism gaps

### 4. No real product proof.
The "demo" (`index.html:97-130`) is a CSS/JS typing animation in a fake `Notes.app`
window. For a UI utility, *seeing it work in a real app* is the top conversion driver.
**Fix:** record a 5–10s screen capture of suggestions appearing inline + Tab-to-accept,
export an optimized GIF/`<video>` (muted, autoplay, loop, `playsinline`), and add
2–3 real screenshots (inline overlay, settings window, menu-bar item). Keep the
animated demo as a secondary/hero flourish if you like, but lead with reality.
**Needs from you:** the recordings (I can storyboard exact shots + sizes).

### 5. Social/OG image is a placeholder.
`og-image.png` is ~5.6 KB at 1200×630 — almost certainly auto-generated.
**Fix:** design a real 1200×630 card (logo, tagline, screenshot peek, on-brand palette).
First impression in every link unfurl (Slack/X/iMessage).

### 6. No trust section — critical for a permissions/privacy app.
There's no FAQ, no privacy explainer, no security note. People are about to grant
Accessibility + Input Monitoring; the page must pre-empt the obvious fears.
**Fix:** add a compact **FAQ** + **Privacy** block answering:
- "Is anything sent to a server?" (no — local by default)
- "Why does it need Accessibility / Input Monitoring?"
- "Is it really open source / auditable?" (link the exact source dirs)
- "Does it store what I type?" (personalization is encrypted, local, PII-filtered, opt-in)
- "How do I uninstall?" / "Which Macs are supported?"

### 7. `install.sh` installs an unsigned app with no guidance.
`scripts/install.sh` downloads, copies to `/Applications`, and `open`s the app — but
if the release is unsigned/un-notarized the user just gets a Gatekeeper block with
no explanation. Once #2 lands this is moot; until then, add an honest first-launch
note (right-click → Open, or `xattr -dr com.apple.quarantine`) to the script output,
the README, and the site.

---

## P2 — Polish that separates good from great

### 8. No dark mode.
Audience is Mac developers; many run dark system-wide. Current palette is light-only
(`css/variables.css`). **Fix:** add a `@media (prefers-color-scheme: dark)` token
override (the whole site is token-driven, so this is mostly one block). Verify
contrast, shadows, and the grain overlay in dark.

### 9. Google Fonts dependency (perf + privacy).
`index.html:27-29` pulls Instrument Serif + DM Sans + JetBrains Mono from Google.
For a privacy-branded product, calling Google on every load is off-message, and
it's render-blocking. **Fix:** self-host the woff2 subsets locally, add `font-display: swap`
and `<link rel="preload">` for the display face.

### 10. Site accessibility pass.
Audit: visible focus states on all interactive elements, `aria-expanded` on the
mobile nav toggle (`nav.js`), descriptive `alt` on every image once real ones land,
color contrast for `--text-tertiary` on light bg (currently borderline at small sizes),
and the decorative SVGs marked `aria-hidden`.

### 11. Honor `prefers-reduced-motion`.
Scroll reveals (`css/base.css`), the typing demo (`js/demo.js`), the blinking cursor,
and the pulsing badge all animate unconditionally. **Fix:** wrap in
`@media (prefers-reduced-motion: no-preference)` / bail early in JS when the user
opts out.

### 12. SEO / shareability basics.
Missing: `<link rel="canonical">`, JSON-LD `SoftwareApplication` schema, `sitemap.xml`,
`robots.txt`. Cheap, and they materially help discoverability and rich results.

---

## P3 — Housekeeping

### 13. Single-source the version + add roadmap/changelog link.
`v0.1.0` is hardcoded in the hero badge and will drift from `CHANGELOG.md`. Add a
footer link to the changelog/roadmap, and decide on one source of truth for the
displayed version.

### 14. Repo hygiene.
`git status` shows uncommitted `.claude/` and a modified `skills-lock.json`; confirm
`.build/` is fully ignored (it appears in the tree) and not tracked. Quick pass to
keep the public repo clean before it gets traffic.

---

## Recommended execution sequence

1. **Cut the release** (#1) — verify the build, tag `v0.1.0`, confirm the DMG works. _Nothing else matters until Download works._
2. **Sign + notarize** (#2) — fold Developer ID signing + notarization into `release.yml`, re-cut. Now the download is *trustworthy*, not just present.
3. **Fix the copy** (#3) — remove online-LLM claims so the page matches the binary. Fast, pure win.
4. **Product proof** (#4, #5) — screenshots/video + real OG image. Biggest perceived-quality jump.
5. **Trust section** (#6, #7) — FAQ + privacy + honest install guidance.
6. **Polish pass** (#8–#12) — dark mode, self-hosted fonts, a11y, reduced-motion, SEO.
7. **Housekeeping** (#13, #14).

Phases 1–3 are the launch gate. Phases 4–5 are what make it look like a *product*.
Phase 6 is what makes it look *expensive*.

---

## What I need from you

| Need | Why | Status |
|------|-----|--------|
| Developer ID cert + Team ID + notarization creds as GH secrets | To wire signing/notarization into CI | ⏳ you have the account; need the secrets uploaded |
| 5–10s screen recording + 2–3 screenshots of the real app | Real product proof (#4) | ⏳ I'll storyboard exact shots |
| Sign-off on removed online-LLM copy | Confirm tone of the trimmed sections (#3) | ✅ decided: remove |
| Confirm the public site URL | OG tags use `2002bishwajeet.github.io/autosuggest` | ⏳ verify Pages is live there |
