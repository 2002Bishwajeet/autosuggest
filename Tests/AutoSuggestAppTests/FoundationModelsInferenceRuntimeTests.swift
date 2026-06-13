import XCTest
@testable import AutoSuggestApp

final class FoundationModelsInferenceRuntimeTests: XCTestCase {
    // MARK: - Mock seam

    @MainActor
    private final class MockResponder: FoundationModelResponding {
        var isModelAvailable: Bool
        var result: Result<String, Error>
        private(set) var receivedPrompt: String?
        private(set) var receivedMaxTokens: Int?
        private(set) var callCount = 0

        init(isModelAvailable: Bool = true, result: Result<String, Error> = .success("")) {
            self.isModelAvailable = isModelAvailable
            self.result = result
        }

        func respond(toPrompt prompt: String, maxTokens: Int) async throws -> String {
            callCount += 1
            receivedPrompt = prompt
            receivedMaxTokens = maxTokens
            return try result.get()
        }
    }

    private enum MockError: Error {
        case refusal
    }

    // MARK: - Naming

    @MainActor
    func testRuntimeNameIsFoundationModels() {
        let runtime = FoundationModelsInferenceRuntime(responder: MockResponder())
        XCTAssertEqual(runtime.name, "foundationmodels")
    }

    // MARK: - isAvailable per availability state

    @MainActor
    func testIsAvailableTrueWhenModelAvailable() async {
        let runtime = FoundationModelsInferenceRuntime(
            responder: MockResponder(isModelAvailable: true)
        )
        let available = await runtime.isAvailable()
        XCTAssertTrue(available)
    }

    @MainActor
    func testIsAvailableFalseWhenModelUnavailable() async {
        let runtime = FoundationModelsInferenceRuntime(
            responder: MockResponder(isModelAvailable: false)
        )
        let available = await runtime.isAvailable()
        XCTAssertFalse(available)
    }

    // MARK: - Success path

    @MainActor
    func testReturnsCompletionOnSuccess() async throws {
        let runtime = FoundationModelsInferenceRuntime(
            responder: MockResponder(result: .success(" world"))
        )
        let suggestion = try await runtime.generateSuggestion(context: "hello")
        XCTAssertEqual(suggestion.completion, " world")
        XCTAssertGreaterThan(suggestion.confidence, 0)
    }

    // MARK: - Error → empty mapping

    @MainActor
    func testReturnsEmptyOnError() async throws {
        let runtime = FoundationModelsInferenceRuntime(
            responder: MockResponder(result: .failure(MockError.refusal))
        )
        let suggestion = try await runtime.generateSuggestion(context: "hello")
        XCTAssertEqual(suggestion.completion, "")
        XCTAssertEqual(suggestion.confidence, 0)
    }

    @MainActor
    func testReturnsEmptyWhenModelReturnsWhitespaceOnly() async throws {
        let runtime = FoundationModelsInferenceRuntime(
            responder: MockResponder(result: .success("   \n  "))
        )
        let suggestion = try await runtime.generateSuggestion(context: "hello")
        XCTAssertEqual(suggestion.completion, "")
        XCTAssertEqual(suggestion.confidence, 0)
    }

    // MARK: - Token cap

    @MainActor
    func testPassesTokenCapToResponder() async throws {
        let responder = MockResponder(result: .success("x"))
        let runtime = FoundationModelsInferenceRuntime(responder: responder)
        _ = try await runtime.generateSuggestion(context: "hello")
        XCTAssertEqual(responder.receivedMaxTokens, FoundationModelsInferenceRuntime.maxResponseTokens)
        XCTAssertEqual(responder.receivedMaxTokens, 24)
    }

    // MARK: - Context truncation

    @MainActor
    func testTruncatesOverlongContextToPromptBudget() async throws {
        let responder = MockResponder(result: .success("x"))
        let runtime = FoundationModelsInferenceRuntime(responder: responder)

        let budget = FoundationModelsInferenceRuntime.maxPromptCharacters
        let oversized = String(repeating: "a", count: budget + 500) + "TAIL"

        _ = try await runtime.generateSuggestion(context: oversized)

        let sent = try XCTUnwrap(responder.receivedPrompt)
        XCTAssertEqual(sent.count, budget, "Prompt must be capped at the char budget")
        // The trailing text (nearest the caret) must be preserved.
        XCTAssertTrue(sent.hasSuffix("TAIL"))
    }

    @MainActor
    func testDoesNotTruncateShortContext() {
        let short = "the quick brown fox"
        XCTAssertEqual(FoundationModelsInferenceRuntime.truncatedPrompt(short), short)
    }

    @MainActor
    func testEmptyContextReturnsEmptyWithoutCallingResponder() async throws {
        let responder = MockResponder(result: .success("should-not-be-used"))
        let runtime = FoundationModelsInferenceRuntime(responder: responder)
        let suggestion = try await runtime.generateSuggestion(context: "")
        XCTAssertEqual(suggestion.completion, "")
        XCTAssertEqual(responder.callCount, 0, "Should short-circuit empty context")
    }
}
