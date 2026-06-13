import Foundation

@MainActor
struct InferenceRuntimeFactory {
    let localModelSession: LocalModelSession
    let personalizationEngine: PersonalizationEngine
    let coreMLModelAdapter: CoreMLModelAdapter

    func makeRuntimes(
        config: LocalModelConfig,
        onlineLLMConfig: OnlineLLMConfig? = nil,
        onlineAPIKey: String? = nil,
        piiFilteringEnabled: Bool = true
    ) -> [InferenceRuntime] {
        let order = config.runtimeOrder.isEmpty
            ? ["foundationmodels", "coreml", "ollama", "llama.cpp"]
            : config.runtimeOrder
        var runtimes: [InferenceRuntime] = []
        let logger = Logger(scope: "InferenceRuntimeFactory")

        for runtimeName in order {
            switch runtimeName.lowercased() {
            case "foundationmodels", "foundation-models", "applellm":
                // macOS 26 Apple Intelligence on-device LLM. Registered only when
                // the SDK is present, the OS supports it, and the user has it
                // enabled. Runtime availability (eligibility / Apple Intelligence
                // on / assets ready) is gated further at request time via
                // isAvailable(), so non-eligible users transparently fall through.
                guard config.foundationModelsEnabled else { continue }
                #if canImport(FoundationModels)
                    if #available(macOS 26.0, *) {
                        runtimes.append(
                            FoundationModelsInferenceRuntime(
                                responder: LanguageModelSessionResponder()
                            )
                        )
                    }
                #endif
            case "coreml":
                runtimes.append(
                    CoreMLInferenceRuntime(
                        session: localModelSession,
                        personalizationEngine: personalizationEngine,
                        modelAdapter: coreMLModelAdapter
                    )
                )
            case "ollama":
                if config.fallbackRuntimeEnabled, isValidBaseURL(config.ollama.baseURL, path: "/api/generate") {
                    let modelName = config.ollama.modelName.isEmpty ? config.fallbackModelName : config.ollama.modelName
                    runtimes.append(
                        OllamaFallbackInferenceRuntime(
                            baseURL: config.ollama.baseURL,
                            model: modelName,
                            personalizationEngine: personalizationEngine
                        )
                    )
                } else if config.fallbackRuntimeEnabled {
                    logger.warn("Ollama baseURL invalid or unreachable; skipping Ollama runtime.")
                }
            case "llama.cpp", "llamacpp", "llama_cpp":
                if config.fallbackRuntimeEnabled, isValidBaseURL(config.llamaCpp.baseURL, path: "/completion") {
                    runtimes.append(
                        LlamaCppInferenceRuntime(
                            baseURL: config.llamaCpp.baseURL,
                            personalizationEngine: personalizationEngine
                        )
                    )
                } else if config.fallbackRuntimeEnabled {
                    logger.warn("Llama.cpp baseURL invalid or unreachable; skipping Llama.cpp runtime.")
                }
            default:
                continue
            }
        }

        // Add online LLM runtime if enabled and API key is present
        if let onlineLLMConfig, onlineLLMConfig.enabled, let apiKey = onlineAPIKey, !apiKey.isEmpty {
            let onlineRuntime = OnlineLLMInferenceRuntime(
                provider: onlineLLMConfig.byok.provider,
                model: onlineLLMConfig.byok.selectedModel,
                endpointURL: onlineLLMConfig.byok.endpointURL,
                apiKey: apiKey,
                sanitize: Self.makeSanitizer(piiFilteringEnabled: piiFilteringEnabled)
            )
            switch onlineLLMConfig.byok.priority {
            case .primary:
                runtimes.insert(onlineRuntime, at: 0)
            case .fallback:
                runtimes.append(onlineRuntime)
            }
        }

        return runtimes
    }

    private func isValidBaseURL(_ baseURL: String, path: String) -> Bool {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let base = URL(string: trimmed),
              let full = URL(string: path, relativeTo: base) else {
            return false
        }
        return full.scheme == "http" || full.scheme == "https"
    }

    /// Returns a Sendable sanitizer closure. Extracting to a named function avoids
    /// a Swift type-checker limitation with `@Sendable` on inline ternary expressions.
    private static func makeSanitizer(piiFilteringEnabled: Bool) -> @Sendable (String) -> String {
        if piiFilteringEnabled {
            return { PIIFilter().sanitize($0) }
        }
        return { $0 }
    }
}
