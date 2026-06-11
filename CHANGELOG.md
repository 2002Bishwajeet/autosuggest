# Changelog

## Unreleased

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
