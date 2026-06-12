# AutoSuggest Usability Pass — Design

**Date:** 2026-06-12
**Branch:** `usability-pass`
**Status:** Approved design, pending implementation plan

## Problem

A developer who installs the signed `.app` from the DMG release experiences the
app as unusable:

1. The menu-bar icon looks "wrong."
2. Installation feels "not on par."
3. Permission checking is "broken."
4. Switching settings tabs "looks like the app hanged."

Investigation against the shipped `.app` (not the dev `swift run` build) found
that three of these four complaints share two underlying causes: **synchronous
work on the main thread**, and a **permission flow that is neither reactive nor
self-healing**. The icon and install problems are largely symptoms that resolve
once those two foundations are fixed.

## Confirmed root causes

| Symptom | Root cause | Evidence |
| --- | --- | --- |
| Tab switch / general "hang" | `AppCoordinator.refreshUIState()` performs **synchronous filesystem I/O on the `@MainActor` every 1 second** | `AppCoordinator.swift:286` poll loop → `refreshUIState()` at `:283/:291` |
| Onboarding freeze on appear | `detectOllama()` / `isProcessRunning()` run `Process()` + `waitUntilExit()` **synchronously on the main thread**, fired from `.onAppear` and during render | `OnboardingFlowView.swift:843`, `:935`, `.onAppear` at `:822` |
| Permissions "broken" (stale state) | No reactive refresh when returning from System Settings; poll-only, no `applicationDidBecomeActive` | `PermissionManager.swift`; no `didBecomeActive` observer in `AppDelegate` |
| Permissions "broken" (silently dead) | Granting Input Monitoring after launch never rebuilds the CGEvent tap; UI flips to "Granted" but nothing works until manual relaunch, with no prompt | `CGEventInputMonitor.swift:13` `start()` early-returns and is never re-called |
| Icon "wrong" | Ghost glyph only shows when `permissionHealth.isReady && config.enabled`; with permissions stuck, the user sees the `exclamationmark.shield` warning glyph instead. Brand amber is never applied to the menu-bar tint. | `StatusBarController.swift:37-48`, `:56-65` |
| Install "not on par" | `install.sh` works, but the app does nothing visible post-install until permissions are granted — and that flow is the broken one above | `scripts/install.sh` |

## Goals

A normal developer installs the `.app`, is guided through permissions that
**actually work and update live**, and the app **never freezes**. All four
complaints resolved at their root.

## Non-goals / guardrails (must not break)

- **Secure-field suppression / `PolicyEngine` stays untouched.** This is the
  password-safety boundary; the refactor must not go near it.
- **Privacy invariants** (no raw typed text or completions logged/persisted;
  encrypted personalization store; telemetry off by default and content-free)
  unchanged.
- **Config migrations**: any user-facing config schema change gets a
  `ConfigMigrationManager` step. None expected in this work.
- Keep all 158 tests green; UI file decomposition is mechanical and
  behavior-preserving. `swiftformat Sources Tests --lint` must report 0 files.

## Design

### 1. Threading — de-block the main thread (foundation)

The single biggest cause of the perceived "hang."

- **`AppCoordinator.refreshUIState()`** splits into a fast main-thread *publish*
  and a background *gather*. All filesystem reads (model presence, diagnostics
  paths, etc.) move into an `async` gather that runs off the main actor; only the
  resulting value-type snapshot is published on `@MainActor`. The 1-second loop
  awaits the background snapshot instead of doing disk I/O on main.
- **Cadence**: model-presence and diagnostics do not need a 1-second poll. They
  are re-checked on focus (`didBecomeActive`) and on config change. A lightweight
  metrics tick may remain, but nothing synchronous on the main thread.
- **`RuntimeDetectionService` (new)**: extracts the subprocess/runtime detection
  (`detectOllama`, `isProcessRunning`, binary-path probes) into a service that
  runs `Process`/`pgrep` on a background executor and publishes results to
  `@Published` state. **No `waitUntilExit()` ever on the main thread.** Results
  are debounced and cached so view re-renders never re-spawn processes. Used by
  both onboarding and settings.

### 2. Permissions — reactive + self-healing

The core of "it's broken."

- **Reactive refresh**: observe `NSApplication.didBecomeActiveNotification` and
  immediately re-check Accessibility + Input Monitoring. Returning from System
  Settings updates the UI instantly. The existing "Recheck" button becomes a
  fallback, not the only path.
- **Self-healing event tap**: on a denied→granted transition for Input
  Monitoring, call the input monitor's `start()` again to install the tap **live
  in the same process** (the current "must relaunch" belief is an artifact of
  only ever checking once at startup). After re-arming, verify the tap is
  actually enabled/receiving.
- **Honest fallback**: if live re-arming genuinely fails verification, show a
  clear single-action **"Relaunch to finish enabling AutoSuggest"** banner —
  never silently do nothing. (Decision: live re-arm is the default; relaunch is
  the verified fallback only.)
- Accessibility (`AXIsProcessTrusted()`) updates live within the process once
  granted, so it needs only the reactive refresh.

### 3. Menu-bar icon — keep the ghost, fix the states

- Fixing §2 makes the correct ghost appear (the user is currently seeing the
  warning glyph because permission state is stuck).
- Ensure the ghost PNG is a clean **template** image (pure alpha, proper 16px
  inset) so it renders crisp rather than as a muddy blob. Apply brand amber via
  `contentTintColor` in the active state, staying within macOS menu-bar
  conventions.
- Three legible states, now driven by *accurate* state:
  - **active** — amber ghost
  - **paused** — `pause.circle`
  - **needs-permission** — `exclamationmark.shield`
  - each with a clear, distinct tooltip.

### 4. Reworked guided first-run wizard

- Live permission state: the wizard reflects grants **as they happen** (driven by
  §1/§2) — no stale steps, no surprise relaunch.
- Async model detection via `RuntimeDetectionService` — the wizard never freezes
  on appear.
- Honest relaunch handling only when actually required, with a one-click action.

### 5. Settings / onboarding refactor (decompose the ~930-line files)

Because we are heavily editing these files, we split them along existing seams.
Pure mechanical extraction, no logic change.

- `AutoSuggestViews.swift` → `SettingsRootView` + one file per route
  (`GeneralSettingsView`, `ModelsSettingsView`, `OnlineLLMSettingsView`,
  `PermissionsSettingsView`, `ExclusionsSettingsView`, `AccessibilitySettingsView`,
  `DiagnosticsSettingsView`) + shared components + `StatusPopoverView`.
- `OnboardingFlowView.swift` → one file per step (`WelcomeStepView`,
  `PermissionsStepView`, `ModelStepView`, `FinishStepView`) + the extracted
  `RuntimeDetectionService`.

### 6. Install polish

- Tighten `scripts/install.sh` messaging and confirm the DMG offers
  drag-to-Applications ergonomics.
- Verify the release is actually notarized/valid (flagged as uncertain in earlier
  sessions) so Gatekeeper opens it cleanly.
- Most of "feels on par" is delivered by §2/§4 — the app now does something
  coherent immediately after install.

## Testing

- `RuntimeDetectionService` and the permission state machine get unit tests
  (async detection mocked; AX/CGEvent exercised via `IntegrationTestHarness`
  mocks, per repo CI constraints).
- Characterization tests around the de-blocked `refreshUIState` snapshot.
- View decomposition verified green against the existing 158-test suite plus
  `swiftformat Sources Tests --lint`.

## Phasing (for the implementation plan)

1. Threading de-block + `RuntimeDetectionService`.
2. Permission reactivity + self-healing tap.
3. Icon states.
4. Onboarding wizard rework.
5. View-file decomposition.
6. Install polish.

Each phase is independently shippable and leaves tests green.
