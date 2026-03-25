import Foundation

struct ModelManifestProvider {
    private let logger = Logger(scope: "ModelManifestProvider")
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func resolveManifest(config: LocalModelConfig) async -> ModelManifest {
        let cached = loadCachedManifest(for: config.manifestSourceURL)
        do {
            let remote = try await fetchRemoteManifest(
                from: config.manifestSourceURL,
                etag: cached?.etag
            )
            switch remote {
            case .notModified:
                if let cachedManifest = cached?.manifest {
                    logger.info("Using cached model manifest (304 not modified).")
                    return cachedManifest
                }
                logger.warn("Remote returned 304 but cache is empty; using fallback manifest.")
                return config.fallbackManifest
            case .updated(let manifest, let etag):
                saveCachedManifest(
                    ManifestCacheRecord(
                        sourceURL: config.manifestSourceURL.absoluteString,
                        etag: etag,
                        manifest: manifest
                    )
                )
                logger.info("Using remote model manifest \(manifest.modelID)@\(manifest.version)")
                return manifest
            }
        } catch {
            if let cachedManifest = cached?.manifest {
                logger.warn("Remote manifest unavailable, using cached copy: \(error.localizedDescription)")
                return cachedManifest
            }
            logger.warn("Remote manifest unavailable, using fallback: \(error.localizedDescription)")
            return config.fallbackManifest
        }
    }

    private func fetchRemoteManifest(from url: URL, etag: String?) async throws -> RemoteManifestResult {
        if url.isFileURL {
            let data = try Data(contentsOf: url)
            let manifest = try decoder.decode(ModelManifest.self, from: data)
            return .updated(manifest, nil)
        }

        var request = URLRequest(url: url)
        if let etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 304 {
            return .notModified
        }
        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let manifest = try decoder.decode(ModelManifest.self, from: data)
        let responseETag = http.value(forHTTPHeaderField: "ETag")
        return .updated(manifest, responseETag)
    }

    private func loadCachedManifest(for sourceURL: URL) -> ManifestCacheRecord? {
        guard let file = try? cacheFileURL(),
              let data = try? Data(contentsOf: file),
              let cached = try? decoder.decode(ManifestCacheRecord.self, from: data),
              cached.sourceURL == sourceURL.absoluteString else {
            return nil
        }
        return cached
    }

    private func saveCachedManifest(_ record: ManifestCacheRecord) {
        guard let file = try? cacheFileURL(),
              let data = try? encoder.encode(record) else {
            return
        }
        try? data.write(to: file, options: .atomic)
    }

    private func cacheFileURL() throws -> URL {
        let base = try AppDirectories.applicationSupportURL()
        let dir = base.appendingPathComponent("AutoSuggestApp/ModelCache", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("manifest-cache.json", isDirectory: false)
    }
}

private enum RemoteManifestResult {
    case notModified
    case updated(ModelManifest, String?)
}

private struct ManifestCacheRecord: Codable {
    let sourceURL: String
    let etag: String?
    let manifest: ModelManifest
}
