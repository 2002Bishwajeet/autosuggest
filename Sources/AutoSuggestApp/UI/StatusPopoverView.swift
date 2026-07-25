import AppKit
import SwiftUI

public struct StatusPopoverView: View {
    @ObservedObject var uiModel: AutoSuggestUIModel

    public init(uiModel: AutoSuggestUIModel) {
        self.uiModel = uiModel
    }

    private var statusIndicator: StatusDot.Status {
        if !uiModel.config.enabled { return .inactive }
        if uiModel.quickPanelState.pauseReason != nil { return .paused }
        if uiModel.modelHealth.lastError != nil { return .error }
        return .active
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: AutoSuggestTheme.spacingSM) {
            if let banner = uiModel.banner {
                BannerView(banner: banner, onDismiss: uiModel.dismissBanner)
                    .padding(.horizontal, AutoSuggestTheme.spacingMD)
                    .padding(.top, AutoSuggestTheme.spacingMD)
            }

            header
                .padding(.horizontal, AutoSuggestTheme.spacingLG)
                .padding(.top, uiModel.banner == nil ? AutoSuggestTheme.spacingLG : AutoSuggestTheme.spacingSM)

            if let pauseReason = uiModel.quickPanelState.pauseReason {
                pauseCallout(reason: pauseReason, remedy: uiModel.quickPanelState.pauseRemedy)
                    .padding(.horizontal, AutoSuggestTheme.spacingMD)
            }

            infoBlock
                .padding(.horizontal, AutoSuggestTheme.spacingMD)

            sectionDivider

            actionRows
                .padding(.horizontal, AutoSuggestTheme.spacingSM)

            sectionDivider

            footerRows
                .padding(.horizontal, AutoSuggestTheme.spacingSM)
                .padding(.bottom, AutoSuggestTheme.spacingSM)
        }
        .frame(width: 300, alignment: .leading)
        .autoSuggestTinted()
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center, spacing: AutoSuggestTheme.spacingMD) {
            VStack(alignment: .leading, spacing: 3) {
                Text("AutoSuggest")
                    .font(.headline)
                HStack(spacing: 6) {
                    StatusDot(status: statusIndicator)
                    Text(uiModel.quickPanelState.statusHeadline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Toggle("Suggestions", isOn: Binding(
                get: { uiModel.config.enabled },
                set: { uiModel.toggleEnabled($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityLabel("Enable suggestions")
        }
    }

    private func pauseCallout(reason: String, remedy: String?) -> some View {
        VStack(alignment: .leading, spacing: AutoSuggestTheme.spacingXS) {
            Label(reason, systemImage: "pause.circle.fill")
                .font(.subheadline)
            if let remedy {
                Text(remedy)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AutoSuggestTheme.spacingSM + 2)
        .background(
            AutoSuggestTheme.warning.opacity(AutoSuggestTheme.badgeFillOpacity),
            in: RoundedRectangle(cornerRadius: AutoSuggestTheme.radiusSmall)
        )
    }

    private var infoBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            infoRow("Runtime", value: uiModel.quickPanelState.activeRuntimeLabel)
            infoRow("Model", value: uiModel.quickPanelState.activeModelLabel)
            infoRow("Permissions", value: uiModel.permissionHealth.summary)
            infoRow(
                "Latency",
                value: uiModel.metrics.avgLatencyMs > 0
                    ? "\(Int(uiModel.metrics.avgLatencyMs.rounded())) ms"
                    : "No samples"
            )
        }
        .padding(AutoSuggestTheme.spacingSM + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AutoSuggestTheme.surfaceSecondary.opacity(0.6),
            in: RoundedRectangle(cornerRadius: AutoSuggestTheme.radiusSmall)
        )
    }

    private var actionRows: some View {
        VStack(alignment: .leading, spacing: 1) {
            PopoverActionRow(title: "Settings…", systemImage: "gearshape") {
                uiModel.openSettings(.general)
            }
            .accessibilityHint("Opens the settings window")

            PopoverActionRow(title: "Pause for 1 Hour", systemImage: "pause.circle") {
                uiModel.pauseForHour()
            }
            .accessibilityHint("Pauses suggestions for one hour")

            PopoverActionRow(title: "Exclude Current App", systemImage: "hand.raised") {
                uiModel.excludeFrontmostApp()
            }
            .accessibilityHint("Adds the frontmost app to the exclusion list")

            if uiModel.modelHealth.lastError != nil {
                PopoverActionRow(title: "Retry Model", systemImage: "arrow.clockwise") {
                    uiModel.retryModel()
                }
                .accessibilityHint("Retries loading the inference model")
            }

            if uiModel.canCheckForUpdates {
                PopoverActionRow(title: "Check for Updates…", systemImage: "arrow.down.circle") {
                    uiModel.checkForUpdates()
                }
                .accessibilityHint("Checks for a new version of AutoSuggest")
            }
        }
    }

    private var footerRows: some View {
        VStack(alignment: .leading, spacing: 1) {
            PopoverActionRow(title: "About AutoSuggest", systemImage: "info.circle") {
                uiModel.showAbout()
            }
            .accessibilityHint("Shows app version and links")

            PopoverActionRow(title: "Export Diagnostics…", systemImage: "doc.text") {
                uiModel.exportDiagnostics()
            }
            .accessibilityHint("Saves a diagnostics report to a file")

            PopoverActionRow(title: "Quit AutoSuggest", systemImage: "power") {
                uiModel.quitApp()
            }
            .accessibilityHint("Quits the application")
        }
    }

    private var sectionDivider: some View {
        Divider().padding(.horizontal, AutoSuggestTheme.spacingMD)
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: AutoSuggestTheme.spacingMD)
            Text(value)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .truncationMode(.middle)
                .help(value)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Menu-style action row

/// A popover row styled like a native menu item: SF Symbol, label, and a
/// rounded hover highlight — replaces the old `.link` (hyperlink) buttons.
struct PopoverActionRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: AutoSuggestTheme.spacingSM) {
                Image(systemName: systemImage)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(title)
                Spacer(minLength: 0)
            }
            .font(.body)
            .padding(.horizontal, AutoSuggestTheme.spacingSM)
            .padding(.vertical, 5)
            .contentShape(RoundedRectangle(cornerRadius: AutoSuggestTheme.radiusExtraSmall))
        }
        .buttonStyle(.plain)
        .background(
            isHovered ? Color.primary.opacity(0.08) : .clear,
            in: RoundedRectangle(cornerRadius: AutoSuggestTheme.radiusExtraSmall)
        )
        .onHover { isHovered = $0 }
    }
}
