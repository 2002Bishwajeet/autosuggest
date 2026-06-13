import AppKit
import SwiftUI

struct AccessibilitySettingsView: View {
    @ObservedObject var uiModel: AutoSuggestUIModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SimplePanel {
                SectionHeader("VoiceOver announcements", systemImage: "speaker.wave.2")
                Text("Suggestions are announced once and stay keyboard-first.")
                    .foregroundStyle(.secondary)
                Button("Preview VoiceOver Announcement") {
                    uiModel.previewAnnouncement()
                }
                .accessibilityHint("Plays a sample suggestion announcement")
            }

            SimplePanel {
                SectionHeader("System accessibility settings", systemImage: "eye")
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
