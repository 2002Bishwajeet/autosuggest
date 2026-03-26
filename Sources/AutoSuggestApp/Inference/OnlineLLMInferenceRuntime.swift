import Foundation

struct OnlineLLMInferenceRuntime: InferenceRuntime {
    let name = "online"
    private let provider: OnlineLLMProvider
    private let model: String
    private let endpointURL: String
    private let apiKey: String
    private let logger = Logger(scope: "OnlineLLMInferenceRuntime")

    private static let systemPrompt = "You are an autocomplete engine. Complete the user's text naturally. Only output the completion, nothing else."

    init(provider: OnlineLLMProvider, model: String, endpointURL: String?, apiKey: String) {
        self.provider = provider
        self.model = model.isEmpty ? provider.defaultModel : model
        self.endpointURL = (endpointURL?.isEmpty ?? true) ? provider.defaultEndpoint : endpointURL!
        self.apiKey = apiKey
    }

    func isAvailable() -> Bool {
        !apiKey.isEmpty
    }

    func generateSuggestion(context: String) async throws -> Suggestion {
        switch provider {
        case .anthropic:
            return try await requestAnthropic(context: context)
        case .openAICompatible, .openRouter, .custom:
            return try await requestOpenAICompatible(context: context)
        }
    }

    // MARK: - OpenAI-Compatible (also used for OpenRouter and Custom)

    private func requestOpenAICompatible(context: String) async throws -> Suggestion {
        let urlString = endpointURL.hasSuffix("/")
            ? "\(endpointURL)v1/chat/completions"
            : "\(endpointURL)/v1/chat/completions"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        if provider == .openRouter {
            request.setValue("https://github.com/2002bishwajeet/autosuggest", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("AutoSuggest", forHTTPHeaderField: "X-Title")
        }

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": context],
            ],
            "max_tokens": 60,
            "temperature": 0.3,
            "stream": false,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await performRequest(request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        try checkHTTPStatus(http, data: data)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let content = (message?["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if content.isEmpty {
            return Suggestion(completion: "", confidence: 0)
        }
        return Suggestion(completion: content, confidence: 0.70)
    }

    // MARK: - Anthropic

    private func requestAnthropic(context: String) async throws -> Suggestion {
        let urlString = endpointURL.hasSuffix("/")
            ? "\(endpointURL)v1/messages"
            : "\(endpointURL)/v1/messages"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 60,
            "system": Self.systemPrompt,
            "messages": [
                ["role": "user", "content": context],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await performRequest(request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        try checkHTTPStatus(http, data: data)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let contentArray = json?["content"] as? [[String: Any]]
        let text = (contentArray?.first?["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if text.isEmpty {
            return Suggestion(completion: "", confidence: 0)
        }
        return Suggestion(completion: text, confidence: 0.70)
    }

    // MARK: - Helpers

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            if error.code == .cannotConnectToHost || error.code == .notConnectedToInternet || error.code == .timedOut {
                throw InferenceError.networkError(underlying: error)
            }
            throw InferenceError.networkError(underlying: error)
        } catch {
            throw InferenceError.networkError(underlying: error)
        }
    }

    private func checkHTTPStatus(_ http: HTTPURLResponse, data: Data) throws {
        switch http.statusCode {
        case 200..<300:
            return
        case 401:
            throw InferenceError.invalidAPIKey
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw InferenceError.rateLimited(retryAfterSeconds: retryAfter)
        default:
            let body = String(data: data, encoding: .utf8) ?? "No response body"
            throw InferenceError.providerError(statusCode: http.statusCode, message: body)
        }
    }
}
