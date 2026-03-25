# AutoSuggest Architecture

## Overview

Menu bar app providing system-wide autocomplete via local LLMs. ~54 Swift source files organized by concern.

## Data Flow

```
Keystroke
  -> CGEventInputMonitor
  -> TypingPipeline
  -> SuggestionOrchestrator
  -> PolicyEngine check
  -> InferenceEngine (tries runtimes in order)
  -> FloatingOverlayRenderer (show suggestion)
  -> User accepts (Tab/Enter)
  -> AXTextInsertionEngine (paste/AX/typing fallback)
  -> PersonalizationEngine records acceptance
```

## Key Protocols

### `InferenceRuntime`

- `name` -- runtime identifier
- `isAvailable()` -- checks if runtime can be used
- `generateSuggestion(context:)` -- produces a completion

Implementations: `CoreMLInferenceRuntime`, `OllamaFallbackInferenceRuntime`, `LlamaCppInferenceRuntime`

### `TextInsertionEngine`

- `insertSuggestion(_:)` -- inserts accepted text into the active field

Implementation: `AXTextInsertionEngine` (clipboard paste preferred, AX setValue fallback, CGEvent typing fallback)

### `OverlayRenderer`

- `showSuggestion(_:caretRectInScreen:)` -- displays the suggestion overlay
- `hideSuggestion()` -- hides the overlay

Implementation: `FloatingOverlayRenderer` (NSPanel)

### `TextContextProvider`

- `currentContext()` -- returns text surrounding the caret

Implementation: `AXTextContextProvider`

## Directory Structure

| Directory | Contents |
|---|---|
| `App/` | AppDelegate, AppCoordinator, StatusBarController, OnboardingManager |
| `Config/` | AppConfig, ConfigStore, ConfigMigrationManager |
| `Inference/` | InferenceEngine, InferenceRuntime protocol, runtime implementations, CoreMLModelAdapter |
| `Model/` | ModelManager, ModelDownloadManager, ModelManifestProvider, ModelManifest |
| `Input/` | CGEventInputMonitor, InputEvent, ShortcutMonitor |
| `Context/` | AXTextContextProvider, TextContext |
| `Suggestions/` | SuggestionOrchestrator, TypingPipeline, FloatingOverlayRenderer, AXTextInsertionEngine |
| `System/` | PolicyEngine, PermissionManager, BatteryMonitor, SystemResourceMonitor |
| `Privacy/` | PIIFilter, EncryptedFileStore, KeychainKeyStore |
| `Personalization/` | PersonalizationEngine |
| `Observability/` | MetricsCollector, TelemetryManager |
| `UI/` | AutoSuggestViews, OnboardingFlowView, AutoSuggestUIModel |
| `Support/` | Logger, AXHelpers, AppDirectories |

## How to Add a New Runtime

1. Create a struct conforming to `InferenceRuntime`.
2. Add a case to `InferenceRuntimeFactory.makeRuntimes()`.
3. Add the runtime name to `ConfigValidator.knownRuntimes`.
4. Add config fields if needed (e.g., `baseURL`).
