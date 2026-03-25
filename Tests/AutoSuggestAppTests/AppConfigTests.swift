import XCTest
@testable import AutoSuggestApp

final class AppConfigTests: XCTestCase {

    // MARK: - Helpers

    /// Minimal JSON that satisfies all required fields for AppConfig decoding.
    /// Optional sections (privacy, telemetry, exclusions, battery, insertion, configVersion)
    /// are intentionally omitted so that decoder defaults kick in.
    private func minimalJSON(extras: [String: Any] = [:]) -> Data {
        var root: [String: Any] = [
            "enabled": true,
            "distribution": [
                "notarizationEnabled": false,
                "releaseChannel": "unsigned-pre-mvp"
            ],
            "localModel": [
                "autoDownloadOnFirstRun": false,
                "preferredRuntime": "ollama",
                "fallbackRuntimeEnabled": true,
                "isModelPresent": false,
                "fallbackManifest": [
                    "modelID": "test-model",
                    "version": "1.0",
                    "fileName": "test.mlpackage",
                    "downloadURL": "https://example.com/test.mlpackage",
                    "sha256": "abc123"
                ]
            ],
            "onlineLLM": [
                "enabled": false,
                "rolloutStage": "post-mvp"
            ]
        ]
        for (key, value) in extras {
            root[key] = value
        }
        return try! JSONSerialization.data(withJSONObject: root)
    }

    // MARK: - Tests

    func testDefaultConfigRoundTrips() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(AppConfig.default)
        let decoded = try decoder.decode(AppConfig.self, from: data)

        XCTAssertEqual(decoded.enabled, AppConfig.default.enabled)
        XCTAssertEqual(decoded.configVersion, AppConfig.default.configVersion)
        XCTAssertEqual(decoded.distribution.releaseChannel, AppConfig.default.distribution.releaseChannel)
        XCTAssertEqual(decoded.localModel.preferredRuntime, AppConfig.default.localModel.preferredRuntime)
        XCTAssertEqual(decoded.localModel.fallbackManifest.modelID, AppConfig.default.localModel.fallbackManifest.modelID)
        XCTAssertEqual(decoded.onlineLLM.enabled, AppConfig.default.onlineLLM.enabled)
        XCTAssertEqual(decoded.privacy.encryptedStorageEnabled, AppConfig.default.privacy.encryptedStorageEnabled)
        XCTAssertEqual(decoded.privacy.piiFilteringEnabled, AppConfig.default.privacy.piiFilteringEnabled)
        XCTAssertEqual(decoded.telemetry.enabled, AppConfig.default.telemetry.enabled)
        XCTAssertEqual(decoded.telemetry.localStoreOnly, AppConfig.default.telemetry.localStoreOnly)
        XCTAssertEqual(decoded.battery.mode, AppConfig.default.battery.mode)
        XCTAssertEqual(decoded.insertion.strictUndoSemantics, AppConfig.default.insertion.strictUndoSemantics)
        XCTAssertTrue(decoded.exclusions.userRules.isEmpty)
    }

    func testDecoderProvidesDefaultPrivacy() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: minimalJSON())

        XCTAssertTrue(config.privacy.encryptedStorageEnabled)
        XCTAssertTrue(config.privacy.piiFilteringEnabled)
        XCTAssertTrue(config.privacy.trainingAllowlistBundleIDs.isEmpty)
    }

    func testDecoderProvidesDefaultTelemetry() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: minimalJSON())

        XCTAssertFalse(config.telemetry.enabled)
        XCTAssertTrue(config.telemetry.localStoreOnly)
    }

    func testDecoderProvidesDefaultExclusions() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: minimalJSON())

        XCTAssertTrue(config.exclusions.userRules.isEmpty)
    }

    func testDecoderProvidesDefaultBattery() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: minimalJSON())

        XCTAssertEqual(config.battery.mode, .alwaysOn)
    }

    func testDecoderProvidesDefaultInsertion() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: minimalJSON())

        XCTAssertTrue(config.insertion.strictUndoSemantics)
    }

    func testConfigVersionDefaultsToZeroForLegacy() throws {
        // minimalJSON omits "configVersion", so the decoder should default to 0.
        let config = try JSONDecoder().decode(AppConfig.self, from: minimalJSON())

        XCTAssertEqual(config.configVersion, 0)
    }

    func testLocalModelFallbackManifestReadsLegacyKey() throws {
        // JSON uses the legacy "manifest" key instead of "fallbackManifest".
        let json: [String: Any] = [
            "enabled": true,
            "distribution": [
                "notarizationEnabled": false,
                "releaseChannel": "unsigned-pre-mvp"
            ],
            "localModel": [
                "autoDownloadOnFirstRun": false,
                "preferredRuntime": "coreml",
                "fallbackRuntimeEnabled": true,
                "isModelPresent": false,
                "manifest": [
                    "modelID": "legacy-model",
                    "version": "0.0.1",
                    "fileName": "legacy.zip",
                    "downloadURL": "https://example.com/legacy.zip",
                    "sha256": "deadbeef"
                ]
            ],
            "onlineLLM": [
                "enabled": false,
                "rolloutStage": "post-mvp"
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let config = try JSONDecoder().decode(AppConfig.self, from: data)

        XCTAssertEqual(config.localModel.fallbackManifest.modelID, "legacy-model")
        XCTAssertEqual(config.localModel.fallbackManifest.version, "0.0.1")
        XCTAssertEqual(config.localModel.fallbackManifest.sha256, "deadbeef")
    }

    func testBYOKConfigDefault() {
        let byok = BYOKConfig.default

        XCTAssertEqual(byok.selectedProvider, "openai-compatible")
    }
}
