import Foundation

struct PersonalizationRecord: Codable {
    var acceptedCompletions: [String: Int]
}

actor PersonalizationEngine {
    private let logger = Logger(scope: "PersonalizationEngine")
    private let store: EncryptedFileStore
    private let piiFilter = PIIFilter()
    private let fileName = "personalization.json.enc"
    private var cache: PersonalizationRecord?

    init(store: EncryptedFileStore) {
        self.store = store
    }

    func recordAcceptedSuggestion(_ completion: String) async {
        var state = await loadState()
        let sanitized = piiFilter.sanitize(completion)
        let key = normalizeCompletion(sanitized)
        guard !key.isEmpty else { return }
        state.acceptedCompletions[key, default: 0] += 1
        cache = state
        await store.save(state, to: fileName)
    }

    func bestMatch(for context: String) async -> String? {
        let state = await loadState()
        let lowerContext = context.lowercased()
        let candidates = state.acceptedCompletions
            .filter { completion, _ in
                let firstWord = completion.split(separator: " ").first.map(String.init)?.lowercased() ?? ""
                return firstWord.isEmpty || !lowerContext.hasSuffix(firstWord)
            }
            .sorted { $0.value > $1.value }
        return candidates.first?.key
    }

    private func loadState() async -> PersonalizationRecord {
        if let cache {
            return cache
        }
        if let existing = await store.load(PersonalizationRecord.self, from: fileName) {
            cache = existing
            return existing
        }
        let empty = PersonalizationRecord(acceptedCompletions: [:])
        cache = empty
        return empty
    }

    private func normalizeCompletion(_ completion: String) -> String {
        let trimmed = completion.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 120 {
            return String(trimmed.prefix(120))
        }
        return trimmed
    }
}
