import XCTest
@testable import AutoSuggestApp

final class InferenceEngineTests: XCTestCase {
    @MainActor
    func testUsesFirstAvailableRuntimeThatReturnsCompletion() async throws {
        let engine = InferenceEngine(
            runtimes: [
                TestRuntime(name: "coreml", available: true, behavior: .success("from-coreml")),
                TestRuntime(name: "ollama", available: true, behavior: .success("from-ollama")),
            ]
        )

        let suggestion = try await engine.suggest(for: "hello")
        XCTAssertEqual(suggestion.completion, "from-coreml")
    }

    @MainActor
    func testFallsBackWhenEarlierRuntimeUnavailable() async throws {
        let engine = InferenceEngine(
            runtimes: [
                TestRuntime(name: "coreml", available: false, behavior: .success("unused")),
                TestRuntime(name: "ollama", available: true, behavior: .success("from-ollama")),
            ]
        )

        let suggestion = try await engine.suggest(for: "hello")
        XCTAssertEqual(suggestion.completion, "from-ollama")
    }

    @MainActor
    func testFallsBackWhenEarlierRuntimeThrows() async throws {
        let engine = InferenceEngine(
            runtimes: [
                TestRuntime(name: "coreml", available: true, behavior: .failure(TestError.failed)),
                TestRuntime(name: "llama.cpp", available: true, behavior: .success("from-llama")),
            ]
        )

        let suggestion = try await engine.suggest(for: "hello")
        XCTAssertEqual(suggestion.completion, "from-llama")
    }

    @MainActor
    func testThrowsRuntimeUnavailableWhenAllRuntimesUnavailable() async {
        let engine = InferenceEngine(
            runtimes: [
                TestRuntime(name: "coreml", available: false, behavior: .success("unused")),
                TestRuntime(name: "ollama", available: false, behavior: .success("unused")),
            ]
        )

        do {
            _ = try await engine.suggest(for: "hello")
            XCTFail("Expected runtimeUnavailable error")
        } catch let InferenceError.runtimeUnavailable(message) {
            XCTAssertFalse(message.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private enum TestError: Error {
    case failed
}

private struct TestRuntime: InferenceRuntime {
    enum Behavior {
        case success(String)
        case failure(Error)
    }

    let name: String
    let available: Bool
    let behavior: Behavior

    func isAvailable() -> Bool {
        available
    }

    func generateSuggestion(context: String) async throws -> Suggestion {
        switch behavior {
        case let .success(text):
            return Suggestion(completion: text, confidence: 0.5)
        case let .failure(error):
            throw error
        }
    }
}
