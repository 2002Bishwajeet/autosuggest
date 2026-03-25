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

    // MARK: - Runtime order tests

    @MainActor
    func testDefaultOrderProducesThreeRuntimes() {
        let factory = makeFactory()
        let config = AppConfig.default.localModel
        let runtimes = factory.makeRuntimes(config: config)

        XCTAssertEqual(runtimes.count, 3)
        XCTAssertEqual(runtimes[0].name, "ollama")
        XCTAssertEqual(runtimes[1].name, "llama.cpp")
        XCTAssertEqual(runtimes[2].name, "coreml")
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

        XCTAssertEqual(runtimes.count, 3)
        XCTAssertEqual(runtimes[0].name, "coreml")
        XCTAssertEqual(runtimes[1].name, "ollama")
        XCTAssertEqual(runtimes[2].name, "llama.cpp")
    }

    // MARK: - Fallback and URL validation tests

    @MainActor
    func testFallbackDisabledSkipsOllamaAndLlamaCpp() {
        let factory = makeFactory()
        var config = AppConfig.default.localModel
        config.fallbackRuntimeEnabled = false

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
