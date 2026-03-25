import XCTest
@testable import AutoSuggestApp

final class ConfigMigrationTests: XCTestCase {
    func testLegacyManifestConfigDecodesIntoFallbackManifest() throws {
        let json = """
        {
          "enabled": true,
          "distribution": {
            "notarizationEnabled": false,
            "releaseChannel": "unsigned-pre-mvp"
          },
          "localModel": {
            "autoDownloadOnFirstRun": true,
            "preferredRuntime": "coreml",
            "fallbackRuntimeEnabled": true,
            "isModelPresent": false,
            "manifest": {
              "modelID": "legacy-model",
              "version": "0.0.1",
              "fileName": "legacy.zip",
              "downloadURL": "https://example.com/legacy.zip",
              "sha256": "abc123"
            }
          },
          "onlineLLM": {
            "enabled": false,
            "rolloutStage": "post-mvp"
          }
        }
        """

        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.localModel.fallbackManifest.modelID, "legacy-model")
        XCTAssertEqual(
            config.localModel.manifestSourceURL.absoluteString,
            "https://raw.githubusercontent.com/autosuggest/models/main/manifest/stable.json"
        )
        XCTAssertTrue(config.privacy.encryptedStorageEnabled)
        XCTAssertFalse(config.telemetry.enabled)
        XCTAssertTrue(config.exclusions.userRules.isEmpty)
        XCTAssertEqual(config.battery.mode, .alwaysOn)
        XCTAssertTrue(config.insertion.strictUndoSemantics)
        XCTAssertEqual(config.localModel.customSource.sourceType, .directURL)
        XCTAssertEqual(config.localModel.customSource.huggingFace.revision, "main")
    }
}
