import XCTest
@testable import AutoSuggestApp

final class ModelSourceResolverTests: XCTestCase {
    func testResolveDirectURL() {
        let resolver = ModelSourceResolver()
        let source = LocalModelCustomSourceConfig(
            sourceType: .directURL,
            modelID: "custom",
            version: "1.0.0",
            sha256: "",
            directURL: "https://example.com/model.zip",
            huggingFace: .init(
                repoID: "",
                revision: "main",
                filePath: "",
                tokenKeychainAccount: "test"
            )
        )

        XCTAssertEqual(resolver.resolveDownloadURL(from: source)?.absoluteString, "https://example.com/model.zip")
    }

    func testResolveHuggingFaceURL() {
        let resolver = ModelSourceResolver()
        let source = LocalModelCustomSourceConfig(
            sourceType: .huggingFace,
            modelID: "custom",
            version: "1.0.0",
            sha256: "",
            directURL: "",
            huggingFace: .init(
                repoID: "acme/awesome-model",
                revision: "main",
                filePath: "dist/model.zip",
                tokenKeychainAccount: "test"
            )
        )

        XCTAssertEqual(
            resolver.resolveDownloadURL(from: source)?.absoluteString,
            "https://huggingface.co/acme/awesome-model/resolve/main/dist/model.zip"
        )
    }
}
