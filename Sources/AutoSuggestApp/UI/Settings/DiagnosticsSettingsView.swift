import AppKit
import SwiftUI

struct DiagnosticsSettingsView: View {
    @ObservedObject var uiModel: AutoSuggestUIModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SimplePanel {
                Text("Metrics")
                    .font(.headline)
                Text("Shown: \(uiModel.metrics.suggestionsShown)")
                Text("Accepted: \(uiModel.metrics.suggestionsAccepted)")
                Text(
                    "Latency: \(uiModel.metrics.avgLatencyMs > 0 ? "\(Int(uiModel.metrics.avgLatencyMs.rounded())) ms" : "No samples")"
                )
                if let error = uiModel.diagnostics.lastModelError {
                    Text(error)
                        .foregroundStyle(.orange)
                }
            }

            SimplePanel {
                Text("Support report")
                    .font(.headline)
                TextEditor(text: .constant(uiModel.diagnostics.reportText))
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 260)
                HStack {
                    Button("Copy Report") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(uiModel.diagnostics.reportText, forType: .string)
                    }
                    Button("Export Diagnostics") {
                        uiModel.exportDiagnostics()
                    }
                }
                if let exportPath = uiModel.diagnostics.exportPath {
                    Text(exportPath)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
