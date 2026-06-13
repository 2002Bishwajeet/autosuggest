import XCTest
@testable import AutoSuggestApp

final class ConfigMigrationManagerTests: XCTestCase {
    // MARK: - ConfigMigrationManager

    func testMigrateV0toV1ReordersRuntimes() {
        var config = AppConfig.default
        config.configVersion = 0
        config.localModel.runtimeOrder = ["coreml", "ollama", "llama.cpp"]
        config.localModel.preferredRuntime = "coreml"

        let manager = ConfigMigrationManager()
        manager.migrate(&config)

        // v0->v1 reorders to Ollama-first; v2->v3 then prepends FoundationModels
        // because the result is a known prior default.
        XCTAssertEqual(config.localModel.runtimeOrder, ["foundationmodels", "ollama", "llama.cpp", "coreml"])
        XCTAssertEqual(config.localModel.preferredRuntime, "ollama")
    }

    func testMigrateV0toV1SkipsCustomOrder() {
        var config = AppConfig.default
        config.configVersion = 0
        config.localModel.runtimeOrder = ["llama.cpp", "ollama", "coreml"]
        config.localModel.preferredRuntime = "llama.cpp"

        let manager = ConfigMigrationManager()
        manager.migrate(&config)

        // v0->v1 leaves this custom order alone; v2->v3 only appends
        // FoundationModels (never reorders a customized order).
        XCTAssertEqual(config.localModel.runtimeOrder, ["llama.cpp", "ollama", "coreml", "foundationmodels"])
        XCTAssertEqual(config.localModel.preferredRuntime, "llama.cpp")
    }

    func testMigrateV1PreservesRuntimeAndAppliesV3() {
        var config = AppConfig.default
        config.configVersion = 1
        // A v1 config carried the v1 default order (FoundationModels did not exist).
        config.localModel.runtimeOrder = ["ollama", "llama.cpp", "coreml"]
        config.localModel.preferredRuntime = "ollama"

        let manager = ConfigMigrationManager()
        manager.migrate(&config)

        // v1->v2 is a no-op for runtime order; v2->v3 prepends FoundationModels
        // to the recognized prior default.
        XCTAssertEqual(config.localModel.runtimeOrder, ["foundationmodels", "ollama", "llama.cpp", "coreml"])
        XCTAssertEqual(config.localModel.preferredRuntime, "ollama")
        XCTAssertTrue(config.localModel.foundationModelsEnabled)
    }

    func testMigrateSetsCurrentVersion() {
        var config = AppConfig.default
        config.configVersion = 0

        let manager = ConfigMigrationManager()
        manager.migrate(&config)

        XCTAssertEqual(config.configVersion, AppConfig.currentConfigVersion)
    }

    // MARK: - V2 -> V3 FoundationModels migration (A6 / A8)

    func testMigrateV2toV3PrependsToOldDefaultOrder() {
        var config = AppConfig.default
        config.configVersion = 2
        config.localModel.runtimeOrder = ["ollama", "llama.cpp", "coreml"]
        config.localModel.foundationModelsEnabled = false

        let manager = ConfigMigrationManager()
        manager.migrate(&config)

        XCTAssertEqual(config.localModel.runtimeOrder, ["foundationmodels", "ollama", "llama.cpp", "coreml"])
        XCTAssertTrue(config.localModel.foundationModelsEnabled, "Migration must enable FoundationModels")
    }

    func testMigrateV2toV3PrependsToLegacyCoreMLFirstDefault() {
        var config = AppConfig.default
        config.configVersion = 2
        // The other recognized prior default (v0 order). It is a "known default"
        // so v2->v3 still prepends rather than appends.
        config.localModel.runtimeOrder = ["coreml", "ollama", "llama.cpp"]

        let manager = ConfigMigrationManager()
        manager.migrate(&config)

        XCTAssertEqual(config.localModel.runtimeOrder, ["foundationmodels", "coreml", "ollama", "llama.cpp"])
    }

    func testMigrateV2toV3LeavesCustomizedOrderUntouchedExceptAppend() {
        var config = AppConfig.default
        config.configVersion = 2
        // A user-customized order (not a recognized default).
        config.localModel.runtimeOrder = ["coreml", "llama.cpp", "ollama"]

        let manager = ConfigMigrationManager()
        manager.migrate(&config)

        // Existing order preserved verbatim; FoundationModels appended (never
        // reordered/clobbered).
        XCTAssertEqual(config.localModel.runtimeOrder, ["coreml", "llama.cpp", "ollama", "foundationmodels"])
        XCTAssertTrue(config.localModel.foundationModelsEnabled)
    }

    func testMigrateV2toV3DoesNotDuplicateWhenAlreadyPresent() {
        var config = AppConfig.default
        config.configVersion = 2
        config.localModel.runtimeOrder = ["foundationmodels", "ollama", "coreml"]

        let manager = ConfigMigrationManager()
        manager.migrate(&config)

        XCTAssertEqual(config.localModel.runtimeOrder, ["foundationmodels", "ollama", "coreml"])
        XCTAssertEqual(
            config.localModel.runtimeOrder.count(where: { $0 == "foundationmodels" }),
            1,
            "FoundationModels must appear exactly once"
        )
    }

    func testMigrateV2toV3IsIdempotent() {
        var config = AppConfig.default
        config.configVersion = 2
        config.localModel.runtimeOrder = ["ollama", "llama.cpp", "coreml"]

        let manager = ConfigMigrationManager()
        manager.migrate(&config)
        let afterFirst = config.localModel.runtimeOrder

        // Force the version back and migrate again — must add nothing.
        config.configVersion = 2
        manager.migrate(&config)

        XCTAssertEqual(config.localModel.runtimeOrder, afterFirst)
        XCTAssertEqual(config.localModel.runtimeOrder, ["foundationmodels", "ollama", "llama.cpp", "coreml"])
    }

    // MARK: - V3 -> V4 personalizationEnabled migration

    func testMigrateV3toV4SetsPersonalizationEnabled() {
        var config = AppConfig.default
        config.configVersion = 3

        let manager = ConfigMigrationManager()
        manager.migrate(&config)

        XCTAssertTrue(config.privacy.personalizationEnabled, "v3->v4 must set personalizationEnabled to true")
        XCTAssertEqual(config.configVersion, AppConfig.currentConfigVersion)
    }

    func testMigrateV3toV4IsIdempotent() {
        var config = AppConfig.default
        config.configVersion = 3

        let manager = ConfigMigrationManager()
        manager.migrate(&config)

        // Force back and migrate again — flag stays true, no crash.
        config.configVersion = 3
        manager.migrate(&config)

        XCTAssertTrue(config.privacy.personalizationEnabled)
    }

    func testPersonalizationEnabledDefaultsTrueOnLegacyDecode() throws {
        // A v3 JSON without personalizationEnabled decodes with the flag = true.
        let json = """
        {
          "configVersion": 3,
          "enabled": true,
          "distribution": { "notarizationEnabled": false, "releaseChannel": "x" },
          "localModel": {
            "autoDownloadOnFirstRun": false,
            "preferredRuntime": "ollama",
            "runtimeOrder": ["foundationmodels", "ollama", "llama.cpp", "coreml"],
            "fallbackRuntimeEnabled": true,
            "isModelPresent": false,
            "fallbackManifest": {
              "modelID": "m", "version": "1.0", "fileName": "m.mlpackage",
              "downloadURL": "https://example.com/m.mlpackage", "sha256": "abc"
            }
          },
          "onlineLLM": { "enabled": false, "rolloutStage": "available" },
          "privacy": {
            "encryptedStorageEnabled": true,
            "piiFilteringEnabled": true,
            "trainingAllowlistBundleIDs": [],
            "trainingDataCollectionEnabled": false
          }
        }
        """
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertTrue(config.privacy.personalizationEnabled, "Missing key should default to true")
    }

    func testPersonalizationEnabledRoundTrips() throws {
        var config = AppConfig.default
        config.privacy.personalizationEnabled = false

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertFalse(decoded.privacy.personalizationEnabled, "false value must survive encode/decode round-trip")
    }

    // MARK: - V0 / V1 config preservation (must never break legacy configs)

    func testLegacyV0ConfigDecodesAndMigratesWithoutLoss() throws {
        // A pre-FoundationModels config JSON (no configVersion → defaults to 0,
        // no foundationModelsEnabled key, no runtimeOrder key).
        let json = """
        {
          "enabled": true,
          "distribution": { "notarizationEnabled": false, "releaseChannel": "unsigned-pre-mvp" },
          "localModel": {
            "autoDownloadOnFirstRun": false,
            "preferredRuntime": "coreml",
            "fallbackRuntimeEnabled": true,
            "isModelPresent": false,
            "manifest": {
              "modelID": "legacy", "version": "0.0.1", "fileName": "legacy.zip",
              "downloadURL": "https://example.com/legacy.zip", "sha256": "abc"
            }
          },
          "onlineLLM": { "enabled": false, "rolloutStage": "post-mvp" }
        }
        """
        var config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))

        // Decode defaults preserved: missing key defaults to true / v1 order.
        XCTAssertEqual(config.configVersion, 0)
        XCTAssertTrue(config.localModel.foundationModelsEnabled)
        XCTAssertEqual(config.localModel.runtimeOrder, ["ollama", "llama.cpp", "coreml"])

        let manager = ConfigMigrationManager()
        manager.migrate(&config)

        // Legacy fields untouched; FoundationModels prepended to the recognized default.
        XCTAssertEqual(config.localModel.fallbackManifest.modelID, "legacy")
        XCTAssertEqual(config.localModel.runtimeOrder, ["foundationmodels", "ollama", "llama.cpp", "coreml"])
        XCTAssertEqual(config.configVersion, AppConfig.currentConfigVersion)
    }

    func testFoundationModelsEnabledDefaultsTrueOnLegacyDecode() throws {
        // A v2 config JSON without the new key still decodes with the flag true.
        let json = """
        {
          "configVersion": 2,
          "enabled": true,
          "distribution": { "notarizationEnabled": false, "releaseChannel": "x" },
          "localModel": {
            "autoDownloadOnFirstRun": false,
            "preferredRuntime": "ollama",
            "runtimeOrder": ["ollama", "llama.cpp", "coreml"],
            "fallbackRuntimeEnabled": true,
            "isModelPresent": false,
            "fallbackManifest": {
              "modelID": "m", "version": "1.0", "fileName": "m.mlpackage",
              "downloadURL": "https://example.com/m.mlpackage", "sha256": "abc"
            }
          },
          "onlineLLM": { "enabled": false, "rolloutStage": "available" }
        }
        """
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertTrue(config.localModel.foundationModelsEnabled)
    }

    // MARK: - ConfigValidator

    func testValidateRemovesUnknownRuntimes() {
        var config = AppConfig.default
        config.localModel.runtimeOrder = ["ollama", "unknown_runtime", "coreml"]

        let validator = ConfigValidator()
        validator.validate(&config)

        XCTAssertEqual(config.localModel.runtimeOrder, ["ollama", "coreml"])
    }

    func testValidateKeepsFoundationModelsInOrder() {
        // Regression guard: the validator must NOT strip "foundationmodels".
        var config = AppConfig.default
        config.localModel.runtimeOrder = ["foundationmodels", "coreml", "ollama", "llama.cpp"]

        let validator = ConfigValidator()
        validator.validate(&config)

        XCTAssertEqual(config.localModel.runtimeOrder, ["foundationmodels", "coreml", "ollama", "llama.cpp"])
    }

    func testValidateResetsEmptyRuntimeOrder() {
        var config = AppConfig.default
        config.localModel.runtimeOrder = []

        let validator = ConfigValidator()
        validator.validate(&config)

        XCTAssertEqual(config.localModel.runtimeOrder, ["ollama", "llama.cpp", "coreml"])
    }

    func testValidateFixesInvalidOllamaURL() {
        var config = AppConfig.default
        // Use a truly empty string - the validator checks non-empty + URL(string:) == nil
        config.localModel.ollama.baseURL = "http://[invalid"

        let validator = ConfigValidator()
        validator.validate(&config)

        XCTAssertEqual(config.localModel.ollama.baseURL, "http://127.0.0.1:11434")
    }

    func testValidateFixesInvalidLlamaCppURL() {
        var config = AppConfig.default
        config.localModel.llamaCpp.baseURL = "http://[invalid"

        let validator = ConfigValidator()
        validator.validate(&config)

        XCTAssertEqual(config.localModel.llamaCpp.baseURL, "http://127.0.0.1:8080")
    }

    func testValidateDisablesRulesWithBadRegex() {
        var config = AppConfig.default
        config.exclusions.userRules = [
            ExclusionRule(enabled: true, bundleID: nil, windowTitleContains: nil, contentPattern: "[invalid(regex"),
        ]

        let validator = ConfigValidator()
        validator.validate(&config)

        XCTAssertEqual(config.exclusions.userRules.count, 1)
        XCTAssertFalse(config.exclusions.userRules[0].enabled)
    }

    func testValidateKeepsValidConfig() {
        var config = AppConfig.default
        config.localModel.runtimeOrder = ["ollama", "llama.cpp", "coreml"]
        config.localModel.ollama.baseURL = "http://127.0.0.1:11434"
        config.localModel.llamaCpp.baseURL = "http://127.0.0.1:8080"
        config.exclusions.userRules = [
            ExclusionRule(
                enabled: true,
                bundleID: "com.example.app",
                windowTitleContains: nil,
                contentPattern: "^secret.*$"
            ),
        ]

        let expected = config

        let validator = ConfigValidator()
        validator.validate(&config)

        XCTAssertEqual(config.localModel.runtimeOrder, expected.localModel.runtimeOrder)
        XCTAssertEqual(config.localModel.ollama.baseURL, expected.localModel.ollama.baseURL)
        XCTAssertEqual(config.localModel.llamaCpp.baseURL, expected.localModel.llamaCpp.baseURL)
        XCTAssertEqual(config.exclusions.userRules, expected.exclusions.userRules)
    }
}
