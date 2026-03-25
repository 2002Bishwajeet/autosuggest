import AppKit
import SwiftUI

struct StatusPopoverView: View {
    @ObservedObject var uiModel: AutoSuggestUIModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let banner = uiModel.banner {
                    BannerView(banner: banner, onDismiss: uiModel.dismissBanner)
                }

                Text("AutoSuggest")
                    .font(.title3.weight(.semibold))
                Text(uiModel.quickPanelState.statusHeadline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let pauseReason = uiModel.quickPanelState.pauseReason {
                    SimplePanel {
                        Label(pauseReason, systemImage: "pause.circle")
                            .foregroundStyle(.secondary)
                    }
                }

                Button(uiModel.config.enabled ? "Disable AutoSuggest" : "Enable AutoSuggest") {
                    uiModel.toggleEnabled(!uiModel.config.enabled)
                }
                .buttonStyle(.borderedProminent)

                GroupBox("Status") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Runtime: \(uiModel.quickPanelState.activeRuntimeLabel)")
                        Text("Model: \(uiModel.quickPanelState.activeModelLabel)")
                        Text("Permissions: \(uiModel.permissionHealth.summary)")
                        Text(uiModel.metrics.avgLatencyMs > 0 ? "Latency: \(Int(uiModel.metrics.avgLatencyMs.rounded())) ms" : "Latency: No samples")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(spacing: 8) {
                    QuickActionButton(title: "Open Settings", systemImage: "gearshape") {
                        uiModel.openSettings(.general)
                    }
                    QuickActionButton(title: "Pause for 1 Hour", systemImage: "pause.circle") {
                        uiModel.pauseForHour()
                    }
                    QuickActionButton(title: "Exclude Current App", systemImage: "minus.circle") {
                        uiModel.excludeFrontmostApp()
                    }
                    QuickActionButton(title: "Retry Model", systemImage: "arrow.clockwise") {
                        uiModel.retryModel()
                    }
                    QuickActionButton(title: "Export Diagnostics", systemImage: "square.and.arrow.up") {
                        uiModel.exportDiagnostics()
                    }
                    QuickActionButton(title: "Quit AutoSuggest", systemImage: "xmark.circle") {
                        uiModel.quitApp()
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 368)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct QuickActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
    }
}

struct SettingsRootView: View {
    @ObservedObject var uiModel: AutoSuggestUIModel

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(SettingsRoute.allCases) { route in
                        Button {
                            uiModel.selectedSettingsRoute = route
                        } label: {
                            HStack {
                                Image(systemName: route.systemImage)
                                Text(route.title)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(route == uiModel.selectedSettingsRoute ? Color(nsColor: .selectedContentBackgroundColor) : .clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(16)
            .frame(width: 230, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let banner = uiModel.banner {
                        BannerView(banner: banner, onDismiss: uiModel.dismissBanner)
                    }
                    SettingsDetailContent(route: uiModel.selectedSettingsRoute, uiModel: uiModel)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SettingsDetailContent: View {
    let route: SettingsRoute
    @ObservedObject var uiModel: AutoSuggestUIModel

    @State private var isSourceEditorPresented = false
    @State private var sourceDraft = ModelSourceDraft(source: .default)
    @State private var searchText = ""
    @State private var isRuleEditorPresented = false
    @State private var ruleDraft = ExclusionRuleDraft()
    @State private var editingRule: ExclusionRule?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(route.title)
                .font(.title2.weight(.semibold))

            switch route {
            case .general:
                generalSection
            case .models:
                modelsSection
            case .permissionsPrivacy:
                permissionsSection
            case .exclusions:
                exclusionsSection
            case .accessibility:
                accessibilitySection
            case .diagnostics:
                diagnosticsSection
            }
        }
        .sheet(isPresented: $isSourceEditorPresented) {
            ModelSourceEditorView(sourceDraft: sourceDraft) { savedDraft in
                uiModel.saveModelSource(savedDraft)
            }
        }
        .sheet(isPresented: $isRuleEditorPresented) {
            ExclusionRuleEditorView(draft: ruleDraft) { savedDraft in
                uiModel.saveExclusionRule(savedDraft, originalRule: editingRule)
            }
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SimplePanel {
                Button(uiModel.config.enabled ? "Turn AutoSuggest Off" : "Turn AutoSuggest On") {
                    uiModel.toggleEnabled(!uiModel.config.enabled)
                }
                .buttonStyle(.borderedProminent)

                HStack {
                    Text("Battery behavior")
                    Spacer()
                    Button("Always On") {
                        uiModel.updateBatteryMode(.alwaysOn)
                    }
                    .disabled(uiModel.config.battery.mode == .alwaysOn)
                    Button("Pause on Low Power") {
                        uiModel.updateBatteryMode(.pauseOnLowPower)
                    }
                    .disabled(uiModel.config.battery.mode == .pauseOnLowPower)
                }

                HStack {
                    Text("Strict undo semantics")
                    Spacer()
                    Button(uiModel.config.insertion.strictUndoSemantics ? "Enabled" : "Disabled") {
                        uiModel.updateStrictUndo(!uiModel.config.insertion.strictUndoSemantics)
                    }
                }
            }

            SimplePanel {
                Text("Shortcuts")
                    .font(.headline)
                Text("Accept suggestions with Tab or Enter. Dismiss with Esc. Left-click the status item for quick controls and right-click for overflow actions.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var modelsSection: some View {
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
                    Text("Model source")
                        .font(.headline)
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
                    Text(lastError)
                        .foregroundStyle(.orange)
                }
            }

            SimplePanel {
                HStack {
                    Text("Installed models")
                        .font(.headline)
                    Spacer()
                    Button("Rollback") {
                        uiModel.rollbackModel()
                    }
                    .disabled(uiModel.modelHealth.installedModels.isEmpty)
                }

                if uiModel.modelHealth.installedModels.isEmpty {
                    Text("No installed models.")
                        .foregroundStyle(.secondary)
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
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SimplePanel {
                Text("If Input Monitoring was just enabled in System Settings, quit and reopen AutoSuggest once so macOS applies the change to the running app.")
                    .foregroundStyle(.secondary)
                permissionRow(
                    title: "Accessibility",
                    status: uiModel.permissionHealth.accessibilityTrusted ? "Granted" : "Missing"
                ) {
                    uiModel.openAccessibilitySettings()
                }
                permissionRow(
                    title: "Input Monitoring",
                    status: uiModel.permissionHealth.inputMonitoringTrusted ? "Granted" : "Missing"
                ) {
                    uiModel.openInputMonitoringSettings()
                }
                Button("Recheck Permissions") {
                    uiModel.refreshPermissions()
                }
            }

            SimplePanel {
                HStack {
                    Text("PII filtering")
                    Spacer()
                    Button(uiModel.config.privacy.piiFilteringEnabled ? "Enabled" : "Disabled") {
                        uiModel.updatePIIFiltering(!uiModel.config.privacy.piiFilteringEnabled)
                    }
                }
                HStack {
                    Text("Local telemetry")
                    Spacer()
                    Button(uiModel.config.telemetry.enabled ? "Enabled" : "Disabled") {
                        uiModel.updateTelemetryEnabled(!uiModel.config.telemetry.enabled)
                    }
                }
                HStack {
                    Text("Local only export")
                    Spacer()
                    Button(uiModel.config.telemetry.localStoreOnly ? "Enabled" : "Disabled") {
                        uiModel.updateTelemetryLocalOnly(!uiModel.config.telemetry.localStoreOnly)
                    }
                }
            }
        }
    }

    private var exclusionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SimplePanel {
                HStack {
                    TextField("Search rules", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                    Button("Exclude Frontmost App") {
                        uiModel.excludeFrontmostApp()
                    }
                    Button("Add Rule…") {
                        ruleDraft = ExclusionRuleDraft()
                        editingRule = nil
                        isRuleEditorPresented = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            SimplePanel {
                HStack {
                    Button("VS Code") { uiModel.applyExclusionPreset("com.microsoft.VSCode") }
                    Button("Xcode") { uiModel.applyExclusionPreset("com.apple.dt.Xcode") }
                    Button("IntelliJ") { uiModel.applyExclusionPreset("com.jetbrains.intellij") }
                }
            }

            SimplePanel {
                if filteredRules.isEmpty {
                    Text("No exclusion rules.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(filteredRules.enumerated()), id: \.offset) { _, rule in
                        HStack {
                            Text(rule.bundleID ?? "Custom rule")
                            Spacer()
                            Button(rule.enabled ? "Disable" : "Enable") {
                                uiModel.toggleRuleEnabled(rule, enabled: !rule.enabled)
                            }
                            .buttonStyle(.borderless)
                            Button("Edit") {
                                ruleDraft = ExclusionRuleDraft(rule: rule)
                                editingRule = rule
                                isRuleEditorPresented = true
                            }
                            .buttonStyle(.borderless)
                            Button("Delete", role: .destructive) {
                                uiModel.deleteExclusionRule(rule)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
    }

    private var accessibilitySection: some View {
        SimplePanel {
            Text("VoiceOver announcements")
                .font(.headline)
            Text("Suggestions are announced once and stay keyboard-first.")
                .foregroundStyle(.secondary)
            Text("Reduce Transparency: \(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? "Enabled" : "Disabled")")
            Text("Increase Contrast: \(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? "Enabled" : "Disabled")")
            Button("Preview VoiceOver Announcement") {
                uiModel.previewAnnouncement()
            }
        }
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SimplePanel {
                Text("Metrics")
                    .font(.headline)
                Text("Shown: \(uiModel.metrics.suggestionsShown)")
                Text("Accepted: \(uiModel.metrics.suggestionsAccepted)")
                Text("Latency: \(uiModel.metrics.avgLatencyMs > 0 ? "\(Int(uiModel.metrics.avgLatencyMs.rounded())) ms" : "No samples")")
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

    private var filteredRules: [ExclusionRule] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return uiModel.config.exclusions.userRules }
        return uiModel.config.exclusions.userRules.filter { rule in
            [
                rule.bundleID ?? "",
                rule.windowTitleContains ?? "",
                rule.contentPattern ?? "",
            ].contains(where: { $0.localizedStandardContains(query) })
        }
    }

    @ViewBuilder
    private func permissionRow(title: String, status: String, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings", action: action)
        }
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
    }
}

private struct SimplePanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

private struct BannerView: View {
    let banner: AppBanner
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbolName)
                .foregroundStyle(symbolColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title)
                    .font(.headline)
                Text(banner.message)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var symbolName: String {
        switch banner.kind {
        case .info:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        }
    }

    private var symbolColor: Color {
        switch banner.kind {
        case .info:
            return .blue
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
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

private struct ExclusionRuleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ExclusionRuleDraft
    let onSave: (ExclusionRuleDraft) -> Void

    init(draft: ExclusionRuleDraft, onSave: @escaping (ExclusionRuleDraft) -> Void) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exclusion Rule")
                .font(.title3.weight(.semibold))
            Button(draft.enabled ? "Rule Enabled" : "Rule Disabled") {
                draft.enabled.toggle()
            }
            TextField("Bundle ID", text: $draft.bundleID)
            TextField("Window title contains", text: $draft.windowTitleContains)
            TextField("Content regex", text: $draft.contentPattern)

            if let message = draft.validationMessage() {
                Text(message)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    onSave(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.validationMessage() != nil)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
