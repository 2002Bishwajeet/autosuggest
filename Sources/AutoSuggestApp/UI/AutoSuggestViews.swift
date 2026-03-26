import AppKit
import SwiftUI

struct StatusPopoverView: View {
    @ObservedObject var uiModel: AutoSuggestUIModel

    private var statusIndicator: StatusDot.Status {
        if !uiModel.config.enabled { return .inactive }
        if uiModel.quickPanelState.pauseReason != nil { return .paused }
        if uiModel.modelHealth.lastError != nil { return .error }
        return .active
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let banner = uiModel.banner {
                    BannerView(banner: banner, onDismiss: uiModel.dismissBanner)
                }

                HStack(spacing: 10) {
                    StatusDot(status: statusIndicator)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AutoSuggest")
                            .font(.title3.weight(.semibold))
                        Text(uiModel.quickPanelState.statusHeadline)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if let pauseReason = uiModel.quickPanelState.pauseReason {
                    SimplePanel {
                        Label(pauseReason, systemImage: "pause.circle")
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle("AutoSuggest", isOn: Binding(
                    get: { uiModel.config.enabled },
                    set: { uiModel.toggleEnabled($0) }
                ))
                .toggleStyle(.switch)

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        statusRow("Runtime", value: uiModel.quickPanelState.activeRuntimeLabel)
                        statusRow("Model", value: uiModel.quickPanelState.activeModelLabel)
                        statusRow("Permissions", value: uiModel.permissionHealth.summary)
                        statusRow("Latency", value: uiModel.metrics.avgLatencyMs > 0
                            ? "\(Int(uiModel.metrics.avgLatencyMs.rounded())) ms"
                            : "No samples")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    SectionHeader("Status", systemImage: "chart.bar")
                }

                VStack(spacing: 6) {
                    QuickActionButton(title: "Open Settings", systemImage: "gearshape") {
                        uiModel.openSettings(.general)
                    }
                    .accessibilityHint("Opens the settings window")
                    Divider().padding(.horizontal, 8)
                    QuickActionButton(title: "Pause for 1 Hour", systemImage: "pause.circle") {
                        uiModel.pauseForHour()
                    }
                    .accessibilityHint("Pauses suggestions for one hour")
                    QuickActionButton(title: "Exclude Current App", systemImage: "minus.circle") {
                        uiModel.excludeFrontmostApp()
                    }
                    .accessibilityHint("Adds the frontmost app to the exclusion list")
                    QuickActionButton(title: "Retry Model", systemImage: "arrow.clockwise") {
                        uiModel.retryModel()
                    }
                    .accessibilityHint("Retries loading the inference model")
                    Divider().padding(.horizontal, 8)
                    QuickActionButton(title: "Export Diagnostics", systemImage: "square.and.arrow.up") {
                        uiModel.exportDiagnostics()
                    }
                    .accessibilityHint("Exports diagnostics data to a file")
                    QuickActionButton(title: "Quit AutoSuggest", systemImage: "xmark.circle") {
                        uiModel.quitApp()
                    }
                    .accessibilityHint("Quits the application")
                }
            }
        }
        .padding(16)
        .frame(width: 368)
        .background(AutoSuggestTheme.surfacePrimary)
    }

    private func statusRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .font(.system(.body, design: .monospaced))
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }
}

private struct QuickActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AutoSuggestTheme.radiusSmall, style: .continuous)
                    .fill(isHovered
                        ? Color.primary.opacity(0.08)
                        : AutoSuggestTheme.surfaceSecondary)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
        .accessibilityLabel(title)
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
    @State private var ruleToDelete: ExclusionRule?
    @State private var showRollbackConfirmation = false
    @State private var onlineLLMAPIKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(route.title)
                .font(.title2.weight(.semibold))

            switch route {
            case .general:
                generalSection
            case .models:
                modelsSection
            case .onlineLLM:
                onlineLLMSection
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
                Toggle("AutoSuggest", isOn: Binding(
                    get: { uiModel.config.enabled },
                    set: { uiModel.toggleEnabled($0) }
                ))

                Divider()

                Picker("Battery behavior", selection: Binding(
                    get: { uiModel.config.battery.mode },
                    set: { uiModel.updateBatteryMode($0) }
                )) {
                    Text("Always On").tag(BatteryMode.alwaysOn)
                    Text("Pause on Low Power").tag(BatteryMode.pauseOnLowPower)
                }
                .pickerStyle(.segmented)

                Divider()

                Toggle("Strict undo semantics", isOn: Binding(
                    get: { uiModel.config.insertion.strictUndoSemantics },
                    set: { _ in uiModel.updateStrictUndo(!uiModel.config.insertion.strictUndoSemantics) }
                ))
                Text("When enabled, only clipboard-paste insertion is used, giving a cleaner Cmd+Z experience.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SimplePanel {
                SectionHeader("Shortcuts", systemImage: "keyboard")
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
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Accessibility row
            PermissionSettingsRow(
                systemImage: "accessibility",
                title: "Accessibility",
                description: "Required to read text context and insert completions into any text field.",
                granted: uiModel.permissionHealth.accessibilityTrusted,
                primaryLabel: "Show Prompt",
                secondaryLabel: "Open Settings",
                primaryAction: { uiModel.openAccessibilitySettings() },
                secondaryAction: { uiModel.openAccessibilitySettings() }
            )

            // Input Monitoring row
            PermissionSettingsRow(
                systemImage: "keyboard",
                title: "Input Monitoring",
                description: "Required to detect Tab, Enter, and Esc for accepting or dismissing suggestions. Needs a relaunch after granting.",
                granted: uiModel.permissionHealth.inputMonitoringTrusted,
                primaryLabel: "Register & Open",
                secondaryLabel: "Open Settings",
                primaryAction: { uiModel.openInputMonitoringSettings() },
                secondaryAction: { uiModel.openInputMonitoringSettings() }
            )

            // Relaunch / recheck controls
            HStack(spacing: 10) {
                Button("Recheck") {
                    uiModel.refreshPermissions()
                }
                .buttonStyle(.bordered)

                if !uiModel.permissionHealth.isReady {
                    Button("Relaunch Now") {
                        uiModel.relaunchApp()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            }

            SimplePanel {
                SectionHeader("Privacy & Telemetry", systemImage: "hand.raised")

                Toggle("PII filtering", isOn: Binding(
                    get: { uiModel.config.privacy.piiFilteringEnabled },
                    set: { _ in uiModel.updatePIIFiltering(!uiModel.config.privacy.piiFilteringEnabled) }
                ))
                Text("Strips emails, phone numbers, and card numbers from personalization data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Toggle("Local telemetry", isOn: Binding(
                    get: { uiModel.config.telemetry.enabled },
                    set: { _ in uiModel.updateTelemetryEnabled(!uiModel.config.telemetry.enabled) }
                ))

                Toggle("Local only export", isOn: Binding(
                    get: { uiModel.config.telemetry.localStoreOnly },
                    set: { _ in uiModel.updateTelemetryLocalOnly(!uiModel.config.telemetry.localStoreOnly) }
                ))
            }

            SimplePanel {
                SectionHeader("Training Data", systemImage: "doc.text")

                Toggle("Collect training data (opt-in)", isOn: Binding(
                    get: { uiModel.config.privacy.trainingDataCollectionEnabled },
                    set: { uiModel.onUpdateTrainingDataCollection?($0) }
                ))
                Text("When enabled, accepted suggestions are recorded locally for fine-tuning. PII is filtered automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Export Training Data") {
                        uiModel.onExportTrainingData?()
                    }
                    .disabled(!uiModel.config.privacy.trainingDataCollectionEnabled)
                    Button("Clear Training Data") {
                        uiModel.onClearTrainingData?()
                    }
                    .disabled(!uiModel.config.privacy.trainingDataCollectionEnabled)
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
                    VStack(spacing: 6) {
                        Image(systemName: "shield.slash")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        Text("No exclusion rules")
                            .foregroundStyle(.secondary)
                        Text("Add rules to prevent suggestions in specific apps, windows, or when certain content is detected.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } else {
                    ForEach(Array(filteredRules.enumerated()), id: \.offset) { _, rule in
                        HStack {
                            Circle()
                                .fill(rule.enabled ? AutoSuggestTheme.success : AutoSuggestTheme.textTertiary)
                                .frame(width: 6, height: 6)
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
                                ruleToDelete = rule
                            }
                            .buttonStyle(.borderless)
                        }
                        Divider()
                    }
                    .confirmationDialog("Delete this exclusion rule?", isPresented: Binding(
                        get: { ruleToDelete != nil },
                        set: { if !$0 { ruleToDelete = nil } }
                    )) {
                        Button("Delete", role: .destructive) {
                            if let rule = ruleToDelete {
                                uiModel.deleteExclusionRule(rule)
                            }
                            ruleToDelete = nil
                        }
                        Button("Cancel", role: .cancel) { ruleToDelete = nil }
                    } message: {
                        Text("This exclusion rule will be permanently removed.")
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

    private var onlineLLMSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SimplePanel {
                Toggle("Enable online LLM", isOn: Binding(
                    get: { uiModel.config.onlineLLM.enabled },
                    set: { uiModel.onUpdateOnlineLLMEnabled?($0) }
                ))
                Text("Use a cloud-based LLM provider for suggestions. Requires an API key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if uiModel.config.onlineLLM.enabled {
                SimplePanel {
                    SectionHeader("Provider", systemImage: "cloud")

                    Picker("Provider", selection: Binding(
                        get: { uiModel.config.onlineLLM.byok.provider },
                        set: { uiModel.onUpdateOnlineLLMProvider?($0) }
                    )) {
                        ForEach(OnlineLLMProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }

                    TextField("Model", text: Binding(
                        get: { uiModel.config.onlineLLM.byok.selectedModel },
                        set: { uiModel.onUpdateOnlineLLMModel?($0) }
                    ))

                    if uiModel.config.onlineLLM.byok.provider.requiresEndpointField {
                        TextField("Endpoint URL", text: Binding(
                            get: { uiModel.config.onlineLLM.byok.endpointURL ?? "" },
                            set: { uiModel.onUpdateOnlineLLMEndpoint?($0) }
                        ))
                    }

                    Picker("Priority", selection: Binding(
                        get: { uiModel.config.onlineLLM.byok.priority },
                        set: { uiModel.onUpdateOnlineLLMPriority?($0) }
                    )) {
                        Text("Primary (try first)").tag(OnlineLLMPriority.primary)
                        Text("Fallback (try last)").tag(OnlineLLMPriority.fallback)
                    }
                    .pickerStyle(.segmented)
                }

                SimplePanel {
                    SectionHeader("API Key", systemImage: "key")
                    SecureField("Enter API key", text: $onlineLLMAPIKey)
                        .onChange(of: onlineLLMAPIKey) { newValue in
                            uiModel.onUpdateOnlineLLMAPIKey?(newValue)
                        }
                    Text("Stored securely in the system keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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

}

private struct PermissionSettingsRow: View {
    let systemImage: String
    let title: String
    let description: String
    let granted: Bool
    let primaryLabel: String
    let secondaryLabel: String
    let primaryAction: () -> Void
    let secondaryAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(granted ? Color.green.opacity(0.1) : Color.orange.opacity(0.09))
                    .frame(width: 40, height: 40)
                Image(systemName: granted ? "checkmark.shield.fill" : systemImage)
                    .font(.system(size: 18))
                    .foregroundStyle(granted ? .green : .orange)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    Text(granted ? "Granted" : "Required")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(granted ? Color.green.opacity(0.1) : Color.orange.opacity(0.1)))
                        .foregroundStyle(granted ? .green : .orange)
                }
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !granted {
                    HStack(spacing: 8) {
                        Button(primaryLabel, action: primaryAction)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        Button(secondaryLabel, action: secondaryAction)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(granted ? Color.green.opacity(0.18) : Color(nsColor: .separatorColor), lineWidth: 1)
                )
        )
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
            Toggle("Rule enabled", isOn: $draft.enabled)
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
