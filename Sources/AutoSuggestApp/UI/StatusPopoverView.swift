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
                SimplePanel {
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

            VStack(spacing: 6) {
                QuickActionButton(title: "Open Settings", systemImage: "gearshape") {
                    uiModel.openSettings(.general)
                }
                .accessibilityHint("Opens the settings window")
                Divider().padding(.horizontal, 8)
                QuickActionButton(title: "Pause for 1 Hour", systemImage: "pause.circle") {
                    uiModel.pauseForHour()
                }
                .accessibilityHint("Pauses suggestions for one hour")
                QuickActionButton(title: "Exclude Current App", systemImage: "minus.circle") {
                    uiModel.excludeFrontmostApp()
                }
                .accessibilityHint("Adds the frontmost app to the exclusion list")
                if uiModel.modelHealth.lastError != nil {
                    QuickActionButton(title: "Retry Model", systemImage: "arrow.clockwise") {
                        uiModel.retryModel()
                    }
                    .accessibilityHint("Retries loading the inference model")
                }
                if uiModel.canCheckForUpdates {
                    QuickActionButton(title: "Check for Updates…", systemImage: "arrow.down.circle") {
                        uiModel.checkForUpdates()
                    }
                    .accessibilityHint("Checks for a new version of AutoSuggest")
                }
                Divider().padding(.horizontal, 8)
                QuickActionButton(title: "Quit AutoSuggest", systemImage: "xmark.circle") {
                    uiModel.quitApp()
                }
                .accessibilityHint("Quits the application")
            }
        }
        .padding(16)
        .frame(width: 368)
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

private struct QuickActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AutoSuggestTheme.radiusSmall, style: .continuous)
                    .fill(isHovered
                        ? Color.primary.opacity(0.08)
                        : AutoSuggestTheme.surfaceSecondary)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
        .accessibilityLabel(title)
    }
}
