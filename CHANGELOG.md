# Changelog

## v0.1.0 (Unreleased)

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
