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
}
