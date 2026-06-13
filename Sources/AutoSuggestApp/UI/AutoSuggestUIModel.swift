import AppKit
import Foundation

enum SettingsRoute: String, CaseIterable, Identifiable {
    case general
    case models
    case permissionsPrivacy
    case exclusions
    case accessibility
    case onlineLLM
    case diagnostics

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .general:
            "General"
        case .models:
            "Models"
        case .onlineLLM:
            "Online LLM"
        case .permissionsPrivacy:
            "Permissions & Privacy"
        case .exclusions:
            "Exclusions"
        case .accessibility:
            "Accessibility"
        case .diagnostics:
            "Diagnostics"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            "switch.2"
        case .models:
            "cpu"
        case .onlineLLM:
            "cloud"
        case .permissionsPrivacy:
            "hand.raised"
        case .exclusions:
            "line.3.horizontal.decrease.circle"
        case .accessibility:
            "figure.wave"
        case .diagnostics:
            "stethoscope"
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
    var pauseRemedy: String?
    var activeRuntimeLabel: String
    var activeModelLabel: String
    var statusHeadline: String

    static let empty = QuickPanelState(
        pauseReason: nil,
        pauseRemedy: nil,
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
                revision: huggingFaceRevision.trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty ? "main" : huggingFaceRevision.trimmingCharacters(in: .whitespacesAndNewlines),
                filePath: huggingFaceFilePath.trimmingCharacters(in: .whitespacesAndNewlines),
                tokenKeychainAccount: existing.huggingFace.tokenKeychainAccount
            )
        )
    }
}

/// Friendly, human-readable display names for the runtime identifier strings
/// stored in `config.localModel.runtimeOrder` (e.g. "ollama", "llama.cpp",
/// "coreml", "online"). Unknown identifiers are returned unchanged so the UI
/// never shows an empty label.
enum RuntimeDisplayName {
    static func label(for runtimeID: String) -> String {
        switch runtimeID.lowercased() {
        case "ollama":
            "Ollama"
        case "llama.cpp", "llamacpp", "llamaserver":
            "llama.cpp"
        case "coreml", "core ml":
            "Core ML"
        case "online":
            "Online LLM"
        default:
            runtimeID
        }
    }
}

extension ExclusionRule {
    /// A human-readable one-line summary of what the rule matches, used as the
    /// row title in the exclusions list. Prefers the bundle ID, then a window
    /// title condition, then a content-pattern condition, falling back to a
    /// generic label when (defensively) nothing is set.
    var displayTitle: String {
        if let bundleID, !bundleID.isEmpty {
            return bundleID
        }
        if let windowTitleContains, !windowTitleContains.isEmpty {
            return "Window title contains \u{201C}\(windowTitleContains)\u{201D}"
        }
        if let contentPattern, !contentPattern.isEmpty {
            return "Content matches /\(contentPattern)/"
        }
        return "Custom rule"
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
    /// Set when Input Monitoring is granted but the tap could not be armed in this
    /// process; the UI shows a one-click "Relaunch to finish enabling" action.
    @Published var needsRelaunchToEnable: Bool = false
    @Published var quickPanelState: QuickPanelState = .empty
    @Published var modelHealth: ModelHealth = .empty
    @Published var ollamaRunning: Bool = false
    @Published var ollamaInstalled: [OllamaModelService.InstalledModel] = []
    /// model name -> in-flight pull progress
    @Published var ollamaPulls: [String: OllamaModelService.PullProgress] = [:]
    @Published var llamaCppReachable: Bool = false
    @Published var diagnostics: DiagnosticsSnapshot = .empty
    @Published var metrics: MetricsSnapshot = .zero
    @Published var banner: AppBanner?
    @Published var onboardingModelChoice: OnboardingModelChoice = .ollama
    @Published var personalizationStats: (unique: Int, total: Int) = (0, 0)

    var onSetEnabled: ((Bool) -> Void)?
    var onOpenSettings: ((SettingsRoute) -> Void)?
    var onPauseForHour: (() -> Void)?
    var onExcludeFrontmostApp: (() -> Void)?
    var onRetryModel: (() -> Void)?
    var onExportDiagnostics: (() -> Void)?
    var onOpenAccessibilitySettings: (() -> Void)?
    var onOpenInputMonitoringSettings: (() -> Void)?
    var onRefreshPermissions: (() -> Void)?
    var onRelaunchApp: (() -> Void)?
    var onUpdateBatteryMode: ((BatteryMode) -> Void)?
    var onUpdateStrictUndo: ((Bool) -> Void)?
    var onUpdatePIIFiltering: ((Bool) -> Void)?
    var onUpdateTelemetryEnabled: ((Bool) -> Void)?
    var onUpdateTelemetryLocalOnly: ((Bool) -> Void)?
    var onMoveRuntime: ((Int, Int) -> Void)?
    var onSwitchToInstalledModel: ((InstalledModel) -> Void)?
    var onRollbackModel: (() -> Void)?
    var onSetOllamaModel: ((String) -> Void)?
    var onSetOllamaBaseURL: ((String) -> Void)?
    var onPullOllamaModel: ((String) -> Void)?
    var onDeleteOllamaModel: ((String) -> Void)?
    var onRefreshOllama: (() -> Void)?
    var onRefreshLlamaCpp: (() -> Void)?
    var onSetLlamaCppBaseURL: ((String) -> Void)?
    var onSaveModelSource: ((ModelSourceDraft) -> Void)?
    var onToggleRuleEnabled: ((ExclusionRule, Bool) -> Void)?
    var onSaveExclusionRule: ((ExclusionRuleDraft, ExclusionRule?) -> Void)?
    var onDeleteExclusionRule: ((ExclusionRule) -> Void)?
    var onApplyExclusionPreset: ((String) -> Void)?
    var onPreviewAnnouncement: (() -> Void)?
    var onUpdateOnlineLLMEnabled: ((Bool) -> Void)?
    var onUpdateOnlineLLMProvider: ((OnlineLLMProvider) -> Void)?
    var onUpdateOnlineLLMModel: ((String) -> Void)?
    var onUpdateOnlineLLMEndpoint: ((String) -> Void)?
    var onUpdateOnlineLLMPriority: ((OnlineLLMPriority) -> Void)?
    var onUpdateOnlineLLMAPIKey: ((String) -> Void)?
    var onUpdateTrainingDataCollection: ((Bool) -> Void)?
    var onExportTrainingData: (() -> Void)?
    var onClearTrainingData: (() -> Void)?
    var onUpdatePersonalization: ((Bool) -> Void)?
    var onClearPersonalization: (() -> Void)?
    var onRefreshPersonalizationStats: (() -> Void)?
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

    func relaunchApp() {
        onRelaunchApp?()
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

    func updatePersonalization(_ enabled: Bool) {
        onUpdatePersonalization?(enabled)
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

    func setOllamaModel(_ name: String) {
        onSetOllamaModel?(name)
    }

    func setOllamaBaseURL(_ url: String) {
        onSetOllamaBaseURL?(url)
    }

    func pullOllamaModel(_ name: String) {
        onPullOllamaModel?(name)
    }

    func deleteOllamaModel(_ name: String) {
        onDeleteOllamaModel?(name)
    }

    func refreshOllama() {
        onRefreshOllama?()
    }

    func refreshLlamaCpp() {
        onRefreshLlamaCpp?()
    }

    func setLlamaCppBaseURL(_ url: String) {
        onSetLlamaCppBaseURL?(url)
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
