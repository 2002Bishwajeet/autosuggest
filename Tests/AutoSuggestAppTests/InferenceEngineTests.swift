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
    func testAvailabilityIsCachedWithinTTL() async throws {
        let counter = AvailabilityCounter()
        let engine = InferenceEngine(
            runtimes: [
                CountingRuntime(name: "coreml", available: true, counter: counter, behavior: .success("from-coreml")),
            ]
        )

        _ = try await engine.suggest(for: "hello")
        _ = try await engine.suggest(for: "world")

        XCTAssertEqual(counter.count, 1, "isAvailable() should be cached within the TTL across calls")
    }

    @MainActor
    func testInvalidateAvailabilityCacheForcesRecheck() async throws {
        let counter = AvailabilityCounter()
        let engine = InferenceEngine(
            runtimes: [
                CountingRuntime(name: "coreml", available: true, counter: counter, behavior: .success("from-coreml")),
            ]
        )

        _ = try await engine.suggest(for: "hello")
        engine.invalidateAvailabilityCache()
        _ = try await engine.suggest(for: "world")

        XCTAssertEqual(counter.count, 2, "isAvailable() should be re-checked after cache invalidation")
    }

    @MainActor
    func testUnavailableRuntimeSkippedInFavorOfAvailable() async throws {
        let engine = InferenceEngine(
            runtimes: [
                TestRuntime(name: "coreml", available: false, behavior: .success("from-coreml")),
                TestRuntime(name: "ollama", available: true, behavior: .success("from-ollama")),
            ]
        )

        let suggestion = try await engine.suggest(for: "hello")
        XCTAssertEqual(suggestion.completion, "from-ollama")
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

    func isAvailable() async -> Bool {
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

@MainActor
private final class AvailabilityCounter {
    var count = 0
}

private struct CountingRuntime: InferenceRuntime {
    let name: String
    let available: Bool
    let counter: AvailabilityCounter
    let behavior: TestRuntime.Behavior

    func isAvailable() async -> Bool {
        counter.count += 1
        return available
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
