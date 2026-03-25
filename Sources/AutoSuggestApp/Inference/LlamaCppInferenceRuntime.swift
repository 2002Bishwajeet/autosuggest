import Foundation

struct LlamaCppInferenceRuntime: InferenceRuntime {
    let name = "llama.cpp"
    private let baseURL: String
    private let personalizationEngine: PersonalizationEngine

    init(baseURL: String, personalizationEngine: PersonalizationEngine) {
        self.baseURL = baseURL
        self.personalizationEngine = personalizationEngine
    }

    func isAvailable() -> Bool {
        if isProcessRunning("llama-server") || isProcessRunning("llama.cpp") {
            return true
        }
        return isEndpointReachable()
    }

    private func isEndpointReachable() -> Bool {
        guard let url = URL(string: "\(baseURL)/completion") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 1.0
        let resultBox = ResultBox()
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse {
                resultBox.value = (200..<500).contains(http.statusCode)
            }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 1.5)
        return resultBox.value
    }

    func generateSuggestion(context: String) async throws -> Suggestion {
        let personalHint = await personalizationEngine.bestMatch(for: context)
        let prompt = if let personalHint, !personalHint.isEmpty {
            "\(context)\n\nContinue in style: \(personalHint)"
        } else {
            context
        }

        if let direct = try await requestCompletionEndpoint(prompt: prompt) {
            return direct
        }
        if let openAICompat = try await requestOpenAICompatEndpoint(prompt: prompt) {
            return openAICompat
        }
        return Suggestion(completion: "", confidence: 0)
    }

    private func requestCompletionEndpoint(prompt: String) async throws -> Suggestion? {
        guard let url = URL(string: "\(baseURL)/completion") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            LlamaCppCompletionRequest(
                prompt: prompt,
                nPredict: 24,
                temperature: 0.2,
                stop: ["\n\n"]
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        guard (200..<300).contains(http.statusCode) else { return nil }
        let decoded = try JSONDecoder().decode(LlamaCppCompletionResponse.self, from: data)
        let text = decoded.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        return Suggestion(completion: text, confidence: 0.6)
    }

    private func requestOpenAICompatEndpoint(prompt: String) async throws -> Suggestion? {
        guard let url = URL(string: "\(baseURL)/v1/completions") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            OpenAICompatRequest(
                model: "default",
                prompt: prompt,
                maxTokens: 24,
                temperature: 0.2
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        guard (200..<300).contains(http.statusCode) else { return nil }
        let decoded = try JSONDecoder().decode(OpenAICompatResponse.self, from: data)
        let text = decoded.choices.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty { return nil }
        return Suggestion(completion: text, confidence: 0.58)
    }

    private func isProcessRunning(_ processName: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", processName]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

private struct LlamaCppCompletionRequest: Encodable {
    let prompt: String
    let nPredict: Int
    let temperature: Double
    let stop: [String]

    enum CodingKeys: String, CodingKey {
        case prompt
        case nPredict = "n_predict"
        case temperature
        case stop
    }
}

private struct LlamaCppCompletionResponse: Decodable {
    let content: String
}

private struct OpenAICompatRequest: Encodable {
    let model: String
    let prompt: String
    let maxTokens: Int
    let temperature: Double

    enum CodingKeys: String, CodingKey {
        case model
        case prompt
        case maxTokens = "max_tokens"
        case temperature
    }
}

private struct OpenAICompatResponse: Decodable {
    let choices: [OpenAICompatChoice]
}

private struct OpenAICompatChoice: Decodable {
    let text: String
}

private final class ResultBox: @unchecked Sendable {
    var value = false
}
