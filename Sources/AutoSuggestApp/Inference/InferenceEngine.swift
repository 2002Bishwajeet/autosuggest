import Foundation

@MainActor
struct InferenceEngine {
    private let runtimes: [InferenceRuntime]
    private let logger = Logger(scope: "InferenceEngine")

    init(runtimes: [InferenceRuntime]) {
        self.runtimes = runtimes
    }

    func suggest(for context: String) async throws -> Suggestion {
        guard !runtimes.isEmpty else {
            throw InferenceError.runtimeUnavailable("No runtime configured")
        }

        var lastError: Error?
        for runtime in runtimes {
            guard runtime.isAvailable() else { continue }
            do {
                let suggestion = try await runtime.generateSuggestion(context: context)
                if !suggestion.completion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return suggestion
                }
            } catch {
                lastError = error
                logger.warn("Runtime \(runtime.name) failed: \(error.localizedDescription)")
            }
        }

        if let lastError {
            throw lastError
        }
        throw InferenceError.runtimeUnavailable("No runtime available")
    }
}
