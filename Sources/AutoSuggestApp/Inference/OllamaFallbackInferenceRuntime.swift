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
        let personalHint = await personalizationEngine.bestMatch(for: context)
        let prompt = if let personalHint, !personalHint.isEmpty {
            "\(context)\n\nPrefer continuation style similar to: \(personalHint)"
        } else {
            context
        }

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
        } catch let urlError as URLError where urlError.code == .cannotConnectToHost {
            throw InferenceError.runtimeUnavailable("Ollama is not running. Start it with: ollama serve")
        }
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
        let completion = decoded.response.trimmingCharacters(in: .whitespacesAndNewlines)
        if completion.isEmpty {
            return Suggestion(completion: "", confidence: 0)
        }
        return Suggestion(completion: completion, confidence: 0.64)
    }
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
