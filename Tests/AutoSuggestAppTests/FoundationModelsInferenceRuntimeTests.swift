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
        private(set) var prewarmCallCount = 0

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

        func prewarm() {
            prewarmCallCount += 1
        }
    }

    /// A responder that does NOT override `prewarm()`, exercising the protocol's
    /// default no-op extension (mocks/tests must not break when prewarm is added).
    @MainActor
    private final class NoPrewarmResponder: FoundationModelResponding {
        var isModelAvailable = true
        func respond(toPrompt _: String, maxTokens _: Int) async throws -> String {
            ""
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

    // MARK: - inlineTrimmed (Tweak 1: trim completions for inline display)

    func testInlineTrimmedKeepsOnlyFirstLine() {
        let multiline = "first line\nsecond line\nthird"
        XCTAssertEqual(FoundationModelsInferenceRuntime.inlineTrimmed(multiline), "first line")
    }

    func testInlineTrimmedHandlesCarriageReturnNewlines() {
        let multiline = "first line\r\nsecond line"
        XCTAssertEqual(FoundationModelsInferenceRuntime.inlineTrimmed(multiline), "first line")
    }

    func testInlineTrimmedCutsLongLineAtFirstSentenceTerminator() {
        // A single long line (> 80 chars) with multiple sentences → cut at the
        // first terminator, keeping the punctuation.
        let long = "This is the first sentence. And here is a much longer second sentence that pushes the whole thing past eighty characters."
        XCTAssertGreaterThan(long.count, 80)
        XCTAssertEqual(
            FoundationModelsInferenceRuntime.inlineTrimmed(long),
            "This is the first sentence."
        )
    }

    func testInlineTrimmedCutsLongLineAtQuestionMark() {
        let long = "Are you sure about this whole thing? Because there is a lot more that follows after the question here."
        XCTAssertGreaterThan(long.count, 80)
        XCTAssertEqual(
            FoundationModelsInferenceRuntime.inlineTrimmed(long),
            "Are you sure about this whole thing?"
        )
    }

    func testInlineTrimmedLeavesShortLineUnchangedEvenWithSentenceTerminator() {
        // Under the 80-char threshold → no sentence cut, returned as-is.
        let short = "Hi there. More."
        XCTAssertLessThanOrEqual(short.count, 80)
        XCTAssertEqual(FoundationModelsInferenceRuntime.inlineTrimmed(short), "Hi there. More.")
    }

    func testInlineTrimmedLeavesLongSingleSentenceUnchanged() {
        // Long, but no internal sentence terminator → returned as-is (modulo the
        // trailing whitespace that is always dropped).
        let long = String(repeating: "word ", count: 30).trimmingCharacters(in: .whitespaces)
        XCTAssertGreaterThan(long.count, 80)
        XCTAssertEqual(FoundationModelsInferenceRuntime.inlineTrimmed(long), long)
    }

    func testInlineTrimmedEmptyStaysEmpty() {
        XCTAssertEqual(FoundationModelsInferenceRuntime.inlineTrimmed(""), "")
    }

    func testInlineTrimmedDropsTrailingWhitespaceButKeepsLeadingSpace() {
        // Leading space is preserved (inline continuations often need it); only
        // trailing whitespace and anything past the first newline are dropped.
        let value = " the completion  \nignored"
        XCTAssertEqual(FoundationModelsInferenceRuntime.inlineTrimmed(value), " the completion")
    }

    func testInlineTrimmedPreservesLeadingSpaceContinuation() {
        // The classic " world" continuation after "hello" must survive intact.
        XCTAssertEqual(FoundationModelsInferenceRuntime.inlineTrimmed(" world"), " world")
    }

    @MainActor
    func testGenerateSuggestionAppliesInlineTrim() async throws {
        let responder = MockResponder(result: .success("first line\nsecond line"))
        let runtime = FoundationModelsInferenceRuntime(responder: responder)
        let suggestion = try await runtime.generateSuggestion(context: "hello")
        XCTAssertEqual(suggestion.completion, "first line")
        XCTAssertGreaterThan(suggestion.confidence, 0)
    }

    // MARK: - prewarm (Tweak 2: mask cold start)

    @MainActor
    func testPrewarmCallsThroughToResponder() {
        let responder = MockResponder()
        let runtime = FoundationModelsInferenceRuntime(responder: responder)
        runtime.prewarm()
        XCTAssertEqual(responder.prewarmCallCount, 1, "prewarm() must delegate to the responder")
    }

    @MainActor
    func testPrewarmWithDefaultNoOpResponderDoesNotCrash() {
        let runtime = FoundationModelsInferenceRuntime(responder: NoPrewarmResponder())
        runtime.prewarm() // protocol default no-op; must be safe.
    }
}
