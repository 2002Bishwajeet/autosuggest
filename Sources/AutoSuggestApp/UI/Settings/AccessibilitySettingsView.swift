import AppKit
import SwiftUI

struct AccessibilitySettingsView: View {
    @ObservedObject var uiModel: AutoSuggestUIModel

    var body: some View {
        Form {
            Section("VoiceOver announcements") {
                Text("Suggestions are announced once and stay keyboard-first.")
                    .foregroundStyle(.secondary)
                Button("Preview VoiceOver Announcement") {
                    uiModel.previewAnnouncement()
                }
                .accessibilityHint("Plays a sample suggestion announcement")
            }

            Section("System accessibility") {
                Text("AutoSuggest follows these macOS preferences automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                settingRow(
                    "Reduce Transparency",
                    on: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
                )
                settingRow(
                    "Increase Contrast",
                    on: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
                )
            }
        }
        .formStyle(.grouped)
    }

    private func settingRow(_ title: String, on: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(on ? "On" : "Off")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(on ? "On" : "Off")")
    }
}
