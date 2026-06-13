import XCTest
@testable import AutoSuggestApp

final class InferenceRuntimeFactoryTests: XCTestCase {
    @MainActor
    private func makeFactory() -> InferenceRuntimeFactory {
        InferenceRuntimeFactory(
            localModelSession: LocalModelSession(),
            personalizationEngine: PersonalizationEngine(store: EncryptedFileStore()),
            coreMLModelAdapter: CoreMLModelAdapter()
        )
    }

    /// Whether the FoundationModels runtime can be registered by the factory on
    /// the current toolchain/OS. Mirrors the factory's own gating so assertions
    /// hold on both macOS 26 + SDK (registers) and CI / older toolchains (omits).
    private var foundationModelsRegistrable: Bool {
        #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                return true
            }
            return false
        #else
            return false
        #endif
    }

    // MARK: - Runtime order tests

    @MainActor
    func testDefaultOrderRegistersExpectedRuntimes() {
        let factory = makeFactory()
        let config = AppConfig.default.localModel
        let runtimes = factory.makeRuntimes(config: config)

        if foundationModelsRegistrable {
            // Default order is ["foundationmodels","coreml","ollama","llama.cpp"].
            XCTAssertEqual(runtimes.count, 4)
            XCTAssertEqual(runtimes.map(\.name), ["foundationmodels", "coreml", "ollama", "llama.cpp"])
        } else {
            XCTAssertEqual(runtimes.count, 3)
            XCTAssertEqual(runtimes.map(\.name), ["coreml", "ollama", "llama.cpp"])
        }
    }

    @MainActor
    func testCustomOrderIsRespected() {
        let factory = makeFactory()
        var config = AppConfig.default.localModel
        config.runtimeOrder = ["llama.cpp", "ollama"]

        let runtimes = factory.makeRuntimes(config: config)

        XCTAssertEqual(runtimes.count, 2)
        XCTAssertEqual(runtimes[0].name, "llama.cpp")
        XCTAssertEqual(runtimes[1].name, "ollama")
    }

    @MainActor
    func testUnknownRuntimeNameIsSkipped() {
        let factory = makeFactory()
        var config = AppConfig.default.localModel
        config.runtimeOrder = ["ollama", "unknown", "coreml"]

        let runtimes = factory.makeRuntimes(config: config)

        XCTAssertEqual(runtimes.count, 2)
        XCTAssertEqual(runtimes[0].name, "ollama")
        XCTAssertEqual(runtimes[1].name, "coreml")
    }

    @MainActor
    func testEmptyOrderUsesDefaults() {
        let factory = makeFactory()
        var config = AppConfig.default.localModel
        config.runtimeOrder = []

        let runtimes = factory.makeRuntimes(config: config)

        if foundationModelsRegistrable {
            XCTAssertEqual(runtimes.map(\.name), ["foundationmodels", "coreml", "ollama", "llama.cpp"])
        } else {
            XCTAssertEqual(runtimes.map(\.name), ["coreml", "ollama", "llama.cpp"])
        }
    }

    // MARK: - FoundationModels registration (A8)

    @MainActor
    func testFoundationModelsRegisteredFirstWhenAvailableAndEnabled() throws {
        try XCTSkipUnless(foundationModelsRegistrable, "FoundationModels SDK/OS not available on this toolchain")
        let factory = makeFactory()
        var config = AppConfig.default.localModel
        config.runtimeOrder = ["foundationmodels", "coreml", "ollama", "llama.cpp"]
        config.foundationModelsEnabled = true

        let runtimes = factory.makeRuntimes(config: config)

        XCTAssertEqual(runtimes.first?.name, "foundationmodels")
        XCTAssertEqual(runtimes.map(\.name), ["foundationmodels", "coreml", "ollama", "llama.cpp"])
    }

    @MainActor
    func testFoundationModelsOmittedWhenFlagOff() {
        let factory = makeFactory()
        var config = AppConfig.default.localModel
        config.runtimeOrder = ["foundationmodels", "coreml", "ollama", "llama.cpp"]
        config.foundationModelsEnabled = false

        let runtimes = factory.makeRuntimes(config: config)

        XCTAssertFalse(runtimes.contains { $0.name == "foundationmodels" })
        XCTAssertEqual(runtimes.map(\.name), ["coreml", "ollama", "llama.cpp"])
    }

    @MainActor
    func testFoundationModelsAliasesCanonicalize() throws {
        try XCTSkipUnless(foundationModelsRegistrable, "FoundationModels SDK/OS not available on this toolchain")
        let factory = makeFactory()
        var config = AppConfig.default.localModel
        config.foundationModelsEnabled = true

        for alias in ["foundation-models", "applellm", "FoundationModels"] {
            config.runtimeOrder = [alias]
            let runtimes = factory.makeRuntimes(config: config)
            XCTAssertEqual(runtimes.map(\.name), ["foundationmodels"], "alias \(alias) should canonicalize")
        }
    }

    @MainActor
    func testUnavailableFoundationModelsDoesNotCrashAndIsOmitted() {
        // Regardless of registrability, asking for foundationmodels must never
        // crash. When the SDK/OS is absent the runtime is silently omitted.
        let factory = makeFactory()
        var config = AppConfig.default.localModel
        config.runtimeOrder = ["foundationmodels", "coreml"]
        config.foundationModelsEnabled = true

        let runtimes = factory.makeRuntimes(config: config)

        if foundationModelsRegistrable {
            XCTAssertEqual(runtimes.map(\.name), ["foundationmodels", "coreml"])
        } else {
            XCTAssertEqual(runtimes.map(\.name), ["coreml"])
        }
    }

    // MARK: - Fallback and URL validation tests

    @MainActor
    func testFallbackDisabledSkipsOllamaAndLlamaCpp() {
        let factory = makeFactory()
        var config = AppConfig.default.localModel
        config.fallbackRuntimeEnabled = false
        config.foundationModelsEnabled = false

        let runtimes = factory.makeRuntimes(config: config)

        XCTAssertEqual(runtimes.count, 1)
        XCTAssertEqual(runtimes[0].name, "coreml")
    }

    @MainActor
    func testInvalidBaseURLSkipsRuntime() {
        let factory = makeFactory()
        var config = AppConfig.default.localModel
        config.runtimeOrder = ["ollama"]
        config.fallbackRuntimeEnabled = true
        config.ollama.baseURL = "not-a-valid-url"

        let runtimes = factory.makeRuntimes(config: config)

        XCTAssertTrue(runtimes.isEmpty)
    }
}
