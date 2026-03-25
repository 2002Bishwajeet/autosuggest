# Local Setup Guide

AutoSuggest runs entirely on your machine. No internet connection is required after initial setup.

## Option 1: Ollama (Recommended)

Ollama is the fastest path to working suggestions.

```bash
# Install
brew install ollama

# Start the server (runs in background)
ollama serve

# Pull a model (one-time download, ~1GB)
ollama pull qwen2.5:1.5b
```

Ollama is the default runtime. No config changes needed.

**Verify**: Run `curl http://127.0.0.1:11434/api/tags` — you should see your pulled model listed.

## Option 2: llama.cpp

If you already have a GGUF model file:

```bash
# Install llama.cpp
brew install llama.cpp

# Start the server with your model
llama-server -m /path/to/your-model.gguf --port 8080
```

AutoSuggest will try llama.cpp as the second runtime after Ollama. To make it primary, edit `~/Library/Application Support/AutoSuggestApp/config.json`:

```json
{
  "localModel": {
    "runtimeOrder": ["llama.cpp", "ollama", "coreml"],
    "llamaCpp": {
      "baseURL": "http://127.0.0.1:8080"
    }
  }
}
```

## Option 3: CoreML

For Apple Silicon Macs, CoreML runs inference without a separate server process.

1. Obtain a CoreML model (`.mlmodelc` or `.mlpackage`) and its `tokenizer.json`
2. Place both in the same directory
3. Configure in the app's Settings > Model Source Settings, or use the onboarding flow to download one

CoreML requires a `tokenizer.json` file alongside the model for proper BPE tokenization. Without it, the app falls back to byte-level tokenization which produces lower quality suggestions.

## Config File Location

```
~/Library/Application Support/AutoSuggestApp/config.json
```

The app creates this automatically on first run with sensible defaults. You can edit it directly or use the Settings window.

## Permissions

AutoSuggest needs two macOS permissions:

1. **Accessibility** — to read text context from the focused app
2. **Input Monitoring** — to detect keystrokes for triggering suggestions

Grant both in: System Settings > Privacy & Security

After enabling Input Monitoring, fully quit and reopen AutoSuggest for it to take effect.

## Offline Operation

Once your chosen runtime is set up:
- Ollama: runs locally, no network needed
- llama.cpp: runs locally, no network needed
- CoreML: runs locally, no network needed

The app will attempt to fetch a remote model manifest on startup but gracefully falls back to the built-in manifest if the network is unavailable. No features are degraded in offline mode.
