import AppKit
import Foundation

/// Disk-derived model state, gathered off the main actor and cached so the
/// synchronous UI refresh never touches the filesystem.
struct ModelStateSnapshot {
    var installedModels: [InstalledModel]
    var activeModelPath: URL?
    var report: ModelCompatibilityReport

    static func empty(report: ModelCompatibilityReport) -> ModelStateSnapshot {
        ModelStateSnapshot(installedModels: [], activeModelPath: nil, report: report)
    }
}

@MainActor
final class AppCoordinator {
    let logger = Logger(scope: "AppCoordinator")
    let statusBarController = StatusBarController()
    let onboardingManager = OnboardingManager()
    let configStore = ConfigStore()
    let permissionManager = PermissionManager()
    let modelManifestProvider = ModelManifestProvider()
    let modelDownloadManager = ModelDownloadManager()
    let modelManager = ModelManager()
    let modelCompatibilityAdvisor = ModelCompatibilityAdvisor()
    let modelSourceResolver = ModelSourceResolver()
    let secretStore = SecretStore()
    let metricsCollector = MetricsCollector()
    let encryptedStore = EncryptedFileStore()
    let localModelSession = LocalModelSession()
    let coreMLModelAdapter = CoreMLModelAdapter()
    let accessibilityAnnouncer = AccessibilityAnnouncer()
    lazy var personalizationEngine = PersonalizationEngine(store: encryptedStore)
    lazy var runtimeFactory = InferenceRuntimeFactory(
        localModelSession: localModelSession,
        personalizationEngine: personalizationEngine,
        coreMLModelAdapter: coreMLModelAdapter
    )
    var trainingDataExporter = TrainingDataExporter(enabled: false)

    var telemetryManager = TelemetryManager(enabled: false)
    var currentConfig: AppConfig?
    var uiModel: AutoSuggestUIModel?
    var policyEngine: PolicyEngine?
    var inferenceEngine: InferenceEngine?
    var orchestrator: SuggestionOrchestrator?
    var typingPipeline: TypingPipeline?
    var metricsRefreshTask: Task<Void, Never>?
    var preferencesWindowController: PreferencesWindowController?
    var manualPauseUntil: Date?
    var lastModelError: String?
    var diagnosticsExportPath: String?
    var lastModelSnapshot: ModelStateSnapshot?
    nonisolated(unsafe) var didBecomeActiveObserver: NSObjectProtocol?
    var lastInputMonitoringTrusted = false

    /// Host-provided callback for "Check for Updates…". Auto-update is an
    /// app-bundle concern owned by the host target (Sparkle); the library only
    /// surfaces the affordance and forwards the intent. Optional: when nil (e.g.
    /// the SwiftPM runner) the status popover hides the control.
    var onCheckForUpdates: (() -> Void)?

    deinit {
        if let didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(didBecomeActiveObserver)
        }
    }

    func start() async {
        // Recover the user's clipboard if a previous run crashed mid-paste,
        // before the pipeline can start and overwrite the saved backup.
        AXTextInsertionEngine.restoreClipboardIfNeeded()

        let config = await configStore.loadOrCreateDefault()
        currentConfig = config
        telemetryManager = TelemetryManager(enabled: config.telemetry.enabled)
        trainingDataExporter = TrainingDataExporter(enabled: config.privacy.trainingDataCollectionEnabled)

        let uiModel = AutoSuggestUIModel(config: config)
        self.uiModel = uiModel
        bindUIModel(uiModel)
        statusBarController.configure(with: uiModel)

        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleDidBecomeActive() }
        }
        lastInputMonitoringTrusted = permissionManager.hasInputMonitoringPermission()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            onboardingManager.showIfNeeded(
                permissionManager: permissionManager,
                localModelConfig: config.localModel,
                onSelectModelChoice: { [weak self] choice in
                    self?.applyOnboardingModelChoice(choice)
                },
                downloadCoreML: { [weak self] in
                    guard let self, let currentConfig else { return }
                    try await ensureModelAvailable(config: currentConfig)
                },
                onOpenSettings: { [weak self] in
                    self?.openSettings(route: .models)
                },
                onComplete: {
                    continuation.resume()
                }
            )
        }

        do {
            try await bootstrapInitialModelIfNeeded()
        } catch {
            lastModelError = Self.friendlyModelSetupMessage(for: error)
            uiModel.showBanner(
                kind: .warning,
                title: "Model setup needs attention",
                message: Self.friendlyModelSetupMessage(for: error)
            )
        }

        rebuildRuntimePipelines(using: currentConfig ?? config)
        await refreshModelState()
        setPipelineEnabledFromCurrentState()
        await personalizationEngine.setEnabled(config.privacy.personalizationEnabled)
        startMetricsRefreshLoop()
        logger.info("Startup complete.")
    }

    func bindUIModel(_ uiModel: AutoSuggestUIModel) {
        uiModel.onSetEnabled = { [weak self] enabled in
            self?.updateEnabled(enabled)
        }
        uiModel.onOpenSettings = { [weak self] route in
            self?.openSettings(route: route)
        }
        uiModel.onPauseForHour = { [weak self] in
            self?.pauseForHour()
        }
        uiModel.onExcludeFrontmostApp = { [weak self] in
            self?.excludeFrontmostApp()
        }
        uiModel.onRetryModel = { [weak self] in
            self?.retryModelAcquisition()
        }
        uiModel.onExportDiagnostics = { [weak self] in
            self?.exportDiagnostics()
        }
        uiModel.onOpenAccessibilitySettings = { [weak self] in
            self?.openAccessibilitySettings()
        }
        uiModel.onOpenInputMonitoringSettings = { [weak self] in
            self?.openInputMonitoringSettings()
        }
        uiModel.onRefreshPermissions = { [weak self] in
            self?.refreshPresentation()
        }
        uiModel.onRelaunchApp = { [weak self] in
            self?.permissionManager.relaunchApp()
        }
        uiModel.onUpdateBatteryMode = { [weak self] mode in
            self?.updateBatteryMode(mode)
        }
        uiModel.onUpdateStrictUndo = { [weak self] enabled in
            self?.updateStrictUndo(enabled)
        }
        uiModel.onUpdatePIIFiltering = { [weak self] enabled in
            self?.updatePIIFiltering(enabled)
        }
        uiModel.onUpdateTelemetryEnabled = { [weak self] enabled in
            self?.updateTelemetryEnabled(enabled)
        }
        uiModel.onUpdateTelemetryLocalOnly = { [weak self] enabled in
            self?.updateTelemetryLocalOnly(enabled)
        }
        uiModel.onMoveRuntime = { [weak self] source, target in
            self?.moveRuntime(from: source, to: target)
        }
        uiModel.onSwitchToInstalledModel = { [weak self] model in
            self?.switchToInstalledModel(model)
        }
        uiModel.onRollbackModel = { [weak self] in
            self?.rollbackModel()
        }
        uiModel.onSetOllamaModel = { [weak self] name in self?.setOllamaModel(name) }
        uiModel.onSetOllamaBaseURL = { [weak self] url in self?.setOllamaBaseURL(url) }
        uiModel.onPullOllamaModel = { [weak self] name in self?.pullOllamaModel(name) }
        uiModel.onDeleteOllamaModel = { [weak self] name in self?.deleteOllamaModel(name) }
        uiModel.onRefreshOllama = { [weak self] in self?.refreshOllama() }
        uiModel.onRefreshLlamaCpp = { [weak self] in self?.refreshLlamaCpp() }
        uiModel.onSetLlamaCppBaseURL = { [weak self] url in self?.setLlamaCppBaseURL(url) }
        uiModel.onSaveModelSource = { [weak self] draft in
            self?.saveModelSource(draft)
        }
        uiModel.onToggleRuleEnabled = { [weak self] rule, enabled in
            self?.toggleRuleEnabled(rule, enabled: enabled)
        }
        uiModel.onSaveExclusionRule = { [weak self] draft, originalRule in
            self?.saveExclusionRule(draft, originalRule: originalRule)
        }
        uiModel.onDeleteExclusionRule = { [weak self] rule in
            self?.deleteExclusionRule(rule)
        }
        uiModel.onApplyExclusionPreset = { [weak self] bundleID in
            self?.applyExclusionPreset(bundleID)
        }
        uiModel.onPreviewAnnouncement = { [weak self] in
            self?.accessibilityAnnouncer.announceSuggestion("AutoSuggest preview")
        }
        uiModel.onUpdateOnlineLLMEnabled = { [weak self] enabled in
            self?.updateOnlineLLMEnabled(enabled)
        }
        uiModel.onUpdateOnlineLLMProvider = { [weak self] provider in
            self?.updateOnlineLLMProvider(provider)
        }
        uiModel.onUpdateOnlineLLMModel = { [weak self] model in
            self?.updateOnlineLLMModel(model)
        }
        uiModel.onUpdateOnlineLLMEndpoint = { [weak self] endpoint in
            self?.updateOnlineLLMEndpoint(endpoint)
        }
        uiModel.onUpdateOnlineLLMPriority = { [weak self] priority in
            self?.updateOnlineLLMPriority(priority)
        }
        uiModel.onUpdateOnlineLLMAPIKey = { [weak self] key in
            self?.updateOnlineLLMAPIKey(key)
        }
        uiModel.onUpdateTrainingDataCollection = { [weak self] enabled in
            self?.updateTrainingDataCollection(enabled)
        }
        uiModel.onExportTrainingData = { [weak self] in
            self?.exportTrainingData()
        }
        uiModel.onClearTrainingData = { [weak self] in
            self?.clearTrainingData()
        }
        uiModel.onUpdatePersonalization = { [weak self] enabled in
            self?.updatePersonalization(enabled)
        }
        uiModel.onClearPersonalization = { [weak self] in
            self?.clearPersonalizationData()
        }
        uiModel.onRefreshPersonalizationStats = { [weak self] in
            self?.refreshPersonalizationStats()
        }
        uiModel.onQuitApp = {
            NSApp.terminate(nil)
        }
        // Only expose the update affordance when the host wired an updater.
        uiModel.onCheckForUpdates = onCheckForUpdates
    }

    func mutateConfig(
        _ update: (inout AppConfig) -> Void,
        persist: @escaping (ConfigStore) async -> Void,
        rebuildPipelines: Bool = false
    ) {
        guard var currentConfig else { return }
        update(&currentConfig)
        self.currentConfig = currentConfig
        Task {
            await persist(configStore)
        }
        if rebuildPipelines {
            rebuildRuntimePipelines(using: currentConfig)
            setPipelineEnabledFromCurrentState()
        }
        refreshPresentation()
    }

    func handleDidBecomeActive() {
        // Cheap TCC re-check + immediate UI update (no disk I/O).
        refreshPresentation()
        refreshOllama()

        let nowGranted = permissionManager.hasInputMonitoringPermission()
        let tapActive = typingPipeline?.inputMonitorIsActive ?? false
        let action = PermissionReArm.decide(
            inputMonitoringNowGranted: nowGranted,
            tapCurrentlyActive: tapActive
        )
        lastInputMonitoringTrusted = nowGranted

        switch action {
        case .none:
            if tapActive { uiModel?.needsRelaunchToEnable = false }
        case .rebuildAndVerify:
            guard let currentConfig else { return }
            rebuildRuntimePipelines(using: currentConfig)
            setPipelineEnabledFromCurrentState()
            // Verify after the run loop installs the fresh tap.
            Task { @MainActor in
                let armed = typingPipeline?.inputMonitorIsActive ?? false
                uiModel?.needsRelaunchToEnable = !armed
                if armed {
                    uiModel?.showBanner(
                        kind: .success,
                        title: "AutoSuggest enabled",
                        message: "Input Monitoring is now active."
                    )
                }
                refreshPresentation()
            }
        }
    }

    func refreshPresentation() {
        guard let currentConfig, let uiModel else { return }

        let permissionHealth = PermissionHealth(
            accessibilityTrusted: permissionManager.isAccessibilityTrusted(),
            inputMonitoringTrusted: permissionManager.hasInputMonitoringPermission()
        )

        let snapshot = lastModelSnapshot
            ?? .empty(report: modelCompatibilityAdvisor.buildReport(
                config: currentConfig.localModel,
                installedModels: []
            ))
        let report = snapshot.report
        let installedModels = snapshot.installedModels
        let activeModelPath = snapshot.activeModelPath
        let activeRuntimeLabel = deriveActiveRuntimeLabel(from: report)
        let activeModelLabel = deriveActiveModelLabel(activeModelPath: activeModelPath, config: currentConfig)

        let modelHealth = ModelHealth(
            menuSummary: activeModelPath == nil ? "No local model configured" : report.menuSummary(),
            activeRuntimeLabel: activeRuntimeLabel,
            activeModelLabel: activeModelLabel,
            report: report,
            installedModels: installedModels,
            activeModelPath: activeModelPath,
            isDownloading: uiModel.modelHealth.isDownloading,
            lastError: lastModelError
        )

        let pauseReason = derivePauseReason(config: currentConfig, permissions: permissionHealth, report: report)
        let pauseRemedy = derivePauseRemedy(config: currentConfig, permissions: permissionHealth, report: report)
        let headline = Self.statusHeadline(enabled: currentConfig.enabled, pauseReason: pauseReason)

        uiModel.config = currentConfig
        uiModel.permissionHealth = permissionHealth
        uiModel.modelHealth = modelHealth
        uiModel.quickPanelState = QuickPanelState(
            pauseReason: pauseReason,
            pauseRemedy: pauseRemedy,
            activeRuntimeLabel: activeRuntimeLabel,
            activeModelLabel: activeModelLabel,
            statusHeadline: headline
        )
        uiModel.diagnostics = DiagnosticsSnapshot(
            reportText: buildDiagnosticsReport(
                config: currentConfig,
                permissions: permissionHealth,
                report: report,
                metrics: uiModel.metrics
            ),
            lastModelError: lastModelError,
            exportPath: diagnosticsExportPath
        )
        statusBarController.refreshAppearance()
    }

    func setPipelineEnabledFromCurrentState() {
        guard let typingPipeline, let currentConfig else { return }
        let shouldRun = currentConfig.enabled && manualPauseUntil == nil
        if shouldRun {
            typingPipeline.start()
        } else {
            typingPipeline.stop()
        }
    }

    func startMetricsRefreshLoop() {
        metricsRefreshTask?.cancel()
        metricsRefreshTask = Task { @MainActor in
            while !Task.isCancelled {
                if let manualPauseUntil, manualPauseUntil <= Date() {
                    self.manualPauseUntil = nil
                    uiModel?.showBanner(
                        kind: .success,
                        title: "AutoSuggest resumed",
                        message: "The one-hour pause has ended."
                    )
                }

                let snapshot = await metricsCollector.snapshot()
                uiModel?.metrics = snapshot
                await refreshModelState()
                setPipelineEnabledFromCurrentState()

                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func refreshModelState() async {
        guard let currentConfig else { return }
        lastModelSnapshot = await gatherModelSnapshot(config: currentConfig.localModel)
        refreshPresentation()
    }

    func openSettings(route: SettingsRoute) {
        guard let uiModel else { return }
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(uiModel: uiModel)
        }
        preferencesWindowController?.show(route: route)
    }

    /// Pure presentation of the menu-bar / quick-panel status headline.
    nonisolated static func statusHeadline(enabled: Bool, pauseReason: String?) -> String {
        if !enabled {
            return "Autocomplete is off"
        }
        if let pauseReason {
            return pauseReason
        }
        return "Suggestions are live"
    }

    /// Turns a model-acquisition failure into a clear, actionable banner message
    /// instead of a raw error code (e.g. the `NSURLErrorDomain -1011` a failed
    /// model download surfaces). Network/server failures point the user at the
    /// runtimes that don't need a download.
    nonisolated static func friendlyModelSetupMessage(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut,
                 .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return "Couldn't reach the model download server. Start Ollama (recommended), or pick a model in Settings → Models."
            case .badServerResponse, .fileDoesNotExist, .resourceUnavailable,
                 .badURL, .unsupportedURL:
                return "The default model download isn't available right now. Start Ollama (recommended), or choose a model in Settings → Models."
            default:
                return "Couldn't download the default model. Start Ollama (recommended), or choose a model in Settings → Models."
            }
        }
        return "Couldn't set up the default model: \(error.localizedDescription). Start Ollama, or pick a model in Settings → Models."
    }

    /// Maps the same pause conditions evaluated by `derivePauseReason` to an actionable hint.
    /// Pure and order-matched to `derivePauseReason` so the remedy always describes the active reason.
    nonisolated static func derivePauseRemedy(
        isManualPause: Bool,
        permissionsReady: Bool,
        lowPowerPause: Bool,
        runtimeReady: Bool
    ) -> String? {
        if isManualPause {
            return nil
        }
        if !permissionsReady {
            return "Open System Settings → Privacy & Security → Accessibility / Input Monitoring, then relaunch AutoSuggest."
        }
        if lowPowerPause {
            return "Suggestions resume automatically when Low Power Mode turns off."
        }
        if !runtimeReady {
            return "Start Ollama (`ollama serve`) or install a model via Model Source Settings…"
        }
        return nil
    }

    /// Reads installed/active model state from disk. Runs off the main actor so
    /// the synchronous UI refresh never blocks on the filesystem.
    nonisolated func gatherModelSnapshot(config: LocalModelConfig) async -> ModelStateSnapshot {
        let installed = (try? modelManager.listInstalledModels()
            .sorted { $0.path.path < $1.path.path }) ?? []
        let report = modelCompatibilityAdvisor.buildReport(config: config, installedModels: installed)
        let activePath = (try? modelManager.readActiveModelPath()) ?? nil
        return ModelStateSnapshot(installedModels: installed, activeModelPath: activePath, report: report)
    }
}
