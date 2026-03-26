import XCTest
@testable import AutoSuggestApp

final class ModelManifestTests: XCTestCase {

    // MARK: - ModelManifest Codable

    func testModelManifestRoundTrips() throws {
        let manifest = ModelManifest(
            modelID: "test-model",
            version: "2.0.0",
            fileName: "test-model.mlpackage",
            downloadURL: URL(string: "https://example.com/model.zip")!,
            sha256: "abc123",
            signatureKeyID: "key-1",
            signatureEd25519Base64: "c2lnbmF0dXJl",
            huggingFaceFolder: HuggingFaceFolderSource(
                repo: "org/repo",
                revision: "main",
                folderPath: "model.mlpackage"
            )
        )

        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(ModelManifest.self, from: data)

        XCTAssertEqual(decoded.modelID, manifest.modelID)
        XCTAssertEqual(decoded.version, manifest.version)
        XCTAssertEqual(decoded.fileName, manifest.fileName)
        XCTAssertEqual(decoded.downloadURL, manifest.downloadURL)
        XCTAssertEqual(decoded.sha256, manifest.sha256)
        XCTAssertEqual(decoded.signatureKeyID, manifest.signatureKeyID)
        XCTAssertEqual(decoded.signatureEd25519Base64, manifest.signatureEd25519Base64)
        XCTAssertEqual(decoded.huggingFaceFolder, manifest.huggingFaceFolder)
    }

    // MARK: - ModelManifest.initial

    func testInitialManifestHasExpectedModelID() {
        XCTAssertEqual(ModelManifest.initial.modelID, "OpenELM-270M")
    }

    func testInitialManifestHasHuggingFaceFolder() {
        XCTAssertNotNil(ModelManifest.initial.huggingFaceFolder)
    }

    // MARK: - LocalModelCustomSourceConfig

    func testCustomSourceDefaultValues() {
        let config = LocalModelCustomSourceConfig.default

        XCTAssertEqual(config.sourceType, .directURL)
        XCTAssertEqual(config.modelID, "custom-local-model")
        XCTAssertEqual(config.version, "0.1.0")
        XCTAssertEqual(config.sha256, "")
        XCTAssertEqual(config.directURL, "")
        XCTAssertEqual(config.huggingFace.repoID, "")
        XCTAssertEqual(config.huggingFace.revision, "main")
        XCTAssertEqual(config.huggingFace.filePath, "")
        XCTAssertEqual(config.huggingFace.tokenKeychainAccount, "autosuggest.huggingface.token")
    }

    // MARK: - BYOKConfig

    func testBYOKConfigDefaultValues() {
        let config = BYOKConfig.default

        XCTAssertEqual(config.provider, .openAICompatible)
        XCTAssertEqual(config.selectedModel, "gpt-4o-mini")
        XCTAssertNil(config.endpointURL)
        XCTAssertEqual(config.apiKeyKeychainAccount, "autosuggest.online.byok.default")
        XCTAssertEqual(config.priority, .fallback)
    }

    // MARK: - HuggingFaceFolderSource Codable

    func testHuggingFaceFolderSourceCodable() throws {
        let source = HuggingFaceFolderSource(
            repo: "org/model-repo",
            revision: "v2",
            folderPath: "weights/model.mlpackage"
        )

        let data = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(HuggingFaceFolderSource.self, from: data)

        XCTAssertEqual(decoded, source)
    }

    // MARK: - Nil optionals

    func testManifestWithNilOptionals() throws {
        let manifest = ModelManifest(
            modelID: "minimal-model",
            version: "0.1.0",
            fileName: "minimal.mlmodelc",
            downloadURL: URL(string: "https://example.com/minimal.zip")!,
            sha256: "deadbeef",
            signatureKeyID: nil,
            signatureEd25519Base64: nil,
            huggingFaceFolder: nil
        )

        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(ModelManifest.self, from: data)

        XCTAssertEqual(decoded.modelID, "minimal-model")
        XCTAssertEqual(decoded.version, "0.1.0")
        XCTAssertEqual(decoded.fileName, "minimal.mlmodelc")
        XCTAssertEqual(decoded.downloadURL, URL(string: "https://example.com/minimal.zip")!)
        XCTAssertEqual(decoded.sha256, "deadbeef")
        XCTAssertNil(decoded.signatureKeyID)
        XCTAssertNil(decoded.signatureEd25519Base64)
        XCTAssertNil(decoded.huggingFaceFolder)
    }
}
