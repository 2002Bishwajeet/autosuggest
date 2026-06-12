import Foundation

/// Detects whether a local runtime (Ollama, llama.cpp server) is installed and
/// running. All probing is injectable so the decision logic is unit-testable;
/// `.live` runs filesystem and `pgrep` checks OFF the main thread.
struct RuntimeDetectionService {
    enum Runtime {
        case ollama
        case llamaServer

        /// Candidate binary paths checked for "installed".
        var binaryPaths: [String] {
            switch self {
            case .ollama:
                ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama", "/usr/bin/ollama"]
            case .llamaServer:
                ["/opt/homebrew/bin/llama-server", "/usr/local/bin/llama-server"]
            }
        }

        /// Process names matched by `pgrep -x` for "running".
        var processNames: [String] {
            switch self {
            case .ollama: ["ollama"]
            case .llamaServer: ["llama-server", "llama.cpp"]
            }
        }
    }

    enum Status: Equatable {
        case notInstalled
        case installedNotRunning
        case running
    }

    /// Injected: does a binary exist at this path? (`.live` uses FileManager.)
    let binaryExists: @Sendable (String) -> Bool
    /// Injected: is a process with this exact name running? (`.live` uses pgrep.)
    let processRunning: @Sendable (String) async -> Bool

    func status(for runtime: Runtime) async -> Status {
        let installed = runtime.binaryPaths.contains { binaryExists($0) }
        guard installed else { return .notInstalled }
        for name in runtime.processNames where await processRunning(name) {
            return .running
        }
        return .installedNotRunning
    }

    /// Production instance. Filesystem reads and `pgrep` both run off the main
    /// thread (`processRunning` is async; `binaryExists` is cheap stat()).
    static let live = RuntimeDetectionService(
        binaryExists: { path in FileManager.default.fileExists(atPath: path) },
        processRunning: { name in await Self.pgrep(name) }
    )

    /// Runs `/usr/bin/pgrep -x <name>` on a detached background task and never
    /// blocks the caller's thread. Returns true if the process is running.
    private static func pgrep(_ name: String) async -> Bool {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            process.arguments = ["-x", name]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit() // safe: runs on a detached utility thread
                return process.terminationStatus == 0
            } catch {
                return false
            }
        }.value
    }
}
