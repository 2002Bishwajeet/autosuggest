import AppKit
import SwiftUI

struct PermissionsSettingsView: View {
    @ObservedObject var uiModel: AutoSuggestUIModel

    var body: some View {
        Form {
            if uiModel.needsRelaunchToEnable {
                Section {
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
                    .padding(AutoSuggestTheme.spacingMD)
                    .background(
                        AutoSuggestTheme.brand.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: AutoSuggestTheme.radiusSmall, style: .continuous)
                    )
                }
            }

            Section("Permissions") {
                PermissionsChecklist(
                    context: .settings,
                    accessibilityGranted: uiModel.permissionHealth.accessibilityTrusted,
                    inputMonitoringGranted: uiModel.permissionHealth.inputMonitoringTrusted,
                    actions: PermissionsChecklistActions(
                        requestAccessibility: { uiModel.openAccessibilitySettings() },
                        openAccessibilitySettings: { uiModel.openAccessibilitySettings() },
                        requestInputMonitoring: { uiModel.openInputMonitoringSettings() },
                        openInputMonitoringSettings: { uiModel.openInputMonitoringSettings() }
                    )
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
            }

            Section("Privacy & Telemetry") {
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

            Section("Personalization") {
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

            Section("Training Data") {
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
        .formStyle(.grouped)
    }
}
