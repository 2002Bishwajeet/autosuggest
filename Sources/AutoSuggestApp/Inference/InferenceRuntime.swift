import Foundation

protocol InferenceRuntime {
    @MainActor
    var name: String { get }
    @MainActor
    func isAvailable() async -> Bool
    @MainActor
    func generateSuggestion(context: String) async throws -> Suggestion
}

struct Suggestion {
    let completion: String
    let confidence: Double
}

enum InferenceError: Error {
    case runtimeUnavailable(String)
    case invalidAPIKey
    case rateLimited(retryAfterSeconds: Int?)
    case networkError(underlying: Error)
    case providerError(statusCode: Int, message: String)
    /// The Ollama daemon could not be reached (it is not running, or the
    /// configured base URL is wrong). Distinct from a Core ML failure so the
    /// banner can tell the user exactly what to do.
    case ollamaNotReachable
    /// Ollama is running but the configured model has not been pulled.
    case ollamaModelNotInstalled(model: String)
    /// No Core ML model is selected/installed — nothing for the Core ML runtime
    /// to load. This is NOT a load failure; it just means the user hasn't picked
    /// a Core ML model.
    case coreMLModelMissing
    /// A Core ML model is present but failed to load or run (the historical
    /// `-1011`, a tokenizer mismatch, an unexpected I/O shape, etc.). Carries the
    /// underlying error so it is never confused with "Ollama isn't running".
    case coreMLRuntimeFailure(underlying: Error)
}

extension InferenceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .runtimeUnavailable(message):
            return "Runtime unavailable: \(message)"
        case .invalidAPIKey:
            return "Invalid API key. Check your key in Settings > Online LLM."
        case let .rateLimited(retryAfter):
            if let seconds = retryAfter {
                return "Rate limited by provider. Retry after \(seconds) seconds."
            }
            return "Rate limited by provider. Please wait before retrying."
        case let .networkError(underlying):
            return "Network error: \(underlying.localizedDescription)"
        case let .providerError(statusCode, message):
            return "Provider error (\(statusCode)): \(message)"
        case .ollamaNotReachable:
            return "Ollama isn't running. Start it with `ollama serve`, then try again."
        case let .ollamaModelNotInstalled(model):
            return "Ollama is running, but the model \"\(model)\" isn't installed. "
                + "Pull it with `ollama pull \(model)` or pick another model in Settings → Models."
        case .coreMLModelMissing:
            return "No Core ML model is selected. Choose one in Settings → Models, "
                + "or use Ollama instead."
        case let .coreMLRuntimeFailure(underlying):
            return "The Core ML model failed to load: \(underlying.localizedDescription). "
                + "Try re-selecting the model in Settings → Models, or use Ollama instead."
        }
    }
}
