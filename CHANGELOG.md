# Changelog

## v0.3.0 — 2026-06-12

Real model management and an autocomplete experience that actually feels instant.

### Added
- Runtime-aware **Models** tab with a full **Ollama** panel: live running status,
  installed models with one-click switch, curated suggestions with one-click
  **download** (live `/api/pull` progress), **delete** (non-active models), and a
  configurable base URL (works with a custom OpenWebUI endpoint)
- Suggestions now render as **inline ghost text at the caret** instead of a
  detached floating box

### Changed
- Default model is the fast, non-thinking **`qwen2.5-coder:1.5b`** — Qwen3 is a
  reasoning model (~5 s latency, unfit for inline autocomplete); added `gemma3:1b`
- **About** window uses the real app icon + clickable GitHub/Report-issue links
  (was a placeholder glyph and a dead URL)
- Cleaner Suggestions toggle in the menu-bar panel

### Fixed
- Model-setup / download failures show actionable guidance instead of a raw
  `NSURLErrorDomain -1011` (including in the Diagnostics tab)
- The completion prompt no longer appends a personalization hint that the model
  echoed into the suggestion

## v0.2.0 — 2026-06-12

Usability pass: the app feels responsive and trustworthy from first launch.

### Fixed
- Permissions update live — granting Accessibility / Input Monitoring is picked
  up the moment you return to the app, with an honest "relaunch to finish"
  prompt only when the event tap genuinely can't arm in-process (no more silent
  "granted but nothing works")
- Menu-bar ghost and app icon now render — the committed Xcode project was
  missing the asset-catalog wiring, so local/Xcode builds shipped no icons
- Settings tab switching and first-run no longer freeze — all filesystem and
  subprocess work moved off the main thread
- Model-setup failures show actionable guidance instead of a raw
  `NSURLErrorDomain -1011`; the default model manifest now points at a real,
  reachable model

### Changed
- Reworked first-run wizard reflects permission grants live (no fixed polling)
- Softer brand-amber sidebar selection (was the harsh system accent)
- Trimmed the menu-bar popover to essentials so it never needs to scroll
- Decomposed the two ~930-line settings/onboarding view files into focused
  per-view files (behavior-preserving); test suite 158 → 176

## v0.1.0 — 2026-06-11

Pre-launch hardening ahead of the first signed public release.

### Added
- Signed & notarized release pipeline (Developer ID + `notarytool` staple) so
  downloads open without Gatekeeper warnings
- Trust & Privacy FAQ on the website; self-hosted fonts (no third-party
  requests), dark mode, reduced-motion support, and an accessibility pass
- `CLAUDE.md`, SwiftFormat config, CI lint + build caching
- Characterization + integration tests for the insertion, context, clipboard,
  availability-cache, and secure-input paths (119 → 158 tests)

### Changed
- Runtime availability checks are async and cached — no more `pgrep`/semaphore
  stalls on the keystroke path, and the accept path no longer blocks the event
  tap

### Fixed
- User-typed text and completions no longer leak into the macOS system log or
  local telemetry
- Accepting a suggestion preserves the full clipboard (images, files, rich
  text) instead of destroying non-string contents
- Suggestions are suppressed under macOS secure input mode and in password
  managers; keychain items pinned to a non-migratable accessibility class
- Overlay legibility + a hide/show animation race; runtime-down state now shows
  an actionable remedy

## v0.1.0 (2026-03-26)

Initial open-source release.

### Added
- System-wide autocomplete via local LLMs (Ollama, llama.cpp, CoreML)
- Menu bar utility with floating inline suggestion overlay
- Accept (Tab/Enter) and dismiss (Esc) keyboard shortcuts
- Text insertion via clipboard paste, AX setValue, and CGEvent typing fallback chain
- Automatic runtime fallback: tries each configured runtime in order
- BPE tokenizer support for CoreML via swift-transformers
- Onboarding wizard with permission setup and runtime selection
- Settings window: model management, exclusion rules, privacy, telemetry
- Device-aware model compatibility advisor
- Encrypted personalization store with PII filtering
- Configurable exclusion rules (by app, window title, content regex)
- Battery-aware pause mode
- Config versioning with forward-compatible migration (v0 -> v1)
- Config validation (runtimes, URLs, regex patterns)
- Clipboard backup/restore safety for paste-based insertion
- 94 unit tests across 17 test files
- GPL v3 license

### Fixed
- Replaced all force casts with safe AXHelpers utilities
- Replaced all force unwraps with AppDirectories safe accessors
- Clipboard race condition during paste-based text insertion
