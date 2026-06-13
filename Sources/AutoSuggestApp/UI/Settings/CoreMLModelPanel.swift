import SwiftUI

struct CoreMLModelPanel: View {
    @ObservedObject var uiModel: AutoSuggestUIModel

    @State private var isSourceEditorPresented = false
    @State private var sourceDraft = ModelSourceDraft(source: .default)
    @State private var showRollbackConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Model source
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

            // Installed models
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
                                Label("Active", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(AutoSuggestTheme.brand)
                                    .labelStyle(.titleAndIcon)
                            } else {
                                Button("Use") {
                                    uiModel.switchToInstalledModel(model)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
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
