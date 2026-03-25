import Foundation

struct InstalledModel: Equatable {
    let id: String
    let version: String
    let path: URL
}

enum ModelManagerError: Error {
    case modelNotInstalled
    case rollbackUnavailable
}

struct ModelManager {
    private let logger = Logger(scope: "ModelManager")

    func listInstalledModels() throws -> [InstalledModel] {
        let root = try installedRoot()
        guard let items = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return []
        }

        return items.compactMap { url in
            let name = url.lastPathComponent
            let separator = name.lastIndex(of: "-")
            guard let separator else { return nil }
            let id = String(name[..<separator])
            let version = String(name[name.index(after: separator)...])
            return InstalledModel(id: id, version: version, path: url)
        }
    }

    func readActiveModelPath() throws -> URL? {
        let pointer = try modelStorageDirectory().appendingPathComponent("active_model_path.txt", isDirectory: false)
        guard let data = try? Data(contentsOf: pointer), let path = String(data: data, encoding: .utf8) else {
            return nil
        }
        let pathTrimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pathTrimmed.isEmpty else { return nil }
        let url = URL(fileURLWithPath: pathTrimmed)
        guard FileManager.default.fileExists(atPath: url.path) else {
            logger.warn("Active model path no longer exists: \(url.path); clearing pointer.")
            try? FileManager.default.removeItem(at: pointer)
            return nil
        }
        return url
    }

    func switchActiveModel(to model: InstalledModel) throws {
        let pointer = try modelStorageDirectory().appendingPathComponent("active_model_path.txt", isDirectory: false)
        let rollback = try modelStorageDirectory().appendingPathComponent("previous_model_path.txt", isDirectory: false)
        if let current = try readActiveModelPath(), let currentData = current.path.data(using: .utf8) {
            try currentData.write(to: rollback, options: .atomic)
        }
        guard let newData = model.path.path.data(using: .utf8) else { return }
        try newData.write(to: pointer, options: .atomic)
        logger.info("Switched active model to \(model.id) \(model.version)")
    }

    func rollbackActiveModel() throws {
        let pointer = try modelStorageDirectory().appendingPathComponent("active_model_path.txt", isDirectory: false)
        let rollback = try modelStorageDirectory().appendingPathComponent("previous_model_path.txt", isDirectory: false)
        guard let data = try? Data(contentsOf: rollback) else {
            throw ModelManagerError.rollbackUnavailable
        }
        try data.write(to: pointer, options: .atomic)
        logger.info("Rolled back active model.")
    }

    private func modelStorageDirectory() throws -> URL {
        let base = try AppDirectories.applicationSupportURL()
        let dir = base.appendingPathComponent("AutoSuggestApp/Models", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func installedRoot() throws -> URL {
        let root = try modelStorageDirectory().appendingPathComponent("Installed", isDirectory: true)
        if !FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        return root
    }
}
