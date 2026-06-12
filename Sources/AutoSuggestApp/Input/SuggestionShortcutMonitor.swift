import Foundation

enum SuggestionCommand {
    case accept
    case dismiss
}

@MainActor
protocol SuggestionShortcutMonitor {
    /// True when the event tap is installed and currently enabled.
    var isActive: Bool { get }
    func start(handler: @escaping (SuggestionCommand) -> Bool)
    func stop()
}
