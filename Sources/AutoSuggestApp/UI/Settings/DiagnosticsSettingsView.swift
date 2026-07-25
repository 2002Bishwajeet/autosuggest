import AppKit
import SwiftUI

struct DiagnosticsSettingsView: View {
    @ObservedObject var uiModel: AutoSuggestUIModel

    var body: some View {
        Form {
            Section("Metrics") {
                metricRow("Suggestions shown", "\(uiModel.metrics.suggestionsShown)")
                metricRow("Accepted", "\(uiModel.metrics.suggestionsAccepted)")
                metricRow("Acceptance rate", uiModel.metrics.acceptanceRateText)
                metricRow(
                    "Average latency",
                    uiModel.metrics.avgLatencyMs > 0
                        ? "\(Int(uiModel.metrics.avgLatencyMs.rounded())) ms"
                        : "No samples"
                )
                if let error = uiModel.diagnostics.lastModelError {
                    Divider()
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(AutoSuggestTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("Support Report") {
                Text("Copy or export this content-free report when filing an issue.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text(uiModel.diagnostics.reportText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 240)
                HStack {
                    Button("Copy Report") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(uiModel.diagnostics.reportText, forType: .string)
                    }
                    Button("Export Diagnostics…") {
                        uiModel.exportDiagnostics()
                    }
                    .buttonStyle(.borderedProminent)
                }
                if let exportPath = uiModel.diagnostics.exportPath {
                    Text("Saved to \(exportPath)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(exportPath)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
