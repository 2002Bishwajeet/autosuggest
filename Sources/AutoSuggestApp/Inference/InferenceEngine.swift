import Foundation

@MainActor
final class InferenceEngine {
    private let runtimes: [InferenceRuntime]
    private let logger = Logger(scope: "InferenceEngine")
    private(set) var lastRuntimeErrors: [String: Error] = [:]

    init(runtimes: [InferenceRuntime]) {
        self.runtimes = runtimes
    }

    var runtimeNames: [String] {
        runtimes.map(\.name)
    }

    var availableRuntimeNames: [String] {
        runtimes.filter { $0.isAvailable() }.map(\.name)
    }

    func suggest(for context: String) async throws -> Suggestion {
        guard !runtimes.isEmpty else {
            throw InferenceError.runtimeUnavailable("No runtime configured")
        }

        lastRuntimeErrors = [:]
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
                lastRuntimeErrors[runtime.name] = error
                logger.warn("Runtime \(runtime.name) failed: \(error.localizedDescription)")
            }
        }

        if let lastError {
            throw lastError
        }
        throw InferenceError.runtimeUnavailable("No runtime available")
    }
}
