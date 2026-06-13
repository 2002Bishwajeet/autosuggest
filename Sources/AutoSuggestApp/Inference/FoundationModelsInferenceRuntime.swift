import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Testability seam (A4). The runtime depends only on this protocol so its
/// logic — token capping, context truncation, error→empty mapping, and the
/// availability check — can be unit-tested without the FoundationModels SDK
/// (which cannot run on CI or macOS < 26). The real conformer
/// (`LanguageModelSessionResponder`) wraps `LanguageModelSession` behind the
/// availability gate; tests inject a mock.
@MainActor
protocol FoundationModelResponding {
    /// `true` iff the on-device system language model is available right now
    /// (Apple Intelligence enabled, device eligible, assets ready).
    var isModelAvailable: Bool { get }

    /// Produce a continuation of `prompt`, capped at `maxTokens` response tokens.
    /// Throws on generation/runtime errors (guardrail refusal, context overflow,
    /// rate limiting, etc.) which the runtime maps to an empty suggestion.
    func respond(toPrompt prompt: String, maxTokens: Int) async throws -> String
}

/// FoundationModels (macOS 26 Apple Intelligence) on-device completion runtime.
///
/// This type is intentionally NOT gated behind `#if canImport(FoundationModels)`
/// — it depends only on the `FoundationModelResponding` seam, so it compiles on
/// every toolchain and is fully unit-testable via a mock. Only the concrete
/// SDK-backed responder and its construction are SDK/OS gated.
struct FoundationModelsInferenceRuntime: InferenceRuntime {
    let name = "foundationmodels"

    /// Short continuation budget; matches the CoreML runtime's 24-token budget.
    static let maxResponseTokens = 24

    /// Conservative char-based prefix budget for the prompt. The FoundationModels
    /// context window is ~4096 tokens (prompt + response); at a defensive ~4
    /// chars/token and leaving headroom for the response we cap the prompt prefix
    /// well under the window. This is a safety net on top of the pipeline's own
    /// upstream truncation.
    static let maxPromptCharacters = 6000

    private let responder: FoundationModelResponding
    private let logger = Logger(scope: "FoundationModelsInferenceRuntime")

    init(responder: FoundationModelResponding) {
        self.responder = responder
    }

    func isAvailable() async -> Bool {
        responder.isModelAvailable
    }

    func generateSuggestion(context: String) async throws -> Suggestion {
        let prompt = Self.truncatedPrompt(context)
        guard !prompt.isEmpty else {
            return Suggestion(completion: "", confidence: 0)
        }

        do {
            let completion = try await responder.respond(
                toPrompt: prompt,
                maxTokens: Self.maxResponseTokens
            )
            let trimmed = completion.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return Suggestion(completion: "", confidence: 0)
            }
            return Suggestion(completion: completion, confidence: 0.8)
        } catch {
            // Generation/runtime errors (guardrail refusal, context overflow,
            // rate limiting, etc.) → return empty so InferenceEngine falls
            // through cleanly to the next runtime. Never log content; the error
            // category alone is enough for diagnostics.
            logger.warn("FoundationModels generation failed; falling through.")
            return Suggestion(completion: "", confidence: 0)
        }
    }

    /// Keep only a safe trailing prefix of the context (the text nearest the
    /// caret is the most relevant continuation signal).
    static func truncatedPrompt(_ context: String) -> String {
        guard context.count > maxPromptCharacters else { return context }
        return String(context.suffix(maxPromptCharacters))
    }
}

#if canImport(FoundationModels)

    /// Real responder backed by `LanguageModelSession` / `SystemLanguageModel`
    /// (macOS 26 Apple Intelligence). A fresh session is created per request (v1 is
    /// stateless — avoids transcript growth; a prewarmed warm session is a deferred
    /// optimization).
    @available(macOS 26.0, *)
    @MainActor
    struct LanguageModelSessionResponder: FoundationModelResponding {
        /// Terse instructions: emit ONLY the continuation of the user's text.
        private static let instructions = """
        You complete the user's text. Output ONLY the continuation that should come \
        immediately after the provided text. Do not repeat the input, do not add \
        quotes, preamble, explanation, or formatting. If there is nothing useful to \
        add, output nothing.
        """

        var isModelAvailable: Bool {
            SystemLanguageModel.default.availability == .available
        }

        func respond(toPrompt prompt: String, maxTokens: Int) async throws -> String {
            // Fresh, stateless session per request.
            let session = LanguageModelSession(instructions: Self.instructions)
            let options = GenerationOptions(
                sampling: .greedy,
                maximumResponseTokens: maxTokens
            )
            let response = try await session.respond(to: prompt, options: options)
            return response.content
        }
    }

#endif
