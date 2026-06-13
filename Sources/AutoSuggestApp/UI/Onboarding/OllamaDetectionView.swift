import SwiftUI

struct OllamaDetectionView: View {
    @State private var status: OllamaStatus = .checking

    enum OllamaStatus {
        case checking
        case notInstalled
        case installedNotRunning
        case running
    }

    var body: some View {
        SettingsCard {
            HStack(spacing: 12) {
                switch status {
                case .checking:
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking Ollama status...")
                        .foregroundStyle(.secondary)
                case .notInstalled:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AutoSuggestTheme.error)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ollama not installed")
                            .font(.headline)
                        Text("Install with: brew install ollama")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                case .installedNotRunning:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AutoSuggestTheme.warning)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ollama installed but not running")
                            .font(.headline)
                        Text("Start with: ollama serve")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                case .running:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AutoSuggestTheme.success)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ollama is running")
                            .font(.headline)
                        Text("Ready to use for suggestions.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Recheck") {
                    Task { await refreshOllamaStatus() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .task {
            await refreshOllamaStatus()
        }
    }

    private func refreshOllamaStatus() async {
        status = .checking
        let result = await RuntimeDetectionService.live.status(for: .ollama)
        status = Self.mapStatus(result)
    }

    private static func mapStatus(_ status: RuntimeDetectionService.Status) -> OllamaStatus {
        switch status {
        case .notInstalled: .notInstalled
        case .installedNotRunning: .installedNotRunning
        case .running: .running
        }
    }
}
