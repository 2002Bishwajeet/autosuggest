import Foundation

@MainActor
final class InferenceEngine {
    private let runtimes: [InferenceRuntime]
    private let logger = Logger(scope: "InferenceEngine")
    private(set) var lastRuntimeErrors: [String: Error] = [:]

    private var availabilityCache: [String: (checkedAt: Date, available: Bool)] = [:]
    private let availabilityTTL: TimeInterval = 15

    init(runtimes: [InferenceRuntime]) {
        self.runtimes = runtimes
    }

    var runtimeNames: [String] {
        runtimes.map(\.name)
    }

    func availableRuntimeNames() async -> [String] {
        var names: [String] = []
        for runtime in runtimes where await isAvailableCached(runtime) {
            names.append(runtime.name)
        }
        return names
    }

    private func isAvailableCached(_ runtime: InferenceRuntime) async -> Bool {
        if let cached = availabilityCache[runtime.name],
           Date().timeIntervalSince(cached.checkedAt) < availabilityTTL {
            return cached.available
        }
        let available = await runtime.isAvailable()
        availabilityCache[runtime.name] = (Date(), available)
        return available
    }

    func invalidateAvailabilityCache() {
        availabilityCache.removeAll()
    }

    func suggest(for context: String) async throws -> Suggestion {
        guard !runtimes.isEmpty else {
            throw InferenceError.runtimeUnavailable("No runtime configured")
        }

        lastRuntimeErrors = [:]
        var lastError: Error?
        for runtime in runtimes {
            guard await isAvailableCached(runtime) else { continue }
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
