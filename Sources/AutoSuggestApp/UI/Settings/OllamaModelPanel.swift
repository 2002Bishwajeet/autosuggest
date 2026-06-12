import SwiftUI

struct OllamaModelPanel: View {
    @ObservedObject var uiModel: AutoSuggestUIModel
    @State private var baseURLDraft: String = ""

    private var activeModel: String {
        uiModel.config.localModel.ollama.modelName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Endpoint + status
            SimplePanel {
                SectionHeader("Ollama endpoint", systemImage: "server.rack")
                HStack {
                    TextField("http://127.0.0.1:11434", text: $baseURLDraft)
                        .textFieldStyle(.roundedBorder)
                    Button("Apply") { uiModel.setOllamaBaseURL(baseURLDraft) }
                        .disabled(baseURLDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                HStack(spacing: 8) {
                    Circle()
                        .fill(uiModel.ollamaRunning ? Color.green : Color.secondary)
                        .frame(width: 8, height: 8)
                    Text(uiModel.ollamaRunning ? "Ollama is running" : "Ollama not reachable")
                        .font(.caption).foregroundStyle(.secondary)
                    if !uiModel.ollamaRunning {
                        Text("· start it with `ollama serve`").font(.caption).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button("Recheck") { uiModel.refreshOllama() }
                        .buttonStyle(.borderless).controlSize(.small)
                }
            }

            // Installed
            SimplePanel {
                SectionHeader("Installed models", systemImage: "cube")
                if uiModel.ollamaInstalled.isEmpty {
                    Text(uiModel.ollamaRunning ? "No models pulled yet — download one below."
                        : "Connect to Ollama to see installed models.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(uiModel.ollamaInstalled, id: \.name) { model in
                        HStack {
                            Text(model.name)
                            Text(sizeText(model.sizeBytes)).font(.caption).foregroundStyle(.tertiary)
                            Spacer()
                            if model.name == activeModel {
                                Label("Active", systemImage: "checkmark.circle.fill")
                                    .font(.caption).foregroundStyle(AutoSuggestTheme.brand)
                            } else {
                                Button("Use") { uiModel.setOllamaModel(model.name) }
                                    .buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
                }
            }

            // Suggested
            SimplePanel {
                SectionHeader("Suggested models", systemImage: "sparkles")
                ForEach(OllamaSuggestedModels.all) { suggestion in
                    suggestionRow(suggestion)
                    if suggestion.id != OllamaSuggestedModels.all.last?.id { Divider() }
                }
            }
        }
        .onAppear {
            baseURLDraft = uiModel.config.localModel.ollama.baseURL
            uiModel.refreshOllama()
        }
    }

    @ViewBuilder
    private func suggestionRow(_ s: OllamaSuggestedModel) -> some View {
        let installed = uiModel.ollamaInstalled.contains { $0.name == s.name }
        let pull = uiModel.ollamaPulls[s.name]
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.name).font(.body.monospaced())
                    Text(s.blurb).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(String(format: "%.2f GB", s.sizeGB)).font(.caption).foregroundStyle(.tertiary)
                if pull != nil {
                    ProgressView().controlSize(.small)
                } else if installed {
                    if s.name == activeModel {
                        Label("Active", systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(AutoSuggestTheme.brand)
                    } else {
                        Button("Use") { uiModel.setOllamaModel(s.name) }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                } else {
                    Button("Download") { uiModel.pullOllamaModel(s.name) }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                        .disabled(!uiModel.ollamaRunning)
                }
            }
            if let pull {
                ProgressView(value: pull.fraction)
                Text(pull.total > 0
                    ? "\(sizeText(pull.completed)) / \(sizeText(pull.total)) — \(pull.status)"
                    : pull.status)
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
