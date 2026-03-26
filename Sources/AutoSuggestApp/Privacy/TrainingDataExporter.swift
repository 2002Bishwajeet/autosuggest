import Foundation

enum TrainingDataError: Error, LocalizedError {
    case exportDisabled
    case fileSystemError(underlying: Error)
    case encodingError

    var errorDescription: String? {
        switch self {
        case .exportDisabled:
            return "Training data collection is disabled. Enable it in Settings > Privacy."
        case .fileSystemError(let underlying):
            return "File system error: \(underlying.localizedDescription)"
        case .encodingError:
            return "Failed to encode training data pair."
        }
    }
}

struct TrainingPair: Codable {
    let prompt: String
    let completion: String
    let timestamp: Date
}

actor TrainingDataExporter {
    private let enabled: Bool
    private let piiFilter = PIIFilter()
    private let logger = Logger(scope: "TrainingDataExporter")

    private var storageURL: URL {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("AutoSuggestApp/TrainingData/training-pairs.jsonl")
        }
        let dir = base.appendingPathComponent("AutoSuggestApp/TrainingData", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("training-pairs.jsonl")
    }

    init(enabled: Bool) {
        self.enabled = enabled
    }

    func recordTrainingPair(prompt: String, completion: String) async {
        guard enabled else { return }

        let sanitizedPrompt = piiFilter.sanitize(prompt)
        let sanitizedCompletion = piiFilter.sanitize(completion)

        let pair = TrainingPair(
            prompt: sanitizedPrompt,
            completion: sanitizedCompletion,
            timestamp: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(pair),
              let line = String(data: data, encoding: .utf8) else {
            logger.warn("Failed to encode training pair.")
            return
        }

        let url = storageURL
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                handle.seekToEndOfFile()
                handle.write(Data((line + "\n").utf8))
                handle.closeFile()
            } else {
                try (line + "\n").write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            logger.warn("Failed to write training pair: \(error.localizedDescription)")
        }
    }

    func exportAnonymized() throws -> URL {
        guard enabled else { throw TrainingDataError.exportDisabled }

        let url = storageURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TrainingDataError.fileSystemError(underlying: NSError(
                domain: "TrainingDataExporter",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "No training data file found."]
            ))
        }

        // Double-scrub PII on export
        let contents = try String(contentsOf: url, encoding: .utf8)
        let lines = contents.components(separatedBy: "\n").filter { !$0.isEmpty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        var scrubbed: [String] = []
        for line in lines {
            guard let data = line.data(using: .utf8),
                  var pair = try? decoder.decode(TrainingPair.self, from: data) else {
                continue
            }
            pair = TrainingPair(
                prompt: piiFilter.sanitize(pair.prompt),
                completion: piiFilter.sanitize(pair.completion),
                timestamp: pair.timestamp
            )
            if let encoded = try? encoder.encode(pair),
               let jsonLine = String(data: encoded, encoding: .utf8) {
                scrubbed.append(jsonLine)
            }
        }

        let exportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("autosuggest-training-export")
        try? FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        let exportURL = exportDir.appendingPathComponent("training-pairs-anonymized.jsonl")
        try scrubbed.joined(separator: "\n").write(to: exportURL, atomically: true, encoding: .utf8)

        return exportURL
    }

    func clearTrainingData() {
        let url = storageURL
        try? FileManager.default.removeItem(at: url)
        logger.info("Training data cleared.")
    }

    func pairCount() -> Int {
        let url = storageURL
        guard FileManager.default.fileExists(atPath: url.path),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return 0
        }
        return contents.components(separatedBy: "\n").filter { !$0.isEmpty }.count
    }
}
