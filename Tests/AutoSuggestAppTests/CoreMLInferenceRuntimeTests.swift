import Foundation
import XCTest
@testable import AutoSuggestApp

/// Verifies that the Core ML runtime surfaces DISTINCT, accurate errors:
/// "no model selected" must never be confused with "the model failed to load"
/// (the historical -1011), and neither may masquerade as "Ollama isn't running".
final class CoreMLInferenceRuntimeTests: XCTestCase {
    @MainActor
    private func makeRuntime(
        modelPath: URL?,
        generator: CoreMLModelGenerating
    ) -> CoreMLInferenceRuntime {
        CoreMLInferenceRuntime(
            session: StubPathProvider(path: modelPath),
            personalizationEngine: PersonalizationEngine(store: EncryptedFileStore()),
            modelAdapter: generator
        )
    }

    @MainActor
    func testNoActiveModelThrowsModelMissing() async {
        let runtime = makeRuntime(
            modelPath: nil,
            generator: StubGenerator(behavior: .returns("never reached"))
        )

        do {
            _ = try await runtime.generateSuggestion(context: "hello")
            XCTFail("Expected coreMLModelMissing")
        } catch InferenceError.coreMLModelMissing {
            // expected — no model selected is its own distinct state
        } catch {
            XCTFail("Expected coreMLModelMissing, got \(error)")
        }
    }

    @MainActor
    func testModelLoadFailureThrowsRuntimeFailureCarryingUnderlying() async {
        // A present-but-broken model (e.g. the historical NSURLErrorDomain -1011)
        // must surface as coreMLRuntimeFailure carrying the real error — not be
        // swallowed into a generic "no usable model" message.
        let underlying = NSError(domain: "NSURLErrorDomain", code: -1011, userInfo: nil)
        let runtime = makeRuntime(
            modelPath: URL(fileURLWithPath: "/tmp/model.mlpackage"),
            generator: StubGenerator(behavior: .throws(underlying))
        )

        do {
            _ = try await runtime.generateSuggestion(context: "hello")
            XCTFail("Expected coreMLRuntimeFailure")
        } catch let InferenceError.coreMLRuntimeFailure(carried) {
            let nsError = carried as NSError
            XCTAssertEqual(nsError.code, -1011)
        } catch {
            XCTFail("Expected coreMLRuntimeFailure, got \(error)")
        }
    }

    @MainActor
    func testSuccessfulGenerationReturnsCompletion() async throws {
        let runtime = makeRuntime(
            modelPath: URL(fileURLWithPath: "/tmp/model.mlpackage"),
            generator: StubGenerator(behavior: .returns("world"))
        )

        let suggestion = try await runtime.generateSuggestion(context: "hello ")
        XCTAssertEqual(suggestion.completion, "world")
    }

    @MainActor
    func testEmptyGenerationDoesNotThrow() async throws {
        // An empty completion is NOT an error: the engine treats an empty
        // suggestion as "try the next runtime", so a present model that produces
        // nothing must return cleanly rather than throwing a runtime failure.
        let runtime = makeRuntime(
            modelPath: URL(fileURLWithPath: "/tmp/model.mlpackage"),
            generator: StubGenerator(behavior: .returns(""))
        )

        // Must not throw .coreMLRuntimeFailure / .coreMLModelMissing — the exact
        // value depends on whether a personalization hint exists, which is not
        // what this test pins down.
        _ = try await runtime.generateSuggestion(context: "hello")
    }

    @MainActor
    func testModelMissingAndRuntimeFailureMessagesAreDistinct() {
        let missing = InferenceError.coreMLModelMissing.errorDescription ?? ""
        let underlying = NSError(domain: "NSURLErrorDomain", code: -1011, userInfo: nil)
        let failure = InferenceError.coreMLRuntimeFailure(underlying: underlying).errorDescription ?? ""

        XCTAssertNotEqual(missing, failure)
        XCTAssertTrue(missing.lowercased().contains("no core ml model"))
        XCTAssertTrue(failure.lowercased().contains("failed to load"))
        // A Core ML failure must not point the user at Ollama's "serve" command
        // as though that were the problem.
        XCTAssertFalse(missing.lowercased().contains("ollama serve"))
        XCTAssertFalse(failure.lowercased().contains("ollama serve"))
    }
}

// MARK: - Stubs

@MainActor
private struct StubPathProvider: CoreMLModelPathProviding {
    let path: URL?
    func withLoadedModel<T>(_ work: (URL?) -> T) -> T {
        work(path)
    }
}

@MainActor
private final class StubGenerator: CoreMLModelGenerating {
    enum Behavior {
        case returns(String?)
        case `throws`(Error)
    }

    let behavior: Behavior
    init(behavior: Behavior) {
        self.behavior = behavior
    }

    func loadTokenizerIfNeeded(modelURL _: URL, explicitTokenizerURL _: URL?) async {}

    func generate(prompt _: String, modelURL _: URL, maxNewTokens _: Int) throws -> String? {
        switch behavior {
        case let .returns(value):
            return value
        case let .throws(error):
            throw error
        }
    }
}
