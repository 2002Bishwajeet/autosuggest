import AppKit
import Foundation

@MainActor
final class AccessibilityAnnouncer {
    func announceSuggestion(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let app = NSApp else { return }
        let info: [NSAccessibility.NotificationUserInfoKey: Any] = [
            .announcement: "Suggestion: \(trimmed)",
            .priority: NSAccessibilityPriorityLevel.medium.rawValue,
        ]
        NSAccessibility.post(element: app, notification: .announcementRequested, userInfo: info)
    }
}
