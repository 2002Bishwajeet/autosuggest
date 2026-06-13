import SwiftUI

struct ModelsSettingsView: View {
    @ObservedObject var uiModel: AutoSuggestUIModel

    @State private var selectedRuntimeTab: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SimplePanel {
                Text("Current runtime: \(uiModel.modelHealth.activeRuntimeLabel)")
                Text("Current model: \(uiModel.modelHealth.activeModelLabel)")
                    .foregroundStyle(.secondary)
                Text(uiModel.modelHealth.menuSummary)
                    .foregroundStyle(.secondary)
            }

            Picker("Runtime", selection: $selectedRuntimeTab) {
                ForEach(uiModel.config.localModel.runtimeOrder, id: \.self) { rt in
                    Text(RuntimeDisplayName.label(for: rt)).tag(rt)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch selectedRuntimeTab {
            case "ollama":
                OllamaModelPanel(uiModel: uiModel)
            case "llama.cpp", "llamacpp", "llama_cpp":
                LlamaCppModelPanel(uiModel: uiModel)
            default:
                CoreMLModelPanel(uiModel: uiModel)
            }

            DisclosureGroup("Fallback order") {
                runtimeOrderControls
            }
        }
        .onAppear {
            if selectedRuntimeTab.isEmpty {
                selectedRuntimeTab = uiModel.config.localModel.runtimeOrder.first ?? "ollama"
            }
        }
    }

    private var runtimeOrderControls: some View {
        SimplePanel {
            Text("Runtime order")
                .font(.headline)
            ForEach(Array(uiModel.config.localModel.runtimeOrder.enumerated()), id: \.offset) { index, runtime in
                HStack {
                    Text("\(index + 1).")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text(RuntimeDisplayName.label(for: runtime))
                    Spacer()
                    Button {
                        uiModel.moveRuntime(from: index, direction: -1)
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == 0)
                    .accessibilityLabel("Move \(RuntimeDisplayName.label(for: runtime)) up")

                    Button {
                        uiModel.moveRuntime(from: index, direction: 1)
                    } label: {
                        Image(systemName: "arrow.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == uiModel.config.localModel.runtimeOrder.count - 1)
                    .accessibilityLabel("Move \(RuntimeDisplayName.label(for: runtime)) down")
                }
            }
        }
    }
}

struct ModelSourceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ModelSourceDraft
    let onSave: (ModelSourceDraft) -> Void

    init(sourceDraft: ModelSourceDraft, onSave: @escaping (ModelSourceDraft) -> Void) {
        _draft = State(initialValue: sourceDraft)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Model Source")
                .font(.title3.weight(.semibold))
            Picker("Source", selection: $draft.sourceType) {
                Text("Direct URL").tag(LocalModelSourceType.directURL)
                Text("Hugging Face").tag(LocalModelSourceType.huggingFace)
            }
            .pickerStyle(.segmented)

            TextField("Model ID", text: $draft.modelID)
                .textFieldStyle(.roundedBorder)
            TextField("Version", text: $draft.version)
                .textFieldStyle(.roundedBorder)
            TextField("SHA256 checksum", text: $draft.sha256)
                .textFieldStyle(.roundedBorder)

            if draft.sourceType == .directURL {
                TextField("Direct URL", text: $draft.directURL)
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField("Repo", text: $draft.huggingFaceRepoID)
                    .textFieldStyle(.roundedBorder)
                TextField("Revision", text: $draft.huggingFaceRevision)
                    .textFieldStyle(.roundedBorder)
                TextField("File Path", text: $draft.huggingFaceFilePath)
                    .textFieldStyle(.roundedBorder)
                SecureField("Optional token", text: $draft.huggingFaceToken)
                    .textFieldStyle(.roundedBorder)
            }

            if let message = draft.validationMessage() {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(AutoSuggestTheme.warning)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save & Download") {
                    onSave(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(draft.validationMessage() != nil)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}
