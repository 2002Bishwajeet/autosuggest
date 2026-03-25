import CryptoKit
import Foundation

enum ModelDownloadError: Error {
    case checksumMismatch(expected: String, actual: String)
    case missingTrustedSignatureKey(String)
    case invalidSignatureEncoding
    case signatureVerificationFailed
    case extractionFailed(exitCode: Int32)
    case invalidActiveModelPathEncoding
}

struct CustomModelDownloadRequest {
    let modelID: String
    let version: String
    let downloadURL: URL
    let sha256: String
    let additionalHeaders: [String: String]
}

struct ModelDownloadManager {
    private let logger = Logger(scope: "ModelDownloadManager")
    private let trustedPublicKeysByID: [String: String] = [
        // Ed25519 32-byte public key in base64.
        "dev-ed25519-v1": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
    ]

    func downloadIfNeeded(manifest: ModelManifest) async throws {
        try await download(manifest: manifest, additionalHeaders: [:])
    }

    func downloadCustomModel(_ request: CustomModelDownloadRequest) async throws {
        let fallbackName = "\(request.modelID)-\(request.version).zip"
        let fileName = inferredFileName(from: request.downloadURL, fallback: fallbackName)
        let manifest = ModelManifest(
            modelID: request.modelID,
            version: request.version,
            fileName: fileName,
            downloadURL: request.downloadURL,
            sha256: request.sha256,
            signatureKeyID: nil,
            signatureEd25519Base64: nil,
            huggingFaceFolder: nil
        )
        try await download(manifest: manifest, additionalHeaders: request.additionalHeaders)
    }

    private func download(manifest: ModelManifest, additionalHeaders: [String: String]) async throws {
        if let hf = manifest.huggingFaceFolder {
            let installPath = try await downloadFromHuggingFaceFolder(
                repo: hf.repo,
                revision: hf.revision,
                folderPath: hf.folderPath,
                modelID: manifest.modelID,
                version: manifest.version
            )
            try setActiveInstalledModel(path: installPath)
            logger.info("Model downloaded from Hugging Face to \(installPath.path)")
            return
        }

        let modelPath = try modelStorageDirectory().appendingPathComponent(manifest.fileName, isDirectory: false)
        if FileManager.default.fileExists(atPath: modelPath.path) {
            if try validateArtifactIntegrity(fileURL: modelPath, manifest: manifest) {
                logger.info("Model already present at \(modelPath.path)")
                let installPath = try unpackArchiveIfNeeded(modelArchivePath: modelPath, manifest: manifest)
                try setActiveInstalledModel(path: installPath)
                return
            }
            try FileManager.default.removeItem(at: modelPath)
            logger.warn("Existing model failed checksum and was removed.")
        }

        if manifest.downloadURL.isFileURL {
            try FileManager.default.copyItem(at: manifest.downloadURL, to: modelPath)
        } else {
            var request = URLRequest(url: manifest.downloadURL)
            for (header, value) in additionalHeaders {
                request.setValue(value, forHTTPHeaderField: header)
            }

            let (tempURL, response) = try await URLSession.shared.download(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            try FileManager.default.moveItem(at: tempURL, to: modelPath)
        }

        _ = try validateArtifactIntegrity(fileURL: modelPath, manifest: manifest)
        let installPath = try unpackArchiveIfNeeded(modelArchivePath: modelPath, manifest: manifest)
        try setActiveInstalledModel(path: installPath)
        logger.info("Model downloaded to \(modelPath.path)")
    }

    private func downloadFromHuggingFaceFolder(
        repo: String,
        revision: String,
        folderPath: String,
        modelID: String,
        version: String
    ) async throws -> URL {
        let installDir = try modelStorageDirectory()
            .appendingPathComponent("Installed", isDirectory: true)
            .appendingPathComponent("\(modelID)-\(version)", isDirectory: true)
        if FileManager.default.fileExists(atPath: installDir.path) {
            logger.info("Hugging Face model already present at \(installDir.path)")
            return installDir
        }
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)
        let filePaths = try await listHuggingFaceFolderRecursive(repo: repo, revision: revision, folderPath: folderPath)
        for filePath in filePaths {
            guard let url = URL(string: "https://huggingface.co/\(repo.replacingOccurrences(of: " ", with: ""))/resolve/\(revision)/\(filePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filePath)") else { continue }
            let request = URLRequest(url: url)
            let (tempURL, response) = try await URLSession.shared.download(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let dest = installDir.appendingPathComponent(filePath, isDirectory: false)
            let destDir = dest.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: destDir.path) {
                try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            }
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: tempURL, to: dest)
            logger.info("Downloaded \(filePath)")
        }
        return installDir
    }

    private func listHuggingFaceFolderRecursive(repo: String, revision: String, folderPath: String) async throws -> [String] {
        var results: [String] = []
        let encoded = repo.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repo
        let revEncoded = revision.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? revision
        let pathEncoded = folderPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? folderPath
        guard let treeURL = URL(string: "https://huggingface.co/api/models/\(encoded)/tree/\(revEncoded)/\(pathEncoded)") else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: treeURL)
        let items = try JSONDecoder().decode([HuggingFaceTreeItem].self, from: data)
        for item in items {
            let fullPath = item.path
            if item.type == "file" {
                results.append(fullPath)
            } else if item.type == "directory" {
                let subPaths = try await listHuggingFaceFolderRecursive(repo: repo, revision: revision, folderPath: fullPath)
                results.append(contentsOf: subPaths)
            }
        }
        return results
    }

    private func validateArtifactIntegrity(fileURL: URL, manifest: ModelManifest) throws -> Bool {
        _ = try validateChecksumIfPresent(fileURL: fileURL, manifest: manifest)
        _ = try validateSignatureIfPresent(fileURL: fileURL, manifest: manifest)
        return true
    }

    private func validateChecksumIfPresent(fileURL: URL, manifest: ModelManifest) throws -> Bool {
        let expected = manifest.sha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !expected.isEmpty, !expected.hasPrefix("replace_") else {
            logger.warn("Model checksum not configured; skipping verification.")
            return true
        }

        let data = try Data(contentsOf: fileURL)
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == expected else {
            throw ModelDownloadError.checksumMismatch(expected: expected, actual: actual)
        }
        return true
    }

    private func validateSignatureIfPresent(fileURL: URL, manifest: ModelManifest) throws -> Bool {
        guard let keyID = manifest.signatureKeyID,
              let signatureBase64 = manifest.signatureEd25519Base64,
              !keyID.isEmpty,
              !signatureBase64.isEmpty else {
            logger.warn("Model signature not configured; skipping signature verification.")
            return true
        }

        guard let keyBase64 = trustedPublicKeysByID[keyID] else {
            throw ModelDownloadError.missingTrustedSignatureKey(keyID)
        }
        guard let keyData = Data(base64Encoded: keyBase64),
              let signatureData = Data(base64Encoded: signatureBase64) else {
            throw ModelDownloadError.invalidSignatureEncoding
        }

        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        let fileData = try Data(contentsOf: fileURL)
        guard publicKey.isValidSignature(signatureData, for: fileData) else {
            throw ModelDownloadError.signatureVerificationFailed
        }
        return true
    }

    private func modelStorageDirectory() throws -> URL {
        let base = try AppDirectories.applicationSupportURL()
        let dir = base.appendingPathComponent("AutoSuggestApp/Models", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func unpackArchiveIfNeeded(modelArchivePath: URL, manifest: ModelManifest) throws -> URL {
        guard modelArchivePath.pathExtension.lowercased() == "zip" else {
            return modelArchivePath
        }

        let installDir = try modelStorageDirectory()
            .appendingPathComponent("Installed", isDirectory: true)
            .appendingPathComponent("\(manifest.modelID)-\(manifest.version)", isDirectory: true)

        if FileManager.default.fileExists(atPath: installDir.path) {
            logger.info("Installed model directory already exists: \(installDir.path)")
            return installDir
        }

        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", modelArchivePath.path, installDir.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ModelDownloadError.extractionFailed(exitCode: process.terminationStatus)
        }

        logger.info("Model archive extracted to \(installDir.path)")
        return installDir
    }

    private func setActiveInstalledModel(path: URL) throws {
        let storageDir = try modelStorageDirectory()
        let pointer = storageDir.appendingPathComponent("active_model_path.txt", isDirectory: false)
        let previous = storageDir.appendingPathComponent("previous_model_path.txt", isDirectory: false)
        if let currentData = try? Data(contentsOf: pointer) {
            try currentData.write(to: previous, options: .atomic)
        }
        guard let data = path.path.data(using: .utf8) else {
            throw ModelDownloadError.invalidActiveModelPathEncoding
        }
        try data.write(to: pointer, options: .atomic)
        logger.info("Active model pointer updated: \(path.path)")
    }

    private func inferredFileName(from url: URL, fallback: String) -> String {
        let trimmed = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        return trimmed
    }
}

private struct HuggingFaceTreeItem: Decodable {
    let type: String
    let path: String
}
