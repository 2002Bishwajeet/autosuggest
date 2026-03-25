import Foundation

enum SuggestionCommand {
    case accept
    case dismiss
}

@MainActor
protocol SuggestionShortcutMonitor {
    func start(handler: @escaping (SuggestionCommand) -> Bool)
    func stop()
}
