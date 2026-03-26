import Foundation

protocol InferenceRuntime {
    @MainActor
    var name: String { get }
    @MainActor
    func isAvailable() -> Bool
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
}

extension InferenceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .runtimeUnavailable(let message):
            return "Runtime unavailable: \(message)"
        case .invalidAPIKey:
            return "Invalid API key. Check your key in Settings > Online LLM."
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limited by provider. Retry after \(seconds) seconds."
            }
            return "Rate limited by provider. Please wait before retrying."
        case .networkError(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        case .providerError(let statusCode, let message):
            return "Provider error (\(statusCode)): \(message)"
        }
    }
}
