import XCTest
@testable import AutoSuggestApp

/// #31 — shared prompt builder + output quality gate. Pure logic only.
final class CompletionPromptTests: XCTestCase {
    // MARK: - CompletionPrompt

    func testChatMessagesStartWithSystemAndEndWithUserContext() {
        let messages = CompletionPrompt.chatMessages(for: "Hey Sarah, are we still on for")
        XCTAssertEqual(messages.first?.role, "system")
        XCTAssertEqual(messages.last?.role, "user")
        XCTAssertEqual(messages.last?.content, "Hey Sarah, are we still on for")
    }

    func testChatMessagesIncludeFewShotPairsInOrder() {
        let messages = CompletionPrompt.chatMessages(for: "x")
        // system + N user/assistant pairs + final user turn.
        let middle = messages.dropFirst().dropLast()
        XCTAssertFalse(middle.isEmpty)
        var expected = "user"
        for message in middle {
            XCTAssertEqual(message.role, expected)
            expected = expected == "user" ? "assistant" : "user"
        }
        // Pairs must be complete: middle count is even.
        XCTAssertEqual(middle.count % 2, 0)
    }

    func testSystemPromptForbidsReplying() {
        let prompt = CompletionPrompt.systemPrompt.lowercased()
        XCTAssertTrue(prompt.contains("continuation"))
        XCTAssertTrue(prompt.contains("never answer") || prompt.contains("not respond"))
    }

    // MARK: - SuggestionQualityGate

    func testGateRejectsEchoOfContextTail() {
        XCTAssertTrue(SuggestionQualityGate.isGarbage("still on for", context: "Hey, are we still on for"))
        XCTAssertTrue(SuggestionQualityGate.isGarbage("Hey, are we still on for", context: "Hey, are we still on for"))
    }

    func testGateRejectsChattyReplyOpeners() {
        XCTAssertTrue(SuggestionQualityGate.isGarbage("Sure, here's the continuation:", context: "Hello"))
        XCTAssertTrue(SuggestionQualityGate.isGarbage("Of course! Lunch sounds great.", context: "are we on for lunch"))
        XCTAssertTrue(SuggestionQualityGate.isGarbage("As an AI, I cannot", context: "test"))
        XCTAssertTrue(SuggestionQualityGate.isGarbage("Here is your text", context: "test"))
    }

    func testGateRejectsQuoteAndMarkupWrappedOutput() {
        XCTAssertTrue(SuggestionQualityGate.isGarbage("\"lunch tomorrow\"", context: "are we on for"))
        XCTAssertTrue(SuggestionQualityGate.isGarbage("`lunch tomorrow`", context: "are we on for"))
        XCTAssertTrue(SuggestionQualityGate.isGarbage("**lunch tomorrow**", context: "are we on for"))
    }

    func testGateAcceptsPlainContinuations() {
        XCTAssertFalse(SuggestionQualityGate.isGarbage(" lunch tomorrow at noon?", context: "Hey, are we still on for"))
        XCTAssertFalse(SuggestionQualityGate.isGarbage("loyed later today.", context: "the fix will be dep"))
        // "I" openers are normal continuations, not chat replies.
        XCTAssertFalse(SuggestionQualityGate.isGarbage(" I think so.", context: "Will it work?"))
    }
}
