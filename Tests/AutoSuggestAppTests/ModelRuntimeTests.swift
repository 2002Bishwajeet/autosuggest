import XCTest
@testable import AutoSuggestApp

final class ModelRuntimeTests: XCTestCase {
    func testConfigValueMapping() {
        XCTAssertEqual(ModelRuntime(configValue: "ollama"), .ollama)
        XCTAssertEqual(ModelRuntime(configValue: "llama.cpp"), .llamaCpp)
        XCTAssertEqual(ModelRuntime(configValue: "llamacpp"), .llamaCpp)
        XCTAssertEqual(ModelRuntime(configValue: "llama_cpp"), .llamaCpp)
        XCTAssertEqual(ModelRuntime(configValue: "llamaserver"), .llamaCpp)
        XCTAssertEqual(ModelRuntime(configValue: "coreml"), .coreML)
        XCTAssertEqual(ModelRuntime(configValue: "core ml"), .coreML)
        XCTAssertEqual(ModelRuntime(configValue: "foundationmodels"), .foundationModels)
        XCTAssertEqual(ModelRuntime(configValue: "FoundationModels"), .foundationModels)
        XCTAssertNil(ModelRuntime(configValue: "nonsense"))
    }

    func testDisplayNames() {
        XCTAssertEqual(ModelRuntime.ollama.displayName, "Ollama")
        XCTAssertEqual(ModelRuntime.llamaCpp.displayName, "llama.cpp")
        XCTAssertEqual(ModelRuntime.coreML.displayName, "Core ML")
        XCTAssertEqual(ModelRuntime.foundationModels.displayName, "Foundation Models")
    }
}
