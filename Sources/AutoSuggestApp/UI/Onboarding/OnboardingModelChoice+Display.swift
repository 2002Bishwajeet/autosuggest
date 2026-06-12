import Foundation

extension OnboardingModelChoice {
    var displayTitle: String {
        switch self {
        case .ollama:
            "Ollama"
        case .llamaCpp:
            "llama.cpp"
        case .coreML:
            "CoreML"
        }
    }

    var systemImage: String {
        switch self {
        case .ollama:
            "shippingbox"
        case .llamaCpp:
            "server.rack"
        case .coreML:
            "cube.transparent"
        }
    }

    var setupTitle: String {
        switch self {
        case .ollama:
            "Set up Ollama"
        case .llamaCpp:
            "Set up llama.cpp"
        case .coreML:
            "Set up CoreML"
        }
    }

    func setupSummary(config: LocalModelConfig) -> String {
        switch self {
        case .ollama:
            "AutoSuggest will use \(config.ollama.modelName) from \(config.ollama.baseURL) once the Ollama service is running."
        case .llamaCpp:
            "Point AutoSuggest at a running llama.cpp server on \(config.llamaCpp.baseURL) and keep your GGUF model loaded there."
        case .coreML:
            "AutoSuggest can download the default CoreML package or use a custom local source from Settings."
        }
    }

    func setupCommands(config: LocalModelConfig) -> String {
        switch self {
        case .ollama:
            "ollama serve\nollama pull \(config.ollama.modelName)"
        case .llamaCpp:
            "llama-server -m /path/to/model.gguf --port 8080"
        case .coreML:
            "CoreML setup happens inside AutoSuggest."
        }
    }

    func isReady(
        config: LocalModelConfig,
        isCoreMLInstalled: Bool,
        ollamaRunning: Bool,
        llamaRunning: Bool
    ) -> Bool {
        switch self {
        case .ollama:
            ollamaRunning
        case .llamaCpp:
            llamaRunning
        case .coreML:
            isCoreMLInstalled || config.isModelPresent
        }
    }

    func finishSummary(config: LocalModelConfig) -> String {
        switch self {
        case .ollama:
            "Keep \(config.ollama.modelName) available in Ollama and AutoSuggest will prefer that path first."
        case .llamaCpp:
            "Keep your llama.cpp server running on \(config.llamaCpp.baseURL) when you want suggestions."
        case .coreML:
            "AutoSuggest will use the local CoreML package you downloaded or configured in Settings."
        }
    }
}
