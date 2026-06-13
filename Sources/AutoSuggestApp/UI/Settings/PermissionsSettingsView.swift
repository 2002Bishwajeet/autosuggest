import AppKit
import SwiftUI

struct PermissionsSettingsView: View {
    @ObservedObject var uiModel: AutoSuggestUIModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if uiModel.needsRelaunchToEnable {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .foregroundStyle(AutoSuggestTheme.brand)
                        .accessibilityHidden(true)
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
                .background(
                    AutoSuggestTheme.brand.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: AutoSuggestTheme.radiusSmall, style: .continuous)
                )
            }

            // Accessibility row
            PermissionSettingsRow(
                systemImage: "accessibility",
                title: "Accessibility",
                description: "Lets AutoSuggest read the text around your cursor and insert completions into any text field.",
                granted: uiModel.permissionHealth.accessibilityTrusted,
                primaryLabel: "Open System Settings",
                primaryAction: { uiModel.openAccessibilitySettings() }
            )

            // Input Monitoring row
            PermissionSettingsRow(
                systemImage: "keyboard",
                title: "Input Monitoring",
                description: "Lets AutoSuggest detect Tab, Enter, and Esc so you can accept or dismiss suggestions. AutoSuggest must relaunch after you grant this.",
                granted: uiModel.permissionHealth.inputMonitoringTrusted,
                primaryLabel: "Open System Settings",
                primaryAction: { uiModel.openInputMonitoringSettings() }
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
                }
            }

            SimplePanel {
                SectionHeader("Privacy & Telemetry", systemImage: "hand.raised")

                Toggle("PII filtering", isOn: Binding(
                    get: { uiModel.config.privacy.piiFilteringEnabled },
                    set: { uiModel.updatePIIFiltering($0) }
                ))
                Text("Strips emails, phone numbers, and card numbers from personalization data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Toggle("Local telemetry", isOn: Binding(
                    get: { uiModel.config.telemetry.enabled },
                    set: { uiModel.updateTelemetryEnabled($0) }
                ))

                Toggle("Local-only export", isOn: Binding(
                    get: { uiModel.config.telemetry.localStoreOnly },
                    set: { uiModel.updateTelemetryLocalOnly($0) }
                ))
                Text("Keeps all telemetry on this Mac and never sends it anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SimplePanel {
                SectionHeader("Personalization", systemImage: "wand.and.stars")

                Toggle("Personalize suggestions", isOn: Binding(
                    get: { uiModel.config.privacy.personalizationEnabled },
                    set: { uiModel.updatePersonalization($0) }
                ))
                Text(
                    "AutoSuggest locally re-ranks suggestions from completions you've accepted. Stored encrypted on this device, never uploaded."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(
                    "\(uiModel.personalizationStats.total) accepted · \(uiModel.personalizationStats.unique) unique"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Button("Clear Personalization Data") {
                    uiModel.onClearPersonalization?()
                }
                .disabled(!uiModel.config.privacy.personalizationEnabled)
            }
            .onAppear { uiModel.onRefreshPersonalizationStats?() }

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
    let primaryAction: () -> Void

    private var accent: Color {
        granted ? AutoSuggestTheme.success : AutoSuggestTheme.warning
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: AutoSuggestTheme.radiusSmall, style: .continuous)
                    .fill(accent.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: granted ? "checkmark.shield.fill" : systemImage)
                    .font(.system(size: 18))
                    .foregroundStyle(accent)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    Text(granted ? "Granted" : "Required")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(accent.opacity(0.14)))
                        .foregroundStyle(accent)
                }
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !granted {
                    Button(primaryLabel, action: primaryAction)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .padding(.top, 2)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: AutoSuggestTheme.radiusMedium, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: AutoSuggestTheme.radiusMedium, style: .continuous)
                        .stroke(
                            granted ? AutoSuggestTheme.success.opacity(0.2) : Color(nsColor: .separatorColor),
                            lineWidth: 1
                        )
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(granted ? "Granted" : "Required"). \(description)")
    }
}
