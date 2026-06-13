import SwiftUI

struct ModelsSettingsView: View {
    @ObservedObject var uiModel: AutoSuggestUIModel

    @State private var isSourceEditorPresented = false
    @State private var sourceDraft = ModelSourceDraft(source: .default)
    @State private var showRollbackConfirmation = false
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
            default:
                coreMLAndSourcePanels
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
        .sheet(isPresented: $isSourceEditorPresented) {
            ModelSourceEditorView(sourceDraft: sourceDraft) { savedDraft in
                uiModel.saveModelSource(savedDraft)
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

    private var coreMLAndSourcePanels: some View {
        VStack(alignment: .leading, spacing: 14) {
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
                        let isActive = uiModel.modelHealth.activeModelPath?.path == model.path.path
                        HStack {
                            Text("\(model.id) \(model.version)")
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help("\(model.id) \(model.version)")
                            Spacer(minLength: 8)
                            if isActive {
                                Label("In use", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(AutoSuggestTheme.brand)
                                    .labelStyle(.titleAndIcon)
                            } else {
                                Button("Use") {
                                    uiModel.switchToInstalledModel(model)
                                }
                            }
                        }
                    }
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
