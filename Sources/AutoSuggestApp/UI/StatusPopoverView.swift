import AppKit
import SwiftUI

struct StatusPopoverView: View {
    @ObservedObject var uiModel: AutoSuggestUIModel

    private var statusIndicator: StatusDot.Status {
        if !uiModel.config.enabled { return .inactive }
        if uiModel.quickPanelState.pauseReason != nil { return .paused }
        if uiModel.modelHealth.lastError != nil { return .error }
        return .active
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let banner = uiModel.banner {
                BannerView(banner: banner, onDismiss: uiModel.dismissBanner)
            }

            HStack(spacing: 10) {
                StatusDot(status: statusIndicator)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AutoSuggest")
                        .font(.title3.weight(.semibold))
                    Text(uiModel.quickPanelState.statusHeadline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let pauseReason = uiModel.quickPanelState.pauseReason {
                SettingsSection {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(pauseReason, systemImage: "pause.circle")
                            .foregroundStyle(.secondary)
                        if let remedy = uiModel.quickPanelState.pauseRemedy {
                            Text(remedy)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            HStack {
                Text("Suggestions")
                Spacer()
                Toggle("Suggestions", isOn: Binding(
                    get: { uiModel.config.enabled },
                    set: { uiModel.toggleEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    statusRow("Runtime", value: uiModel.quickPanelState.activeRuntimeLabel)
                    statusRow("Model", value: uiModel.quickPanelState.activeModelLabel)
                    statusRow("Permissions", value: uiModel.permissionHealth.summary)
                    statusRow(
                        "Latency",
                        value: uiModel.metrics.avgLatencyMs > 0
                            ? "\(Int(uiModel.metrics.avgLatencyMs.rounded())) ms"
                            : "No samples"
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                SectionHeader("Status", systemImage: "chart.bar")
            }

            VStack(alignment: .leading, spacing: 4) {
                Button("Open Settings…") { uiModel.openSettings(.general) }
                    .accessibilityHint("Opens the settings window")
                Button("Pause for 1 Hour") { uiModel.pauseForHour() }
                    .accessibilityHint("Pauses suggestions for one hour")
                Button("Exclude Current App") { uiModel.excludeFrontmostApp() }
                    .accessibilityHint("Adds the frontmost app to the exclusion list")
                if uiModel.modelHealth.lastError != nil {
                    Button("Retry Model") { uiModel.retryModel() }
                        .accessibilityHint("Retries loading the inference model")
                }
                if uiModel.canCheckForUpdates {
                    Button("Check for Updates…") { uiModel.checkForUpdates() }
                        .accessibilityHint("Checks for a new version of AutoSuggest")
                }
                Divider()
                Button("About AutoSuggest") { uiModel.showAbout() }
                    .accessibilityHint("Shows app version and links")
                Button("Export Diagnostics…") { uiModel.exportDiagnostics() }
                    .accessibilityHint("Saves a diagnostics report to a file")
                Divider()
                Button("Quit AutoSuggest") { uiModel.quitApp() }
                    .accessibilityHint("Quits the application")
            }
            .buttonStyle(.link)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(minWidth: 300, maxWidth: 360, alignment: .leading)
        .autoSuggestTinted()
    }

    private func statusRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .truncationMode(.middle)
                .help(value)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
