import AppKit
import Foundation

enum SettingsRoute: String, CaseIterable, Identifiable {
    case general
    case models
    case permissionsPrivacy
    case exclusions
    case accessibility
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .models:
            return "Models"
        case .permissionsPrivacy:
            return "Permissions & Privacy"
        case .exclusions:
            return "Exclusions"
        case .accessibility:
            return "Accessibility"
        case .diagnostics:
            return "Diagnostics"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "switch.2"
        case .models:
            return "cpu"
        case .permissionsPrivacy:
            return "hand.raised"
        case .exclusions:
            return "line.3.horizontal.decrease.circle"
        case .accessibility:
            return "figure.wave"
        case .diagnostics:
            return "stethoscope"
        }
    }
}

enum BannerKind {
    case info
    case success
    case warning
    case error
}

struct AppBanner: Identifiable {
    let id = UUID()
    let kind: BannerKind
    let title: String
    let message: String
}

struct PermissionHealth {
    var accessibilityTrusted: Bool
    var inputMonitoringTrusted: Bool

    static let empty = PermissionHealth(
        accessibilityTrusted: false,
        inputMonitoringTrusted: false
    )

    var isReady: Bool {
        accessibilityTrusted && inputMonitoringTrusted
    }

    var missingItems: [String] {
        var items: [String] = []
        if !accessibilityTrusted {
            items.append("Accessibility")
        }
        if !inputMonitoringTrusted {
            items.append("Input Monitoring")
        }
        return items
    }

    var summary: String {
        if isReady {
            return "All required permissions are granted."
        }
        return "Missing: \(missingItems.joined(separator: ", "))"
    }
}

struct QuickPanelState {
    var pauseReason: String?
    var activeRuntimeLabel: String
    var activeModelLabel: String
    var statusHeadline: String

    static let empty = QuickPanelState(
        pauseReason: nil,
        activeRuntimeLabel: "No runtime ready",
        activeModelLabel: "No local model",
        statusHeadline: "Waiting for setup"
    )
}

struct ModelHealth {
    var menuSummary: String
    var activeRuntimeLabel: String
    var activeModelLabel: String
    var report: ModelCompatibilityReport
    var installedModels: [InstalledModel]
    var activeModelPath: URL?
    var isDownloading: Bool
    var lastError: String?

    static let empty = ModelHealth(
        menuSummary: "No local model configured",
        activeRuntimeLabel: "No runtime ready",
        activeModelLabel: "No local model",
        report: ModelCompatibilityReport(
            recommendedMaxParamsB: 0,
            hardMaxParamsB: 0,
            totalMemoryGB: 0,
            availableMemoryGB: nil,
            runtimeHealth: [],
            installedAssessments: [],
            suggestedModels: []
        ),
        installedModels: [],
        activeModelPath: nil,
        isDownloading: false,
        lastError: nil
    )
}

struct DiagnosticsSnapshot {
    var reportText: String
    var lastModelError: String?
    var exportPath: String?

    static let empty = DiagnosticsSnapshot(
        reportText: "Diagnostics unavailable.",
        lastModelError: nil,
        exportPath: nil
    )
}

enum OnboardingModelChoice: String {
    case ollama
    case llamaCpp
    case coreML
}

struct ExclusionRuleDraft: Identifiable, Equatable {
    let id = UUID()
    var enabled: Bool
    var bundleID: String
    var windowTitleContains: String
    var contentPattern: String

    init(rule: ExclusionRule? = nil) {
        enabled = rule?.enabled ?? true
        bundleID = rule?.bundleID ?? ""
        windowTitleContains = rule?.windowTitleContains ?? ""
        contentPattern = rule?.contentPattern ?? ""
    }

    func validationMessage() -> String? {
        let hasAnyValue = !bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !windowTitleContains.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !contentPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasAnyValue else {
            return "Enter at least one condition."
        }

        let pattern = contentPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return nil }
        do {
            _ = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        } catch {
            return "Content pattern is not valid regex."
        }
        return nil
    }

    func makeRule() -> ExclusionRule {
        let trimmedBundleID = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWindowTitle = windowTitleContains.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPattern = contentPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        return ExclusionRule(
            enabled: enabled,
            bundleID: trimmedBundleID.isEmpty ? nil : trimmedBundleID,
            windowTitleContains: trimmedWindowTitle.isEmpty ? nil : trimmedWindowTitle,
            contentPattern: trimmedPattern.isEmpty ? nil : trimmedPattern
        )
    }
}

struct ModelSourceDraft: Equatable, Identifiable {
    let id = UUID()
    var sourceType: LocalModelSourceType
    var modelID: String
    var version: String
    var sha256: String
    var directURL: String
    var huggingFaceRepoID: String
    var huggingFaceRevision: String
    var huggingFaceFilePath: String
    var huggingFaceToken: String

    init(source: LocalModelCustomSourceConfig) {
        sourceType = source.sourceType
        modelID = source.modelID
        version = source.version
        sha256 = source.sha256
        directURL = source.directURL
        huggingFaceRepoID = source.huggingFace.repoID
        huggingFaceRevision = source.huggingFace.revision
        huggingFaceFilePath = source.huggingFace.filePath
        huggingFaceToken = ""
    }

    func validationMessage() -> String? {
        if modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Model ID is required."
        }
        if version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Version is required."
        }

        switch sourceType {
        case .directURL:
            let value = directURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if URL(string: value) == nil {
                return "Enter a valid direct URL."
            }
        case .huggingFace:
            if huggingFaceRepoID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Hugging Face repo is required."
            }
            if huggingFaceFilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Hugging Face file path is required."
            }
        }

        return nil
    }

    func makeSource(using existing: LocalModelCustomSourceConfig) -> LocalModelCustomSourceConfig {
        LocalModelCustomSourceConfig(
            sourceType: sourceType,
            modelID: modelID.trimmingCharacters(in: .whitespacesAndNewlines),
            version: version.trimmingCharacters(in: .whitespacesAndNewlines),
            sha256: sha256.trimmingCharacters(in: .whitespacesAndNewlines),
            directURL: directURL.trimmingCharacters(in: .whitespacesAndNewlines),
            huggingFace: HuggingFaceModelSourceConfig(
                repoID: huggingFaceRepoID.trimmingCharacters(in: .whitespacesAndNewlines),
                revision: huggingFaceRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "main" : huggingFaceRevision.trimmingCharacters(in: .whitespacesAndNewlines),
                filePath: huggingFaceFilePath.trimmingCharacters(in: .whitespacesAndNewlines),
                tokenKeychainAccount: existing.huggingFace.tokenKeychainAccount
            )
        )
    }
}

extension MetricsSnapshot {
    static let zero = MetricsSnapshot(
        suggestionsShown: 0,
        suggestionsAccepted: 0,
        suggestionsDismissed: 0,
        suggestionErrors: 0,
        insertionFailures: 0,
        avgLatencyMs: 0
    )

    var acceptanceRateText: String {
        guard suggestionsShown > 0 else { return "No suggestions yet" }
        let rate = Double(suggestionsAccepted) / Double(suggestionsShown)
        return "\(Int((rate * 100).rounded()))% accepted"
    }
}

@MainActor
final class AutoSuggestUIModel: ObservableObject {
    @Published var config: AppConfig
    @Published var selectedSettingsRoute: SettingsRoute = .general
    @Published var permissionHealth: PermissionHealth = .empty
    @Published var quickPanelState: QuickPanelState = .empty
    @Published var modelHealth: ModelHealth = .empty
    @Published var diagnostics: DiagnosticsSnapshot = .empty
    @Published var metrics: MetricsSnapshot = .zero
    @Published var banner: AppBanner?
    @Published var onboardingModelChoice: OnboardingModelChoice = .ollama

    var onSetEnabled: ((Bool) -> Void)?
    var onOpenSettings: ((SettingsRoute) -> Void)?
    var onPauseForHour: (() -> Void)?
    var onExcludeFrontmostApp: (() -> Void)?
    var onRetryModel: (() -> Void)?
    var onExportDiagnostics: (() -> Void)?
    var onOpenAccessibilitySettings: (() -> Void)?
    var onOpenInputMonitoringSettings: (() -> Void)?
    var onRefreshPermissions: (() -> Void)?
    var onUpdateBatteryMode: ((BatteryMode) -> Void)?
    var onUpdateStrictUndo: ((Bool) -> Void)?
    var onUpdatePIIFiltering: ((Bool) -> Void)?
    var onUpdateTelemetryEnabled: ((Bool) -> Void)?
    var onUpdateTelemetryLocalOnly: ((Bool) -> Void)?
    var onMoveRuntime: ((Int, Int) -> Void)?
    var onSwitchToInstalledModel: ((InstalledModel) -> Void)?
    var onRollbackModel: (() -> Void)?
    var onSaveModelSource: ((ModelSourceDraft) -> Void)?
    var onToggleRuleEnabled: ((ExclusionRule, Bool) -> Void)?
    var onSaveExclusionRule: ((ExclusionRuleDraft, ExclusionRule?) -> Void)?
    var onDeleteExclusionRule: ((ExclusionRule) -> Void)?
    var onApplyExclusionPreset: ((String) -> Void)?
    var onPreviewAnnouncement: (() -> Void)?
    var onQuitApp: (() -> Void)?

    init(config: AppConfig) {
        self.config = config
    }

    func showBanner(kind: BannerKind, title: String, message: String) {
        banner = AppBanner(kind: kind, title: title, message: message)
    }

    func dismissBanner() {
        banner = nil
    }

    func openSettings(_ route: SettingsRoute = .general) {
        selectedSettingsRoute = route
        onOpenSettings?(route)
    }

    func toggleEnabled(_ enabled: Bool) {
        onSetEnabled?(enabled)
    }

    func pauseForHour() {
        onPauseForHour?()
    }

    func excludeFrontmostApp() {
        onExcludeFrontmostApp?()
    }

    func retryModel() {
        onRetryModel?()
    }

    func exportDiagnostics() {
        onExportDiagnostics?()
    }

    func openAccessibilitySettings() {
        onOpenAccessibilitySettings?()
    }

    func openInputMonitoringSettings() {
        onOpenInputMonitoringSettings?()
    }

    func refreshPermissions() {
        onRefreshPermissions?()
    }

    func updateBatteryMode(_ mode: BatteryMode) {
        onUpdateBatteryMode?(mode)
    }

    func updateStrictUndo(_ enabled: Bool) {
        onUpdateStrictUndo?(enabled)
    }

    func updatePIIFiltering(_ enabled: Bool) {
        onUpdatePIIFiltering?(enabled)
    }

    func updateTelemetryEnabled(_ enabled: Bool) {
        onUpdateTelemetryEnabled?(enabled)
    }

    func updateTelemetryLocalOnly(_ enabled: Bool) {
        onUpdateTelemetryLocalOnly?(enabled)
    }

    func moveRuntime(from index: Int, direction: Int) {
        let target = index + direction
        onMoveRuntime?(index, target)
    }

    func switchToInstalledModel(_ model: InstalledModel) {
        onSwitchToInstalledModel?(model)
    }

    func rollbackModel() {
        onRollbackModel?()
    }

    func saveModelSource(_ draft: ModelSourceDraft) {
        onSaveModelSource?(draft)
    }

    func toggleRuleEnabled(_ rule: ExclusionRule, enabled: Bool) {
        onToggleRuleEnabled?(rule, enabled)
    }

    func saveExclusionRule(_ draft: ExclusionRuleDraft, originalRule: ExclusionRule?) {
        onSaveExclusionRule?(draft, originalRule)
    }

    func deleteExclusionRule(_ rule: ExclusionRule) {
        onDeleteExclusionRule?(rule)
    }

    func applyExclusionPreset(_ bundleID: String) {
        onApplyExclusionPreset?(bundleID)
    }

    func previewAnnouncement() {
        onPreviewAnnouncement?()
    }

    func quitApp() {
        onQuitApp?()
    }
}
