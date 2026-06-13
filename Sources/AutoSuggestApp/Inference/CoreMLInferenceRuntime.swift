import Foundation

/// The subset of `LocalModelSession` the Core ML runtime needs: resolve the
/// currently-active model path (or `nil` if none is selected). A protocol so the
/// runtime's error mapping can be exercised without touching disk.
@MainActor
protocol CoreMLModelPathProviding {
    func withLoadedModel<T>(_ work: (URL?) -> T) -> T
}

/// The subset of `CoreMLModelAdapter` the runtime needs. A protocol so a missing
/// vs failing model can be tested without loading a real `MLModel`.
@MainActor
protocol CoreMLModelGenerating {
    func loadTokenizerIfNeeded(modelURL: URL, explicitTokenizerURL: URL?) async
    func generate(prompt: String, modelURL: URL, maxNewTokens: Int) throws -> String?
}

extension LocalModelSession: CoreMLModelPathProviding {}

extension CoreMLModelAdapter: CoreMLModelGenerating {}

struct CoreMLInferenceRuntime: InferenceRuntime {
    let name = "coreml"
    private let session: CoreMLModelPathProviding
    private let personalizationEngine: PersonalizationEngine
    private let resourceMonitor = SystemResourceMonitor()
    private let modelAdapter: CoreMLModelGenerating

    init(
        session: CoreMLModelPathProviding,
        personalizationEngine: PersonalizationEngine,
        modelAdapter: CoreMLModelGenerating
    ) {
        self.session = session
        self.personalizationEngine = personalizationEngine
        self.modelAdapter = modelAdapter
    }

    func isAvailable() async -> Bool {
        resourceMonitor.hasSufficientMemoryForPrimaryRuntime()
    }

    func generateSuggestion(context: String) async throws -> Suggestion {
        let logger = Logger(scope: "CoreMLInferenceRuntime")
        let personalHint = await personalizationEngine.bestMatch(for: context)
        let startedAt = Date()

        // No active Core ML model means there is nothing to load. This is a
        // distinct, accurate state — NOT a load failure and NOT "Ollama isn't
        // running" — so the banner can tell the user to pick a model.
        let modelPath: URL? = session.withLoadedModel { $0 }
        guard let modelPath else {
            throw InferenceError.coreMLModelMissing
        }

        // Ensure tokenizer is loaded (async, cached after first call)
        await modelAdapter.loadTokenizerIfNeeded(modelURL: modelPath, explicitTokenizerURL: nil)

        // A model IS present, so a failure here is a genuine Core ML runtime
        // failure (the historical -1011, a tokenizer/shape mismatch, etc.). We do
        // NOT swallow it with `try?`: it is surfaced as `.coreMLRuntimeFailure`
        // carrying the underlying error so it is never mislabeled as a generic
        // setup error or confused with an unreachable Ollama daemon.
        let completion: String?
        do {
            completion = try modelAdapter.generate(
                prompt: context,
                modelURL: modelPath,
                maxNewTokens: 24
            )
        } catch {
            logger.warn("CoreML inference failed: \(error.localizedDescription)")
            throw InferenceError.coreMLRuntimeFailure(underlying: error)
        }

        var result: Suggestion
        if let completion, !completion.isEmpty {
            result = Suggestion(completion: completion, confidence: 0.72)
        } else if let personalHint, !personalHint.isEmpty {
            // The model loaded and ran but produced nothing usable; fall back to a
            // personalization match rather than reporting a failure.
            result = Suggestion(completion: personalHint, confidence: 0.61)
        } else {
            return Suggestion(completion: "", confidence: 0)
        }

        let elapsed = Date().timeIntervalSince(startedAt)
        if elapsed > 0.65 {
            logger.warn("CoreML suggestion took \(String(format: "%.0f", elapsed * 1000))ms (slow)")
        }
        return result
    }
}
