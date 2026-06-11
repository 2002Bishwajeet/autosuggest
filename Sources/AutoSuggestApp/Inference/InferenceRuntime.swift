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
        }
    }
}
