import AppKit
import SwiftUI

struct AccessibilitySettingsView: View {
    @ObservedObject var uiModel: AutoSuggestUIModel

    var body: some View {
        SimplePanel {
            Text("VoiceOver announcements")
                .font(.headline)
            Text("Suggestions are announced once and stay keyboard-first.")
                .foregroundStyle(.secondary)
            Text(
                "Reduce Transparency: \(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? "Enabled" : "Disabled")"
            )
            Text(
                "Increase Contrast: \(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? "Enabled" : "Disabled")"
            )
            Button("Preview VoiceOver Announcement") {
                uiModel.previewAnnouncement()
            }
        }
    }
}
