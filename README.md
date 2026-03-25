# AutoSuggest

System-wide macOS autocomplete powered by local LLMs. Runs entirely on your machine — no cloud, no account, no telemetry by default.

## Quick Start (Local, No Internet Required)

```bash
# 1. Install Ollama
brew install ollama

# 2. Pull a small model
ollama pull qwen2.5:1.5b

# 3. Start the Ollama server
ollama serve

# 4. Build and run AutoSuggest
swift build && swift run AutoSuggestRunner
```

Grant **Accessibility** and **Input Monitoring** permissions when prompted. Start typing in any text field — suggestions appear inline. **Tab** or **Enter** to accept, **Esc** to dismiss.

## System Requirements

- macOS 13+ (Ventura or later)
- Apple Silicon recommended (Intel supported)
- Xcode or Swift toolchain (`swift-tools-version: 6.2`)
- One of: Ollama, llama.cpp, or a CoreML model

## Features

- Menu bar utility with floating inline suggestions
- Three local runtime adapters: Ollama, llama.cpp, CoreML
- Automatic runtime fallback chain
- Accept/dismiss shortcuts (Tab/Enter/Esc)
- AX/paste/typing insertion fallback chain
- Encrypted personalization with PII filtering
- Exclusion rules (by app, window title, or content regex)
- Battery-aware pause mode
- Device-aware model compatibility advisor
- Settings window with model management, exclusions, privacy controls

## Run (Xcode App Target)

Preferred path for real permission handling and daily development:

1. Generate or refresh the Xcode project:

```bash
cd macos
xcodegen generate
```

2. Open [AutoSuggestDesktop.xcodeproj](/Users/biswa/Documents/GitHub/autosuggest/macos/AutoSuggestDesktop.xcodeproj).
3. Select scheme `AutoSuggestDesktop`.
4. Run (`Cmd+R`).

This launches a real bundled `AutoSuggest.app` with a stable bundle identifier, which is the correct path for Accessibility and Input Monitoring.

## Run (SwiftPM)

From repo root:

```bash
swift build
swift run AutoSuggestRunner
```

The app runs as a menu bar utility (`AS On` / `AS Off`).

Use the SwiftPM runner only for low-friction iteration. For permission-sensitive testing, prefer the Xcode app target above.

## Runtime Adapter Configuration

Config file path:

`~/Library/Application Support/AutoSuggestApp/config.json`

`localModel` now supports runtime ordering:

```json
{
  "runtimeOrder": ["ollama", "llama.cpp", "coreml"],
  "fallbackRuntimeEnabled": true,
  "customSource": {
    "sourceType": "direct_url",
    "modelID": "custom-local-model",
    "version": "0.1.0",
    "sha256": "",
    "directURL": "",
    "huggingFace": {
      "repoID": "",
      "revision": "main",
      "filePath": "",
      "tokenKeychainAccount": "autosuggest.huggingface.token"
    }
  },
  "ollama": {
    "baseURL": "http://127.0.0.1:11434",
    "modelName": "qwen2.5:1.5b"
  },
  "llamaCpp": {
    "baseURL": "http://127.0.0.1:8080"
  },
  "onlineLLM": {
    "enabled": false,
    "rolloutStage": "post-mvp",
    "byok": {
      "selectedProvider": "openai-compatible",
      "selectedModel": "gpt-4o-mini",
      "endpointURL": null,
      "apiKeyKeychainAccount": "autosuggest.online.byok.default"
    }
  }
}
```

The engine tries adapters in `runtimeOrder` and falls through automatically on unavailable/failed runtime.

## Local Model Setup (No Existing Model Needed)

### Option 1: Ollama (Fastest)

```bash
brew install ollama
ollama serve
ollama pull qwen2.5:1.5b
```

Set in config:
- `runtimeOrder`: `["ollama", "coreml", "llama.cpp"]` (or keep default)
- `localModel.ollama.modelName`: pulled model name
- optionally `localModel.autoDownloadOnFirstRun: false` if you want to skip CoreML bootstrap download

### Option 2: llama.cpp server

Run llama.cpp server separately (example command depends on your local build/model):

```bash
llama-server -m /path/to/model.gguf --port 8080
```

Set in config:
- `runtimeOrder`: include `"llama.cpp"`
- `localModel.llamaCpp.baseURL`: `http://127.0.0.1:8080`

### Option 3: CoreML local model

You can use a local manifest + local artifact URL (`file://...`) without remote hosting:

1. Create a manifest JSON with fields from `ModelManifest`.
2. Point `localModel.manifestSourceURL` to `file:///absolute/path/to/manifest.json`.
3. Set `localModel.autoDownloadOnFirstRun: true` and run app.

The installer supports local file URLs for both manifest and model zip.

### Option 4: Settings Screen (URL / Hugging Face Download)

In the app menu:
- `Model Source Settings…`

You can configure:
- `Direct URL` download (any reachable model artifact URL)
- `Hugging Face` (`repo`, `revision`, `file path`) with optional token

On `Save & Download`, the app downloads, installs, and activates the model locally.
For Hugging Face, token is stored in keychain account from config (`customSource.huggingFace.tokenKeychainAccount`).

## Model Selection Guidance (Built In)

Open the menu item `Model Compatibility Report…` to get:
- total/available memory on this Mac
- recommended model-size ceiling for current conditions
- likely unstable size threshold
- readiness status for each configured runtime
- per-installed-model verdict (`Good`, `Borderline`, `Not Recommended`) when model size can be inferred from model name

## Run (Xcode via Package)

1. Open `Package.swift` in Xcode.
2. Select scheme `AutoSuggestRunner`.
3. Run (`Cmd+R`).

This remains useful for fast package iteration, but it is no longer the recommended path for permission testing.

The package exports a library product (`AutoSuggestApp`) and the repo now includes a native app wrapper in `macos/`.

## Permissions Required

On first run, grant:
- Accessibility
- Input Monitoring

In macOS settings:
- `System Settings > Privacy & Security > Accessibility`
- `System Settings > Privacy & Security > Input Monitoring`

If event taps or insertion don’t work:
- run the Xcode app target from `macos/AutoSuggestDesktop.xcodeproj`
- re-check both permissions for `AutoSuggest`
- fully quit and reopen the app after enabling Input Monitoring

## Tests

```bash
swift test
```

## Useful Menu Actions

- Enable/Disable autocomplete
- Model Source Settings…
- Rollback active model
- Switch to next installed model
- Export local telemetry
- Exclude frontmost app
- Add exclusion rule

## Dedicated macOS App Target

The repo now includes one:
- project spec: [project.yml](/Users/biswa/Documents/GitHub/autosuggest/macos/project.yml)
- generated Xcode project: [AutoSuggestDesktop.xcodeproj](/Users/biswa/Documents/GitHub/autosuggest/macos/AutoSuggestDesktop.xcodeproj)
- host app entry: [AutoSuggestDesktopApp.swift](/Users/biswa/Documents/GitHub/autosuggest/macos/AutoSuggestDesktop/AutoSuggestDesktopApp.swift)

Use `docs/macos-app-target-setup.md` for the workflow.

## Online Models (Post-MVP BYOK)

Online model selection is intentionally disabled during MVP.

Current behavior:
- menu entry `Online Models (BYOK) — Post-MVP` shows rollout status
- config includes BYOK placeholders (provider/model/endpoint/keychain account)
- local runtime adapters remain primary (`coreml`, `ollama`, `llama.cpp`)

Post-MVP target:
- UI for provider + model selection
- key entry and secure storage via keychain
- optional online fallback routing when enabled
