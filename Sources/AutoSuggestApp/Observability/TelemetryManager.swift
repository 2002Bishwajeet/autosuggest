import Foundation

actor TelemetryManager {
    private let logger = Logger(scope: "TelemetryManager")
    private let enabled: Bool

    init(enabled: Bool) {
        self.enabled = enabled
    }

    func record(event: String, payload: [String: String]) {
        guard enabled else { return }
        let line = TelemetryLine(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            event: event,
            payload: payload
        )
        do {
            try append(line: line)
        } catch {
            logger.warn("Failed telemetry write: \(error.localizedDescription)")
        }
    }

    private func append(line: TelemetryLine) throws {
        let dir = try telemetryDirectory()
        let file = dir.appendingPathComponent("events.jsonl", isDirectory: false)
        let encoder = JSONEncoder()
        let data = try encoder.encode(line)
        var output = data
        output.append(0x0A)

        if FileManager.default.fileExists(atPath: file.path) {
            let handle = try FileHandle(forWritingTo: file)
            try handle.seekToEnd()
            try handle.write(contentsOf: output)
            try handle.close()
        } else {
            try output.write(to: file, options: .atomic)
        }
    }

    func exportEvents() -> URL? {
        guard enabled else { return nil }
        let source = try? telemetryDirectory().appendingPathComponent("events.jsonl", isDirectory: false)
        guard let source, FileManager.default.fileExists(atPath: source.path) else { return nil }
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("autosuggest-telemetry-export-\(Int(Date().timeIntervalSince1970)).jsonl")
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        } catch {
            logger.warn("Telemetry export failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func telemetryDirectory() throws -> URL {
        let base = try AppDirectories.applicationSupportURL()
        let dir = base.appendingPathComponent("AutoSuggestApp/Telemetry", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}

private struct TelemetryLine: Codable {
    let timestamp: String
    let event: String
    let payload: [String: String]
}
