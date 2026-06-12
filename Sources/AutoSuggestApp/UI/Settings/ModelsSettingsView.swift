import SwiftUI

struct ModelsSettingsView: View {
    @ObservedObject var uiModel: AutoSuggestUIModel

    @State private var isSourceEditorPresented = false
    @State private var sourceDraft = ModelSourceDraft(source: .default)
    @State private var showRollbackConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SimplePanel {
                Text("Current runtime: \(uiModel.modelHealth.activeRuntimeLabel)")
                Text("Current model: \(uiModel.modelHealth.activeModelLabel)")
                    .foregroundStyle(.secondary)
                Text(uiModel.modelHealth.menuSummary)
                    .foregroundStyle(.secondary)
            }

            SimplePanel {
                Text("Runtime order")
                    .font(.headline)
                ForEach(Array(uiModel.config.localModel.runtimeOrder.enumerated()), id: \.offset) { index, runtime in
                    HStack {
                        Text(runtime)
                        Spacer()
                        Button {
                            uiModel.moveRuntime(from: index, direction: -1)
                        } label: {
                            Image(systemName: "arrow.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == 0)

                        Button {
                            uiModel.moveRuntime(from: index, direction: 1)
                        } label: {
                            Image(systemName: "arrow.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == uiModel.config.localModel.runtimeOrder.count - 1)
                    }
                }
            }

            SimplePanel {
                HStack {
                    SectionHeader("Model source", systemImage: "arrow.down.circle")
                    Spacer()
                    Button("Configure Source…") {
                        sourceDraft = ModelSourceDraft(source: uiModel.config.localModel.customSource)
                        isSourceEditorPresented = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                if uiModel.modelHealth.isDownloading {
                    ProgressView("Downloading model…")
                }
                if let lastError = uiModel.modelHealth.lastError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(AutoSuggestTheme.warning)
                        Text(lastError)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Retry") { uiModel.retryModel() }
                            .buttonStyle(.bordered)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: AutoSuggestTheme.radiusSmall, style: .continuous)
                            .fill(AutoSuggestTheme.warning.opacity(0.1))
                    )
                }
            }

            SimplePanel {
                HStack {
                    SectionHeader("Installed models", systemImage: "cube")
                    Spacer()
                    Button("Rollback") {
                        showRollbackConfirmation = true
                    }
                    .disabled(uiModel.modelHealth.installedModels.isEmpty)
                    .confirmationDialog("Rollback to previous model?", isPresented: $showRollbackConfirmation) {
                        Button("Rollback", role: .destructive) {
                            uiModel.rollbackModel()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will switch back to the previously active model.")
                    }
                }

                if uiModel.modelHealth.installedModels.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "cube.transparent")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        Text("No installed models")
                            .foregroundStyle(.secondary)
                        Text("Configure a model source above or use the onboarding setup.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } else {
                    ForEach(uiModel.modelHealth.installedModels, id: \.path.path) { model in
                        HStack {
                            Text("\(model.id) \(model.version)")
                            Spacer()
                            Button("Use") {
                                uiModel.switchToInstalledModel(model)
                            }
                            .disabled(uiModel.modelHealth.activeModelPath?.path == model.path.path)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isSourceEditorPresented) {
            ModelSourceEditorView(sourceDraft: sourceDraft) { savedDraft in
                uiModel.saveModelSource(savedDraft)
            }
        }
    }
}

private struct ModelSourceEditorView: View {
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
            TextField("Version", text: $draft.version)
            TextField("SHA256 checksum", text: $draft.sha256)

            if draft.sourceType == .directURL {
                TextField("Direct URL", text: $draft.directURL)
            } else {
                TextField("Repo", text: $draft.huggingFaceRepoID)
                TextField("Revision", text: $draft.huggingFaceRevision)
                TextField("File Path", text: $draft.huggingFaceFilePath)
                SecureField("Optional token", text: $draft.huggingFaceToken)
            }

            if let message = draft.validationMessage() {
                Text(message)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save & Download") {
                    onSave(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.validationMessage() != nil)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}
