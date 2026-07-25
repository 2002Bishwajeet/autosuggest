import AppKit
import SwiftUI

struct AccessibilitySettingsView: View {
    @ObservedObject var uiModel: AutoSuggestUIModel

    // Seeded from the current system state and refreshed live via the
    // accessibility-display-options notification, so the rows don't go stale if
    // the user flips the setting while this pane is open.
    @State private var reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    @State private var increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast

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
                settingRow("Reduce Transparency", on: reduceTransparency)
                settingRow("Increase Contrast", on: increaseContrast)
            }
        }
        .formStyle(.grouped)
        .onReceive(
            NSWorkspace.shared.notificationCenter
                .publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
        ) { _ in
            reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
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
