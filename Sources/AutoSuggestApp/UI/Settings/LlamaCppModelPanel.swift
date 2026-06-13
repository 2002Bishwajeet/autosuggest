import SwiftUI

struct LlamaCppModelPanel: View {
    @ObservedObject var uiModel: AutoSuggestUIModel
    @State private var baseURLDraft: String = ""

    var body: some View {
        SimplePanel {
            SectionHeader("llama.cpp endpoint", systemImage: "server.rack")
            HStack {
                TextField("http://127.0.0.1:8080", text: $baseURLDraft)
                    .textFieldStyle(.roundedBorder)
                Button("Apply") { uiModel.setLlamaCppBaseURL(baseURLDraft) }
                    .disabled(baseURLDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack(spacing: 8) {
                StatusDot(status: uiModel.llamaCppReachable ? .active : .inactive)
                Text(uiModel.llamaCppReachable ? "Reachable" : "Not reachable")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Test endpoint") { uiModel.refreshLlamaCpp() }
                    .buttonStyle(.borderless).controlSize(.small)
            }
            .accessibilityElement(children: .combine)
            Text("llama.cpp is a user-run server. Start it with `llama-server --port 8080`.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .onAppear {
            baseURLDraft = uiModel.config.localModel.llamaCpp.baseURL
            uiModel.refreshLlamaCpp()
        }
    }
}
