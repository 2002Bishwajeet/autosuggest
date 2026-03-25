import Foundation

struct MetricsSnapshot {
    let suggestionsShown: Int
    let suggestionsAccepted: Int
    let suggestionsDismissed: Int
    let suggestionErrors: Int
    let insertionFailures: Int
    let avgLatencyMs: Double
}

actor MetricsCollector {
    private var suggestionsShown = 0
    private var suggestionsAccepted = 0
    private var suggestionsDismissed = 0
    private var suggestionErrors = 0
    private var insertionFailures = 0
    private var latencySamplesMs: [Double] = []
    private let maxLatencySamples = 200

    func recordSuggestionShown(latencyMs: Double?) {
        suggestionsShown += 1
        if let latencyMs {
            latencySamplesMs.append(latencyMs)
            if latencySamplesMs.count > maxLatencySamples {
                latencySamplesMs.removeFirst(latencySamplesMs.count - maxLatencySamples)
            }
        }
    }

    func recordSuggestionAccepted() {
        suggestionsAccepted += 1
    }

    func recordSuggestionDismissed() {
        suggestionsDismissed += 1
    }

    func recordSuggestionError() {
        suggestionErrors += 1
    }

    func recordInsertionFailure() {
        insertionFailures += 1
    }

    func snapshot() -> MetricsSnapshot {
        let avgLatencyMs = latencySamplesMs.isEmpty
            ? 0
            : latencySamplesMs.reduce(0, +) / Double(latencySamplesMs.count)
        return MetricsSnapshot(
            suggestionsShown: suggestionsShown,
            suggestionsAccepted: suggestionsAccepted,
            suggestionsDismissed: suggestionsDismissed,
            suggestionErrors: suggestionErrors,
            insertionFailures: insertionFailures,
            avgLatencyMs: avgLatencyMs
        )
    }
}
