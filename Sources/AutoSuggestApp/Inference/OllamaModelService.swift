import Foundation

/// All Ollama HTTP interactions used by the Models settings panel. Parsing is
/// pure + unit-tested; the live methods run off the main actor.
struct OllamaModelService {
    struct InstalledModel: Equatable {
        let name: String
        let sizeBytes: Int64
    }

    struct PullProgress: Equatable {
        let status: String
        let completed: Int64
        let total: Int64
        var fraction: Double {
            total > 0 ? min(1, Double(completed) / Double(total)) : 0
        }
    }

    /// e.g. "http://127.0.0.1:11434" — also an OpenWebUI Ollama-compatible URL.
    let baseURL: String

    func isRunning() async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    func listInstalled() async throws -> [InstalledModel] {
        guard let url = URL(string: "\(baseURL)/api/tags") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try Self.parseTags(data)
    }

    /// Streams one `PullProgress` per NDJSON line from `POST /api/pull`.
    func pull(_ model: String) -> AsyncThrowingStream<PullProgress, Error> {
        let base = baseURL
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = URL(string: "\(base)/api/pull") else { throw URLError(.badURL) }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(PullRequest(model: model, stream: true))
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                        throw URLError(.badServerResponse)
                    }
                    for try await line in bytes.lines {
                        if let progress = Self.parsePullLine(Data(line.utf8)) {
                            continuation.yield(progress)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func delete(_ model: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/delete") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(DeleteRequest(model: model))
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    static func parseTags(_ data: Data) throws -> [InstalledModel] {
        let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
        return decoded.models.map { InstalledModel(name: $0.name, sizeBytes: $0.size) }
    }

    static func parsePullLine(_ line: Data) -> PullProgress? {
        guard let decoded = try? JSONDecoder().decode(PullLine.self, from: line) else { return nil }
        return PullProgress(status: decoded.status, completed: decoded.completed ?? 0, total: decoded.total ?? 0)
    }

    private struct TagsResponse: Decodable { let models: [TagModel] }
    private struct TagModel: Decodable { let name: String; let size: Int64 }
    private struct PullLine: Decodable { let status: String; let total: Int64?; let completed: Int64? }
    private struct PullRequest: Encodable { let model: String; let stream: Bool }
    private struct DeleteRequest: Encodable { let model: String }
}
