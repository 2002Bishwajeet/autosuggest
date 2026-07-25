import Foundation

struct OllamaFallbackInferenceRuntime: InferenceRuntime {
    let name = "ollama"
    private let baseURL: String
    private let model: String
    private let personalizationEngine: PersonalizationEngine

    init(baseURL: String, model: String, personalizationEngine: PersonalizationEngine) {
        self.baseURL = baseURL
        self.model = model
        self.personalizationEngine = personalizationEngine
    }

    func isAvailable() async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 1.0
        guard let (_, response) = try? await URLSession.shared.data(for: request) else {
            return false
        }
        return response is HTTPURLResponse
    }

    func generateSuggestion(context: String) async throws -> Suggestion {
        // #31: use the chat endpoint so the instructions live in a system
        // message the model won't echo into the completion (the old raw
        // /api/generate path let instruction-tuned models chat-template the
        // bare context and "reply" to it). Low temperature + a newline stop
        // because we render exactly one deterministic inline line.
        guard let url = URL(string: "\(baseURL)/api/chat") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = try JSONEncoder().encode(
            OllamaChatRequest(
                model: model,
                messages: CompletionPrompt.chatMessages(for: context),
                stream: false,
                options: OllamaOptions(numPredict: 24, temperature: 0.15, topP: 0.9, stop: ["\n"])
            )
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError where Self.isNotReachable(urlError) {
            throw InferenceError.ollamaNotReachable
        }
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw Self.mapErrorResponse(statusCode: status, body: data, model: model)
        }

        let decoded = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        // Trim newlines only: a leading space is part of the continuation and
        // matters at the insertion point.
        let completion = decoded.message.content.trimmingCharacters(in: .newlines)
        if completion.isEmpty {
            return Suggestion(completion: "", confidence: 0)
        }
        return Suggestion(completion: completion, confidence: 0.64)
    }

    // MARK: - Error Mapping (pure, unit-tested)

    /// URLError codes that mean "the Ollama daemon could not be reached" — i.e.
    /// it isn't running, or the base URL points nowhere. A refused connection on
    /// localhost is usually `.cannotConnectToHost`, but a hung/stale daemon or a
    /// wrong host surfaces as one of the others, so they all collapse to the same
    /// friendly "Ollama isn't running" message rather than a raw URLError.
    static func isNotReachable(_ error: URLError) -> Bool {
        switch error.code {
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
             .timedOut, .notConnectedToInternet, .networkConnectionLost,
             .resourceUnavailable:
            true
        default:
            false
        }
    }

    /// Maps a non-2xx Ollama `/api/generate` response to a precise error. Ollama
    /// returns HTTP 404 with `{"error":"model \"x\" not found, try pulling it
    /// first"}` when the model isn't installed; we surface that distinctly from a
    /// generic server error so the user is told to pull the model rather than
    /// being shown an opaque -1011-style failure.
    static func mapErrorResponse(statusCode: Int, body: Data, model: String) -> InferenceError {
        let message = (try? JSONDecoder().decode(OllamaErrorResponse.self, from: body))?.error
        if let message, message.lowercased().contains("not found") || message.lowercased().contains("try pulling") {
            return .ollamaModelNotInstalled(model: model)
        }
        if statusCode == 404 {
            return .ollamaModelNotInstalled(model: model)
        }
        return .providerError(statusCode: statusCode, message: message ?? "Ollama returned an error")
    }
}

private struct OllamaErrorResponse: Decodable {
    let error: String
}

private struct OllamaChatRequest: Encodable {
    let model: String
    let messages: [CompletionPrompt.ChatMessage]
    let stream: Bool
    let options: OllamaOptions
}

private struct OllamaOptions: Encodable {
    let numPredict: Int
    let temperature: Double
    let topP: Double
    let stop: [String]

    /// Ollama expects snake_case option keys. (The old code encoded
    /// `numPredict` verbatim, so the 24-token cap was silently ignored.)
    enum CodingKeys: String, CodingKey {
        case numPredict = "num_predict"
        case temperature
        case topP = "top_p"
        case stop
    }
}

private struct OllamaChatResponse: Decodable {
    let message: CompletionPrompt.ChatMessage
}
