# BYOK Ship Plan — Online LLM

> Produced by spike 009. All file:line citations resolve to code on `advisor/009-byok-spike`.
> BYOK remains **disabled** (`onlineLLM.enabled = false`) until this plan is executed.

---

## 1. Gap Inventory

### 1a. Enable / Rollout Mechanics

**Current state:** `OnlineLLMConfig.enabled` defaults `false`
(`Sources/AutoSuggestApp/Config/AppConfig.swift:491`).

The settings UI exposes a `Toggle("Enable online LLM", …)` wired to
`uiModel.onUpdateOnlineLLMEnabled`
(`Sources/AutoSuggestApp/UI/Settings/OnlineLLMSettingsView.swift:11-14`).
`AppCoordinator.updateOnlineLLMEnabled` mutates the config and calls
`rebuildRuntimePipelines` — the runtime is live immediately on toggle.

**Recommendation:** Use the existing UI toggle as the enable gate; no
config-flip needed at ship time. The `rolloutStage` field is present but
nothing reads it at runtime today — it can serve as a future server-side
override but does not block the current implementation.

### 1b. Key-Entry Flow

**UI:** `OnlineLLMSettingsView` renders a `SecureField("Enter API key", …)`
that calls `uiModel.onUpdateOnlineLLMAPIKey?(newValue)` on every keystroke
(`Sources/AutoSuggestApp/UI/Settings/OnlineLLMSettingsView.swift:59-62`).

**Handler chain:**
1. `AutoSuggestUIModel.onUpdateOnlineLLMAPIKey` callback
   (`Sources/AutoSuggestApp/UI/AutoSuggestUIModel.swift:393`) is set in
   `AppCoordinator.wireUICallbacks`
   (`Sources/AutoSuggestApp/App/AppCoordinator.swift:222-224`).
2. `AppCoordinator.updateOnlineLLMAPIKey` calls
   `secretStore.upsert(account: config.onlineLLM.byok.apiKeyKeychainAccount, secret: key)`
   (`Sources/AutoSuggestApp/App/AppCoordinator.swift:969-980`).
3. `SecretStore.upsert` writes to `kSecClassGenericPassword` under service
   `com.autosuggest.app` with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
   (`Sources/AutoSuggestApp/Privacy/SecretStore.swift:29-53`). The key never
   touches disk in plaintext.
4. `rebuildRuntimePipelines` reads the key back via
   `secretStore.read(account: …)` and passes it to `makeRuntimes`
   (`Sources/AutoSuggestApp/App/AppCoordinator.swift:275-285`).

**Gap:** The `SecureField` starts blank on every app launch (local
`@State private var onlineLLMAPIKey = ""`). The stored key is never
pre-populated into the field — this is intentional security hygiene but
means the field always reads "blank". The "Leave blank to keep the current
key" caption explains this, but first-time users may not understand why their
key appears missing. **Action:** add a one-time "key is set" indicator (e.g.
a checkmark or "Key saved" label based on `secretStore.read` returning
non-nil) without revealing the key text.

### 1c. Error Surfacing

**Error mapping in `checkHTTPStatus`**
(`Sources/AutoSuggestApp/Inference/OnlineLLMInferenceRuntime.swift:165-179`):

| HTTP status | `InferenceError` thrown |
|-------------|------------------------|
| 401 | `.invalidAPIKey` |
| 429 | `.rateLimited(retryAfterSeconds:)` |
| other 4xx/5xx | `.providerError(statusCode:message:)` |

**Current surfacing:** `SuggestionOrchestrator` catches all errors from
`inferenceEngine.suggest` and calls `onError?()` then `onClearSuggestion?()`
(`Sources/AutoSuggestApp/Suggestions/SuggestionOrchestrator.swift:64-68`).
`onError` is wired to increment `metrics.suggestionErrors` only — **no banner
is shown today**.

**`showBanner` exists** on `AutoSuggestUIModel`
(`Sources/AutoSuggestApp/UI/AutoSuggestUIModel.swift:406-408`) and the
`AppBanner` / `BannerKind` types are fully defined
(`Sources/AutoSuggestApp/UI/AutoSuggestUIModel.swift:56-68`).

**Recommended hook:** In `SuggestionOrchestrator.scheduleSuggestion`, thread
the concrete `InferenceError` through `onError`. Add a typed callback
`onInferenceError: ((InferenceError) -> Void)?` and wire it in
`AppCoordinator` to call:

```swift
// .invalidAPIKey
uiModel.showBanner(kind: .error, title: "Invalid API Key",
    message: "Check your Online LLM key in Settings → Online LLM.")

// .rateLimited(let seconds)
uiModel.showBanner(kind: .warning, title: "Rate Limited",
    message: "Try again in \(seconds ?? 60)s.")

// .providerError(let code, _)
uiModel.showBanner(kind: .error, title: "Provider Error (\(code))",
    message: "The online LLM returned an error. Check your configuration.")
```

### 1d. Fallback When the Provider Fails

`InferenceEngine.suggest` iterates `runtimes` in order
(`Sources/AutoSuggestApp/Inference/InferenceEngine.swift:48-65`). When the
online runtime is `.primary` (inserted at index 0,
`Sources/AutoSuggestApp/Inference/InferenceRuntimeFactory.swift:86-87`) and it throws,
the loop continues to the next available runtime — automatic silent fallback to local
runtimes is already implemented. When online is `.fallback` (appended last, lines 88-89),
failure means no suggestion is returned. In either case `lastError` is re-thrown if all
runtimes fail, which surfaces via `onError` in `SuggestionOrchestrator`.

**No additional code needed for fallback routing.**

---

## 2. Privacy Posture

### By Design: Context Sent to Third Party

BYOK sends the user's typed context (up to the AX window) to the configured
provider endpoint. This is explicit, opt-in via the enable toggle, and scoped
to the provider the user chose.

### Consent UX (Gap)

There is no in-app consent/disclosure screen before the user enables BYOK.
**Required before ship:** show a one-time disclosure dialog (or a visible
warning label in `OnlineLLMSettingsView`) stating:
- Text you type will be sent to [provider] for completion.
- AutoSuggest does not store or log your keystrokes.
- Your API key is stored in the system keychain only.

### Log Hygiene (Confirmed Clean)

`OnlineLLMInferenceRuntime` logs nothing about context or completions
(`Sources/AutoSuggestApp/Inference/OnlineLLMInferenceRuntime.swift` — only
`logger` field declared, never called in request paths). `SuggestionOrchestrator`
logs `"Suggestion ready (\(completion.count) chars, confidence …)"` — character
count only, no content
(`Sources/AutoSuggestApp/Suggestions/SuggestionOrchestrator.swift:52`).

### PII Filtering (Now Wired — this spike)

`InferenceRuntimeFactory.makeSanitizer` passes `PIIFilter().sanitize` when
`config.privacy.piiFilteringEnabled` is true (default: true)
(`Sources/AutoSuggestApp/Inference/InferenceRuntimeFactory.swift:108-113`).
`PIIFilter` redacts email, phone, and card patterns before the context reaches
the HTTP body
(`Sources/AutoSuggestApp/Privacy/PIIFilter.swift:4-13`).

When `piiFilteringEnabled` is false (user opt-out), the identity function is
passed — raw context is sent. This is the user's explicit choice and should be
surfaced in the privacy disclosure.

---

## 3. Manual Validation Matrix

Perform against a real provider before flipping `enabled` to true in the
default config. Use a controlled API key and a sandboxed account.

| Provider | Model | Latency budget | Drill: Wrong key | Drill: Rate limit | Drill: Network off |
|----------|-------|---------------|-----------------|-------------------|--------------------|
| OpenAI-compatible | `gpt-4o-mini` | p50 < 1 s for ~60 tokens | 401 → `invalidAPIKey` error → banner "Invalid API Key" | 429 + Retry-After header → banner with seconds | URLError(.notConnectedToInternet) → silent fallback to local runtime |
| OpenRouter | `openai/gpt-4o-mini` | p50 < 1.5 s | 401 → same | 429 → same | same |
| Anthropic | `claude-3-haiku-20240307` | p50 < 1 s | 401 → same | 429 → same | same |

**Per-drill steps:**

1. **Wrong key:** Set a bad key in Settings → Online LLM. Type in any app.
   Confirm a `.error` banner appears within ~1 s; no suggestion shown.

2. **Rate limit:** Simulate by sending rapid requests or use a mock server
   returning `HTTP 429` with `Retry-After: 30`. Confirm `.warning` banner
   shows "30s"; subsequent keystrokes fall through to local runtime if primary.

3. **Network off:** Enable airplane mode. Type text. Confirm no banner
   (network error → silent local fallback), suggestion still appears from
   Ollama/llama.cpp/CoreML if a local runtime is configured.

**Endpoint validation smoke test (new, this spike):**
- Configure a custom endpoint with `http://api.example.com`. Confirm
  `runtimeUnavailable` error is thrown immediately (no network call); verify
  via logs or a debug build assertion that the URLSession was never invoked.

---

## 4. Recommended v0.x Cut

### Smallest Shippable Scope (all must be done before flipping `enabled`)

**S — Days:**
- [ ] Add "key is set" indicator to `OnlineLLMSettingsView` (read-only
  keychain probe at view appear; show a checkmark when non-nil).
- [ ] Wire `onInferenceError` typed callback in `SuggestionOrchestrator` and
  connect `showBanner` calls in `AppCoordinator` for the three error cases.
- [ ] Add one-time consent label/dialog in `OnlineLLMSettingsView` — static
  text disclosing cloud send is sufficient for v0.x.

**M — Days:**
- [ ] Automated integration test for the full banner flow: mock
  `InferenceError.invalidAPIKey` → assert `uiModel.banner?.kind == .error`.
- [ ] Manual validation matrix executed for OpenAI-compatible + Anthropic
  (two providers minimum); results noted in a PR comment.
- [ ] Flip `AppConfig.default.onlineLLM.enabled` to `false` confirmed via
  grep (it is already false; just keep it that way until the above is done).

**L — Post-v0.x:**
- [ ] Server-side rollout gate using `rolloutStage` from a remote config endpoint.
- [ ] Rate-limit back-off with jitter in `SuggestionOrchestrator`.
- [ ] Per-app routing (exclude certain bundle IDs from cloud send independent
  of the global exclusion list).

### Explicit Non-Goals for v0.x

- **Streaming:** The `"stream": false` body param is intentional; streaming
  adds overlay-update complexity not worth it for <60-token completions.
- **Per-app routing:** The global enable/disable + exclusion rules cover the
  privacy surface for v0.x.
- **Multi-key / team accounts:** Single keychain slot per provider is enough.
- **Telemetry on BYOK latency:** Telemetry is off by default; adding
  cloud-specific metrics would require a privacy review before enabling.
