import Foundation

struct CoreMLInferenceRuntime: InferenceRuntime {
    let name = "coreml"
    private let session: LocalModelSession
    private let personalizationEngine: PersonalizationEngine
    private let resourceMonitor = SystemResourceMonitor()
    private let modelAdapter: CoreMLModelAdapter

    init(session: LocalModelSession, personalizationEngine: PersonalizationEngine, modelAdapter: CoreMLModelAdapter) {
        self.session = session
        self.personalizationEngine = personalizationEngine
        self.modelAdapter = modelAdapter
    }

    func isAvailable() -> Bool {
        resourceMonitor.hasSufficientMemoryForPrimaryRuntime()
    }

    func generateSuggestion(context: String) async throws -> Suggestion {
        let personalHint = await personalizationEngine.bestMatch(for: context)
        let startedAt = Date()

        // Ensure tokenizer is loaded (async, cached after first call)
        let modelPath: URL? = session.withLoadedModel { $0 }
        if let modelPath {
            await modelAdapter.loadTokenizerIfNeeded(modelURL: modelPath)
        }

        let result: Suggestion? = session.withLoadedModel { modelPath in
            guard let modelPath else { return nil }

            if let coreMLCompletion = try? modelAdapter.generate(
                prompt: context,
                modelURL: modelPath,
                maxNewTokens: 24
            ),
               !coreMLCompletion.isEmpty {
                return Suggestion(completion: coreMLCompletion, confidence: 0.72)
            }
            return nil
        }

        guard var result else {
            throw InferenceError.runtimeUnavailable("No usable CoreML model available")
        }
        if let personalHint, !personalHint.isEmpty, result.completion.isEmpty {
            result = Suggestion(completion: personalHint, confidence: 0.61)
        }

        let elapsed = Date().timeIntervalSince(startedAt)
        if elapsed > 0.65 {
            Logger(scope: "CoreMLInferenceRuntime").warn("CoreML suggestion took \(String(format: "%.0f", elapsed * 1000))ms (slow)")
        }
        return result
    }
}
