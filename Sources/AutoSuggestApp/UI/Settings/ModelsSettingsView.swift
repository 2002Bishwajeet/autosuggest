import SwiftUI

struct ModelsSettingsView: View {
    @ObservedObject var uiModel: AutoSuggestUIModel

    @State private var selectedRuntime: ModelRuntime = .ollama

    var body: some View {
        Form {
            Section("Status") {
                Text("Current runtime: \(uiModel.modelHealth.activeRuntimeLabel)")
                Text("Current model: \(uiModel.modelHealth.activeModelLabel)").foregroundStyle(.secondary)
                Text(uiModel.modelHealth.menuSummary).foregroundStyle(.secondary)
            }

            Section("Runtime") {
                Picker("Runtime", selection: $selectedRuntime) {
                    ForEach(availableRuntimes) { rt in
                        Text(rt.displayName).tag(rt)
                    }
                }
                .pickerStyle(.menu)
            }

            runtimePanel

            Section("Fallback order") {
                fallbackOrderList
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if let first = availableRuntimes.first, !availableRuntimes.contains(selectedRuntime) {
                selectedRuntime = first
            }
        }
    }

    /// Runtimes present in the user's configured order, typed. Unknown strings are dropped.
    private var availableRuntimes: [ModelRuntime] {
        uiModel.config.localModel.runtimeOrder.compactMap(ModelRuntime.init(configValue:))
    }

    @ViewBuilder private var runtimePanel: some View {
        switch selectedRuntime {
        case .ollama:
            OllamaModelPanel(uiModel: uiModel)
        case .llamaCpp:
            LlamaCppModelPanel(uiModel: uiModel)
        case .coreML:
            CoreMLModelPanel(uiModel: uiModel)
        case .foundationModels:
            EmptyStateView(
                icon: "sparkles",
                title: "No setup needed",
                message: "Foundation Models runs on-device using Apple Intelligence and requires no configuration."
            )
        }
    }

    private var fallbackOrderList: some View {
        List {
            ForEach(uiModel.config.localModel.runtimeOrder, id: \.self) { runtime in
                Text(RuntimeDisplayName.label(for: runtime))
            }
            .onMove { indices, newOffset in
                guard let from = indices.first else { return }
                // Translate a SwiftUI move (from, insert-before newOffset) into the
                // model's step API. Move one position toward the destination per call
                // by using direction sign; for multi-step moves apply until placed.
                let to = newOffset > from ? newOffset - 1 : newOffset
                if to != from {
                    uiModel.moveRuntime(from: from, direction: to > from ? 1 : -1)
                }
            }
        }
        .frame(minHeight: 120)
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
