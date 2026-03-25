import Foundation

@MainActor
final class LocalModelSession {
    private let logger = Logger(scope: "LocalModelSession")
    private let modelManager = ModelManager()
    private var loadedModelPath: URL?
    private var lastAccessed = Date.distantPast
    private let idleUnloadSeconds: TimeInterval = 120

    func withLoadedModel<T>(_ work: (URL?) -> T) -> T {
        if Date().timeIntervalSince(lastAccessed) > idleUnloadSeconds {
            unloadModel()
        }
        if loadedModelPath == nil {
            loadedModelPath = try? modelManager.readActiveModelPath()
            if let loadedModelPath {
                logger.info("Loaded model session from \(loadedModelPath.path)")
            }
        }
        lastAccessed = Date()
        return work(loadedModelPath)
    }

    func invalidate() {
        loadedModelPath = nil
        lastAccessed = Date.distantPast
    }

    private func unloadModel() {
        guard loadedModelPath != nil else { return }
        loadedModelPath = nil
        logger.info("Model session unloaded after idle timeout.")
    }
}
