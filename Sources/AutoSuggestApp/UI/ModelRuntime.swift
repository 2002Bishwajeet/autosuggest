import Foundation

/// Typed identity for a local inference runtime. Replaces stringly-typed
/// dispatch on config runtime IDs (`"ollama"` / `"llama.cpp"` / `"llamacpp"` / …).
enum ModelRuntime: String, CaseIterable, Identifiable {
    case foundationModels
    case coreML
    case ollama
    case llamaCpp

    var id: String {
        rawValue
    }

    /// Maps a config runtime string (any tolerated spelling) to a case.
    init?(configValue: String) {
        switch configValue.lowercased() {
        case "foundationmodels", "foundation models":
            self = .foundationModels
        case "coreml", "core ml", "core_ml":
            self = .coreML
        case "ollama":
            self = .ollama
        case "llama.cpp", "llamacpp", "llama_cpp", "llamaserver":
            self = .llamaCpp
        default:
            return nil
        }
    }

    var displayName: String {
        switch self {
        case .foundationModels: "Foundation Models"
        case .coreML: "Core ML"
        case .ollama: "Ollama"
        case .llamaCpp: "llama.cpp"
        }
    }
}
