import CryptoKit
import XCTest
@testable import AutoSuggestApp

final class ModelDownloadIntegrityTests: XCTestCase {

    private func makeManifest(
        sha256: String,
        downloadURL: URL,
        huggingFaceFolder: HuggingFaceFolderSource? = nil
    ) -> ModelManifest {
        ModelManifest(
            modelID: "test-model",
            version: "1.0",
            fileName: "test-model.zip",
            downloadURL: downloadURL,
            sha256: sha256,
            signatureKeyID: nil,
            signatureEd25519Base64: nil,
            huggingFaceFolder: huggingFaceFolder
        )
    }

    private func writeTempFile(_ contents: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("integrity-\(UUID().uuidString).bin", isDirectory: false)
        try contents.write(to: url)
        return url
    }

    // MARK: - Checksum: local file:// source with empty sha256 proceeds (dev workflow)

    func testEmptyChecksumLocalFileDoesNotThrow() throws {
        let manager = ModelDownloadManager()
        let fileURL = try writeTempFile(Data("local-dev-artifact".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let manifest = makeManifest(sha256: "", downloadURL: fileURL)
        // file:// source, empty checksum -> warn-and-proceed (no throw).
        XCTAssertNoThrow(try manager.validateArtifactIntegrity(fileURL: fileURL, manifest: manifest))
    }

    // MARK: - Checksum: correct hash passes, wrong hash throws checksumMismatch

    func testCorrectChecksumPasses() throws {
        let manager = ModelDownloadManager()
        let payload = Data("verifiable-bytes".utf8)
        let fileURL = try writeTempFile(payload)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let expected = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        let manifest = makeManifest(
            sha256: expected,
            downloadURL: URL(string: "https://example.com/test-model.zip")!
        )
        XCTAssertNoThrow(try manager.validateArtifactIntegrity(fileURL: fileURL, manifest: manifest))
    }

    func testWrongChecksumThrowsChecksumMismatch() throws {
        let manager = ModelDownloadManager()
        let fileURL = try writeTempFile(Data("verifiable-bytes".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let manifest = makeManifest(
            sha256: String(repeating: "0", count: 64),
            downloadURL: URL(string: "https://example.com/test-model.zip")!
        )
        XCTAssertThrowsError(try manager.validateArtifactIntegrity(fileURL: fileURL, manifest: manifest)) { error in
            guard case ModelDownloadError.checksumMismatch = error else {
                return XCTFail("Expected checksumMismatch, got \(error)")
            }
        }
    }

    // MARK: - Extraction validation: symlink escaping installDir throws unsafeArchiveContents

    func testExtractionWithEscapingSymlinkThrows() throws {
        let manager = ModelDownloadManager()
        let fm = FileManager.default
        let installDir = fm.temporaryDirectory
            .appendingPathComponent("install-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: installDir, withIntermediateDirectories: true)

        // A symlink inside installDir pointing outside it (to /tmp).
        let escapeLink = installDir.appendingPathComponent("escape", isDirectory: false)
        try fm.createSymbolicLink(at: escapeLink, withDestinationURL: URL(fileURLWithPath: "/tmp"))

        XCTAssertThrowsError(try manager.validateExtractedContents(installDir: installDir)) { error in
            guard case ModelDownloadError.unsafeArchiveContents = error else {
                return XCTFail("Expected unsafeArchiveContents, got \(error)")
            }
        }
        // Validation removes the install dir on failure (fail closed).
        XCTAssertFalse(fm.fileExists(atPath: installDir.path))
    }

    func testExtractionWithContainedContentsDoesNotThrow() throws {
        let manager = ModelDownloadManager()
        let fm = FileManager.default
        let installDir = fm.temporaryDirectory
            .appendingPathComponent("install-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: installDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: installDir) }

        let nested = installDir.appendingPathComponent("weights", isDirectory: true)
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("model".utf8).write(to: nested.appendingPathComponent("model.bin", isDirectory: false))

        XCTAssertNoThrow(try manager.validateExtractedContents(installDir: installDir))
        XCTAssertTrue(fm.fileExists(atPath: installDir.path))
    }
}
