import Foundation

struct ModelSourceResolver {
    func resolveDownloadURL(from source: LocalModelCustomSourceConfig) -> URL? {
        switch source.sourceType {
        case .directURL:
            guard !source.directURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return URL(string: source.directURL)
        case .huggingFace:
            return resolveHuggingFaceURL(
                repoID: source.huggingFace.repoID,
                revision: source.huggingFace.revision,
                filePath: source.huggingFace.filePath
            )
        }
    }

    func resolveHuggingFaceURL(repoID: String, revision: String, filePath: String) -> URL? {
        let repo = repoID.trimmingCharacters(in: .whitespacesAndNewlines)
        let rev = revision.trimmingCharacters(in: .whitespacesAndNewlines)
        let file = filePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repo.isEmpty, !rev.isEmpty, !file.isEmpty else { return nil }

        let repoParts = repo.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let fileParts = file.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard repoParts.count >= 2, !fileParts.isEmpty else { return nil }

        let pathParts = repoParts + ["resolve", rev] + fileParts
        let encodedPath = pathParts.map {
            $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0
        }.joined(separator: "/")

        var components = URLComponents()
        components.scheme = "https"
        components.host = "huggingface.co"
        components.percentEncodedPath = "/" + encodedPath
        return components.url
    }
}
