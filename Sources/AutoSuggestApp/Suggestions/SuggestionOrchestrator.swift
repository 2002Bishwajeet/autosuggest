import Foundation

struct SuggestionCandidate {
    let requestID: Int
    let completion: String
    let confidence: Double
    let sourceContext: String
    let sourceBundleID: String
    let sourceWindowTitle: String?
    let latencyMs: Double?
}

@MainActor
final class SuggestionOrchestrator {
    private let policyEngine: PolicyEngine
    private let inferenceEngine: InferenceEngine
    private let logger = Logger(scope: "SuggestionOrchestrator")
    private var pendingTask: Task<Void, Never>?
    private var latestRequestID = 0
    private let debounceNanoseconds: UInt64 = 150_000_000
    var onSuggestion: ((SuggestionCandidate) -> Void)?
    var onClearSuggestion: (() -> Void)?
    var onError: (() -> Void)?

    init(policyEngine: PolicyEngine, inferenceEngine: InferenceEngine) {
        self.policyEngine = policyEngine
        self.inferenceEngine = inferenceEngine
    }

    func scheduleSuggestion(context: String, policyContext: PolicyContext) {
        let startedAt = Date()
        latestRequestID += 1
        let requestID = latestRequestID
        pendingTask?.cancel()
        pendingTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard !Task.isCancelled else { return }
            guard requestID == latestRequestID else { return }
            guard policyEngine.shouldSuggest(in: policyContext) else {
                onClearSuggestion?()
                return
            }

            do {
                let suggestion = try await inferenceEngine.suggest(for: context)
                let completion = suggestion.completion.trimmingCharacters(in: .newlines)
                guard !completion.isEmpty else {
                    onClearSuggestion?()
                    return
                }
                guard requestID == latestRequestID else { return }
                logger.info("Suggestion ready: \(completion)")
                onSuggestion?(
                    SuggestionCandidate(
                        requestID: requestID,
                        completion: completion,
                        confidence: suggestion.confidence,
                        sourceContext: context,
                        sourceBundleID: policyContext.bundleID,
                        sourceWindowTitle: policyContext.windowTitle,
                        latencyMs: Date().timeIntervalSince(startedAt) * 1000
                    )
                )
            } catch {
                logger.warn("Suggestion failed: \(error.localizedDescription)")
                onError?()
                onClearSuggestion?()
            }
        }
    }

    func clearSuggestion() {
        pendingTask?.cancel()
        onClearSuggestion?()
    }
}
