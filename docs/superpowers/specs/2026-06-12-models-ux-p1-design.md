# Models UX — P1: Runtime-aware tab + Ollama panel — Design

**Date:** 2026-06-12
**Branch:** `models-ux-p1`
**Status:** Approved design, pending implementation plan

## Problem

The Settings → Models tab is barebone and confusing. It's built around the CoreML
download flow (Configure Source → Installed models), but the **active runtime is
Ollama**, for which the tab offers nothing useful: it doesn't list installed
Ollama models, can't download or switch them, and surfaces a raw
`NSURLErrorDomain -1011` in two places. A normal developer can't tell what's
installed, how to switch models, how to download new ones, or which to pick.

## Goal

Make the Models tab **runtime-aware**: select the active runtime and see a panel
*for that runtime* that answers — what's installed · switch · download · what to
pick. P1 delivers this end-to-end for **Ollama** (the default + active runtime),
including one-click downloads with live progress. CoreML and llama.cpp keep their
current controls in P1 and get dedicated panels in P2/P3.

This is phase 1 of 3 (each its own branch/PR):
- **P1 (this spec):** runtime-aware layout + Ollama panel + error-message fixes.
- **P2:** CoreML panel (installed `.mlpackage` list, source download, OpenELM
  suggestions).
- **P3:** llama.cpp panel (server URL + status + run helper).

## Decisions (from brainstorming)

- One-click Ollama download **streams live progress in-app** (`/api/pull`).
- **Custom OpenWebUI** support = a configurable Ollama **base URL** (OpenWebUI
  exposes an Ollama-compatible API). No separate subsystem.
- Curated suggestions use the **latest, smallest** verified Ollama tags.
- The stale default model `qwen2.5:1.5b` is updated to `qwen3:1.7b`.

## Curated suggested models (verified against registry.ollama.ai)

| Model | Size | Use |
| --- | --- | --- |
| `qwen3:0.6b` | 0.52 GB | latest Qwen, smallest — fastest general autocomplete (leads the list) |
| `qwen3:1.7b` | 1.36 GB | latest Qwen, better quality, still small (new default) |
| `qwen2.5-coder:1.5b` | 0.99 GB | best small *code* model (Qwen3 has no small coder yet) |
| `llama3.2:1b` | ~1.3 GB | tiny general alternative |

Each entry: `{ name, sizeGB, blurb }`, held in a static `OllamaSuggestedModels`
list so it's trivial to edit.

## Architecture

### New unit — `OllamaModelService`

A small, isolated networking unit (no AppKit), with parsing logic that is
unit-testable via injected payloads.

```
struct OllamaModelService {
    struct InstalledModel: Equatable { let name: String; let sizeBytes: Int64 }
    struct PullProgress: Equatable { let status: String; let completed: Int64; let total: Int64
        var fraction: Double { total > 0 ? Double(completed)/Double(total) : 0 } }

    var baseURL: URL

    func isRunning() async -> Bool                       // GET /api/tags ok → true
    func listInstalled() async throws -> [InstalledModel] // GET /api/tags
    func pull(_ model: String) -> AsyncThrowingStream<PullProgress, Error> // POST /api/pull, stream NDJSON

    // pure, tested:
    static func parseTags(_ data: Data) throws -> [InstalledModel]
    static func parsePullLine(_ line: Data) -> PullProgress?  // one NDJSON object
}
```

- `pull` POSTs `{"model": name, "stream": true}` to `/api/pull` and yields a
  `PullProgress` per NDJSON line (`{"status":"pulling","completed":N,"total":M}`).
  Terminal line is `{"status":"success"}`.
- All requests use the configurable `baseURL` (default `http://127.0.0.1:11434`),
  which also covers a custom OpenWebUI Ollama endpoint.

### Redesigned `ModelsSettingsView`

Top-level: an **active-runtime picker** (Ollama / CoreML / llama.cpp). Below it,
the panel for the selected runtime. The existing **runtime *order*** controls move
into a collapsed "Fallback order" disclosure (it's the fallback chain, not the
primary control).

**Ollama panel (`OllamaModelPanel`, new file):**
1. **Endpoint** — a base-URL `TextField` (prefilled, editable) with a live
   **Running / Not running** status dot; when not running, a "Start Ollama
   (`ollama serve`)" hint and a "Recheck" button.
2. **Installed** — rows from `listInstalled()`, each with size, an **active**
   badge for the current model, and a **Use** button (switch active) for others.
3. **Suggested** — rows from `OllamaSuggestedModels`. If already installed → show
   "Installed ✓ / Use"; else a **Download** button that starts `pull` and shows an
   inline determinate **progress bar** (`fraction`, MB downloaded). On success the
   model moves to Installed and becomes active.

**CoreML / llama.cpp panels:** in P1, render the *existing* controls (source
config, installed `.mlpackage` list, runtime hints) unchanged, only shown when
that runtime is selected. Full redesign is P2/P3.

### State + plumbing

`AutoSuggestUIModel` gains:
- `@Published var ollamaInstalled: [OllamaModelService.InstalledModel]`
- `@Published var ollamaRunning: Bool`
- `@Published var ollamaPulls: [String: OllamaModelService.PullProgress]` (per-model in-flight progress)

Coordinator callbacks:
- `onSetOllamaModel(String)` — set `config.localModel.ollama.modelName`, persist,
  rebuild pipeline, refresh presentation.
- `onSetOllamaBaseURL(String)` — set `config.localModel.ollama.baseURL`, persist,
  rebuild, then refresh installed list.
- `onPullOllamaModel(String)` — run `OllamaModelService.pull` on a background
  task, publish each `PullProgress` into `ollamaPulls[model]`, and on success
  clear it, refresh `ollamaInstalled`, and **set the pulled model active** (the
  user downloaded it to use it) with a success banner.
- `onRefreshOllama()` — refresh `ollamaRunning` + `ollamaInstalled` off-main.

The coordinator refreshes Ollama state on `didBecomeActive` and when the Models
route is shown (reusing the existing off-main refresh pattern — no main-thread
networking).

### Error-message fixes (cross-cutting, P1)

Route the two remaining raw-error sites through the existing
`AppCoordinator.friendlyModelSetupMessage(for:)`:
- the **"Model retry failed"** banner (`retryModelAcquisition` catch), and
- the inline **model-source error** shown in the Models panel
  (`modelHealth.lastError`).

### Config

- Update defaults: `LocalModelConfig.ollama.modelName` and `fallbackModelName`
  `qwen2.5:1.5b` → `qwen3:1.7b`. This is a **default-value** change only (no
  schema change), so existing stored configs are untouched and **no
  `ConfigMigrationManager` step is required**. Update the one config test that
  asserts the old default.

## Error handling

- Ollama not running / unreachable → `isRunning() == false` → panel shows the
  "Start Ollama" hint, never a crash or raw error.
- `pull` failure (network, bad model name) → the row shows a short inline error
  via `friendlyModelSetupMessage`, with a Retry; other rows unaffected.
- All networking is `async` and off the main actor (consistent with the
  threading invariants established in the usability pass).

## Testing

- `OllamaModelService.parseTags` and `parsePullLine` — unit tests with real
  sample payloads (pure parsing, no whole-flow mocking).
- `OllamaSuggestedModels` — a test asserting the list is non-empty and tags are
  well-formed (`repo:tag`).
- Existing suite stays green; `swiftformat --lint` clean.
- Live Ollama pull/switch verified by running the app (Xcode MCP) — networking
  against a real/absent Ollama, per repo convention that real I/O is manual.

## Guardrails (unchanged)

`PolicyEngine`/secure-field suppression, PII filter, encrypted store, telemetry
content-free — all untouched. No new entitlements (localhost HTTP only).

## Out of scope for P1

CoreML browser redesign (P2), llama.cpp run helper (P3), and any cloud/Online-LLM
changes (that's the separate Online LLM tab).
