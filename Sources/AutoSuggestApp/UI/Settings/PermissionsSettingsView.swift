import AppKit
import SwiftUI

struct PermissionsSettingsView: View {
    @ObservedObject var uiModel: AutoSuggestUIModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if uiModel.needsRelaunchToEnable {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Finish enabling AutoSuggest").font(.callout.weight(.semibold))
                        Text("Input Monitoring was granted but needs a relaunch to take effect.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Relaunch") { uiModel.relaunchApp() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(12)
                .background(AutoSuggestTheme.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }

            // Accessibility row
            PermissionSettingsRow(
                systemImage: "accessibility",
                title: "Accessibility",
                description: "Required to read text context and insert completions into any text field.",
                granted: uiModel.permissionHealth.accessibilityTrusted,
                primaryLabel: "Show Prompt",
                secondaryLabel: "Open Settings",
                primaryAction: { uiModel.openAccessibilitySettings() },
                secondaryAction: { uiModel.openAccessibilitySettings() }
            )

            // Input Monitoring row
            PermissionSettingsRow(
                systemImage: "keyboard",
                title: "Input Monitoring",
                description: "Required to detect Tab, Enter, and Esc for accepting or dismissing suggestions. Needs a relaunch after granting.",
                granted: uiModel.permissionHealth.inputMonitoringTrusted,
                primaryLabel: "Register & Open",
                secondaryLabel: "Open Settings",
                primaryAction: { uiModel.openInputMonitoringSettings() },
                secondaryAction: { uiModel.openInputMonitoringSettings() }
            )

            // Relaunch / recheck controls
            HStack(spacing: 10) {
                Button("Recheck") {
                    uiModel.refreshPermissions()
                }
                .buttonStyle(.bordered)

                if !uiModel.permissionHealth.isReady {
                    Button("Relaunch Now") {
                        uiModel.relaunchApp()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            }

            SimplePanel {
                SectionHeader("Privacy & Telemetry", systemImage: "hand.raised")

                Toggle("PII filtering", isOn: Binding(
                    get: { uiModel.config.privacy.piiFilteringEnabled },
                    set: { _ in uiModel.updatePIIFiltering(!uiModel.config.privacy.piiFilteringEnabled) }
                ))
                Text("Strips emails, phone numbers, and card numbers from personalization data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Toggle("Local telemetry", isOn: Binding(
                    get: { uiModel.config.telemetry.enabled },
                    set: { _ in uiModel.updateTelemetryEnabled(!uiModel.config.telemetry.enabled) }
                ))

                Toggle("Local only export", isOn: Binding(
                    get: { uiModel.config.telemetry.localStoreOnly },
                    set: { _ in uiModel.updateTelemetryLocalOnly(!uiModel.config.telemetry.localStoreOnly) }
                ))
            }

            SimplePanel {
                SectionHeader("Training Data", systemImage: "doc.text")

                Toggle("Collect training data (opt-in)", isOn: Binding(
                    get: { uiModel.config.privacy.trainingDataCollectionEnabled },
                    set: { uiModel.onUpdateTrainingDataCollection?($0) }
                ))
                Text(
                    "When enabled, accepted suggestions are recorded locally for fine-tuning. PII is filtered automatically."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack {
                    Button("Export Training Data") {
                        uiModel.onExportTrainingData?()
                    }
                    .disabled(!uiModel.config.privacy.trainingDataCollectionEnabled)
                    Button("Clear Training Data") {
                        uiModel.onClearTrainingData?()
                    }
                    .disabled(!uiModel.config.privacy.trainingDataCollectionEnabled)
                }
            }
        }
    }
}

private struct PermissionSettingsRow: View {
    let systemImage: String
    let title: String
    let description: String
    let granted: Bool
    let primaryLabel: String
    let secondaryLabel: String
    let primaryAction: () -> Void
    let secondaryAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(granted ? Color.green.opacity(0.1) : Color.orange.opacity(0.09))
                    .frame(width: 40, height: 40)
                Image(systemName: granted ? "checkmark.shield.fill" : systemImage)
                    .font(.system(size: 18))
                    .foregroundStyle(granted ? .green : .orange)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    Text(granted ? "Granted" : "Required")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(granted ? Color.green.opacity(0.1) : Color.orange.opacity(0.1)))
                        .foregroundStyle(granted ? .green : .orange)
                }
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !granted {
                    HStack(spacing: 8) {
                        Button(primaryLabel, action: primaryAction)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        Button(secondaryLabel, action: secondaryAction)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(granted ? Color.green.opacity(0.18) : Color(nsColor: .separatorColor), lineWidth: 1)
                )
        )
    }
}
