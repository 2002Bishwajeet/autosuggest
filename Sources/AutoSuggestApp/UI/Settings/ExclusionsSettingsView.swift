import SwiftUI

struct ExclusionsSettingsView: View {
    @ObservedObject var uiModel: AutoSuggestUIModel

    @State private var searchText = ""
    @State private var isRuleEditorPresented = false
    @State private var ruleDraft = ExclusionRuleDraft()
    @State private var editingRule: ExclusionRule?
    @State private var ruleToDelete: ExclusionRule?

    var body: some View {
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
                        Text(
                            "Add rules to prevent suggestions in specific apps, windows, or when certain content is detected."
                        )
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
        .sheet(isPresented: $isRuleEditorPresented) {
            ExclusionRuleEditorView(draft: ruleDraft) { savedDraft in
                uiModel.saveExclusionRule(savedDraft, originalRule: editingRule)
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
