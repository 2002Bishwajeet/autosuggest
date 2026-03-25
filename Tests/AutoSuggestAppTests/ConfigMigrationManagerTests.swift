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

        XCTAssertEqual(config.localModel.runtimeOrder, ["ollama", "llama.cpp", "coreml"])
        XCTAssertEqual(config.localModel.preferredRuntime, "ollama")
    }

    func testMigrateV0toV1SkipsCustomOrder() {
        var config = AppConfig.default
        config.configVersion = 0
        config.localModel.runtimeOrder = ["llama.cpp", "ollama", "coreml"]
        config.localModel.preferredRuntime = "llama.cpp"

        let manager = ConfigMigrationManager()
        manager.migrate(&config)

        XCTAssertEqual(config.localModel.runtimeOrder, ["llama.cpp", "ollama", "coreml"])
        XCTAssertEqual(config.localModel.preferredRuntime, "llama.cpp")
    }

    func testMigrateV1IsNoop() {
        var config = AppConfig.default
        config.configVersion = 1
        let originalOrder = config.localModel.runtimeOrder
        let originalRuntime = config.localModel.preferredRuntime

        let manager = ConfigMigrationManager()
        manager.migrate(&config)

        XCTAssertEqual(config.localModel.runtimeOrder, originalOrder)
        XCTAssertEqual(config.localModel.preferredRuntime, originalRuntime)
    }

    func testMigrateSetsCurrentVersion() {
        var config = AppConfig.default
        config.configVersion = 0

        let manager = ConfigMigrationManager()
        manager.migrate(&config)

        XCTAssertEqual(config.configVersion, AppConfig.currentConfigVersion)
    }

    // MARK: - ConfigValidator

    func testValidateRemovesUnknownRuntimes() {
        var config = AppConfig.default
        config.localModel.runtimeOrder = ["ollama", "unknown_runtime", "coreml"]

        let validator = ConfigValidator()
        validator.validate(&config)

        XCTAssertEqual(config.localModel.runtimeOrder, ["ollama", "coreml"])
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
            ExclusionRule(enabled: true, bundleID: nil, windowTitleContains: nil, contentPattern: "[invalid(regex")
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
            ExclusionRule(enabled: true, bundleID: "com.example.app", windowTitleContains: nil, contentPattern: "^secret.*$")
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
