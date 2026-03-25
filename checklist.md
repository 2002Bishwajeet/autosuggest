# AutoSuggest Build Checklist

## Decisions Locked
- [x] Core runtime path: `CoreML` primary + fallback runtime abstraction
- [x] Distribution pre-MVP: fully unsigned
- [x] First-run model source: remote manifest URL + local fallback manifest
- [x] Online LLM support: post-MVP only (disabled in config)

## Foundation (Done)
- [x] Swift package app bootstrap and menu bar shell
- [x] Config persistence in Application Support
- [x] Accessibility permission prompt wiring
- [x] Inference runtime interfaces (`InferenceRuntime`, `InferenceEngine`)
- [x] CoreML + fallback runtime implementations wired into runtime engine
- [x] Model manifest resolver (`remote manifest -> fallback`)
- [x] Model artifact download + optional checksum verification
- [x] Model zip extraction into versioned install directories
- [x] Active model pointer file update after install
- [x] Input monitoring skeleton with live CGEvent key-down tap
- [x] AX context provider baseline (focused element, role, value, caret prefix)
- [x] AX context enrichment (selection range + caret bounds + focused window title)
- [x] Suggestion pipeline skeleton (monitor -> context -> orchestrator)
- [x] Overlay renderer baseline (floating suggestion panel)
- [x] Suggestion accept/dismiss shortcut monitor (Tab/Enter/Esc)
- [x] AX insertion baseline for accepted suggestions
- [x] Insertion fallback chain (AX value -> paste -> CGEvent typing)
- [x] Smart continuation prefix reconciliation baseline
- [x] Metrics collection + menu bar status details
- [x] Telemetry local writer + export
- [x] Encrypted local storage (AES-GCM + keychain key)
- [x] Personalization baseline (acceptance memory + reranking hint)
- [x] Input method guard (suppress while IME active)
- [x] Accessibility announcement baseline (VoiceOver suggestion announcement)
- [x] Model manager (list/switch/rollback active model pointers)
- [x] User exclusion rules engine (bundle/window/content regex)
- [x] Menu action to exclude frontmost app
- [x] Interactive exclusion-rule editor (menu prompt fields)
- [x] Battery-aware behavior toggle (`always_on` vs `pause_on_low_power`)
- [x] First-launch onboarding prompt
- [x] Test target + initial tests (policy + config migration)
- [x] Inference adapter failover tests (runtime-order fallback coverage)
- [x] Library host API + runner split for dedicated Xcode app target embedding
- [x] Device-aware model compatibility advisor (recommendation + runtime readiness + installed model assessment)
- [x] Model source settings UI (direct URL + Hugging Face local download path)
- [x] PII filter tests

## In Progress
- [ ] Policy filtering hardening:
- [x] Basic app blacklist / coding app blacklist
- [x] Secure field and URL field suppression
- [x] Basic code-like text/file-title detection
- [x] User regex rules + per-app override behavior (menu-driven app rule + config rules)

## Remaining MVP Implementation
- [x] True CoreML model inference integration (model IO schema adapter + token/string decode path)
- [x] Fallback backend integration with real runtime dependency checks (Ollama runtime)
- [x] Overlay polish for edge AX cases where caret bounds are unavailable
- [x] Insertion hardening baseline for AX/paste/typing fallback
- [x] Strict undo semantics mode (paste-first strict mode configurable)
- [x] Advanced race handling (request-version gating + context-validity checks before display/accept)
- [x] Rich exclusions UI management (add/edit/remove/validate flow via interactive manager)
- [x] VoiceOver/Switch Control manual compatibility validation matrix (documented at `docs/accessibility-compatibility-matrix.md`)

## Packaging / Release (Post-MVP Items Noted)
- [ ] Notarization/signing pipeline
- [ ] Installer/updater flow
- [ ] Online LLM provider integration (BYOK request routing + key entry UI)
