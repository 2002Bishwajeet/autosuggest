import Foundation

@MainActor
protocol TextInsertionEngine {
    func insertSuggestion(_ suggestion: String) -> Bool
}
