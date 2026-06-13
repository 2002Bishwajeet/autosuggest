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
        // The text before the caret IS the completion prompt. We intentionally do
        // NOT append a personalization hint as instruction text here — on a raw
        // completion endpoint the model echoes such instructions straight into the
        // suggestion, corrupting it. (Personalization still feeds the accept-loop
        // via PersonalizationEngine.)
        let prompt = context

        guard let url = URL(string: "\(baseURL)/api/generate") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = try JSONEncoder().encode(
            OllamaGenerateRequest(
                model: model,
                prompt: prompt,
                stream: false,
                options: OllamaOptions(numPredict: 24)
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

        let decoded = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
        let completion = decoded.response.trimmingCharacters(in: .whitespacesAndNewlines)
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

private struct OllamaGenerateRequest: Encodable {
    let model: String
    let prompt: String
    let stream: Bool
    let options: OllamaOptions
}

private struct OllamaOptions: Encodable {
    let numPredict: Int
}

private struct OllamaGenerateResponse: Decodable {
    let response: String
}
