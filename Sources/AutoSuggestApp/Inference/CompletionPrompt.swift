import Foundation

/// Shared prompt for all inline-completion runtimes (#31).
///
/// One source of truth so Ollama's chat endpoint and FoundationModels'
/// session instructions steer the model the same way: continue the user's
/// text, never reply to it. Pure data — unit-testable without a model.
enum CompletionPrompt {
    struct ChatMessage: Codable, Equatable {
        let role: String
        let content: String
    }

    /// The task instruction. Register-matching and the "continue, never
    /// answer" rule are the two clauses that kill most garbage output.
    static let systemPrompt = """
    You are an inline autocomplete engine. The user message is text someone \
    is typing, cut off at the cursor. Output ONLY the continuation that should \
    come immediately after it.

    Rules:
    - Never answer, reply to, or comment on the text — you are finishing it, \
    not responding to it.
    - Match the text's language, tone, and formality exactly.
    - If the text ends mid-word, finish that word first.
    - Start with a space if the continuation begins a new word.
    - No quotes, no preamble, no explanations, no markdown.
    - Keep it short: a few words, at most one sentence.
    - If there is nothing useful to add, output nothing.
    """

    /// Few-shot pairs demonstrating continuation (including continuing a
    /// question rather than answering it — the most common failure mode).
    static let fewShotExamples: [(user: String, assistant: String)] = [
        ("Hey Sarah, are we still on for", " lunch tomorrow at noon?"),
        ("Thanks for your patience — the fix will be dep", "loyed later today."),
        ("Can you send me the report by", " end of day Friday?"),
    ]

    /// Full chat transcript for chat-style endpoints: system prompt,
    /// few-shot pairs, then the live context as the final user turn.
    static func chatMessages(for context: String) -> [ChatMessage] {
        var messages = [ChatMessage(role: "system", content: systemPrompt)]
        for example in fewShotExamples {
            messages.append(ChatMessage(role: "user", content: example.user))
            messages.append(ChatMessage(role: "assistant", content: example.assistant))
        }
        messages.append(ChatMessage(role: "user", content: context))
        return messages
    }
}

/// Rejects completions that are model chatter rather than continuations (#31).
/// Conservative on purpose: only patterns that are near-certainly garbage —
/// a false reject costs one suggestion, a false accept ships garbage.
enum SuggestionQualityGate {
    /// Chat-reply openers no legitimate continuation starts with.
    // ponytail: static substring list; grow it from real garbage sightings.
    private static let replyOpeners = [
        "sure,", "sure!", "certainly", "of course", "here is ", "here's ",
        "as an ai", "i'm sorry, i", "i apologize", "okay, here",
    ]

    /// Wrappers that mean the model quoted/formatted instead of continuing.
    private static let markupPrefixes = ["\"", "\u{201C}", "\u{201D}", "`", "**", "* ", "• ", "> ", "#"]

    static func isGarbage(_ completion: String, context: String) -> Bool {
        let trimmed = completion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let lowered = trimmed.lowercased()

        // Echo: the model repeated the end of the input instead of extending it.
        let contextTail = context.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !contextTail.isEmpty, contextTail.hasSuffix(lowered) {
            return true
        }

        if replyOpeners.contains(where: { lowered.hasPrefix($0) }) {
            return true
        }
        if markupPrefixes.contains(where: { trimmed.hasPrefix($0) }) {
            return true
        }
        return false
    }
}
