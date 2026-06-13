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
    private let logger = Logger(scope: "AppCoordinator")
    private let statusBarController = StatusBarController()
    private let onboardingManager = OnboardingManager()
    private let configStore = ConfigStore()
    private let permissionManager = PermissionManager()
    private let modelManifestProvider = ModelManifestProvider()
    private let modelDownloadManager = ModelDownloadManager()
    private let modelManager = ModelManager()
    private let modelCompatibilityAdvisor = ModelCompatibilityAdvisor()
    private let modelSourceResolver = ModelSourceResolver()
    private let secretStore = SecretStore()
    private let metricsCollector = MetricsCollector()
    private let encryptedStore = EncryptedFileStore()
    private let localModelSession = LocalModelSession()
    private let coreMLModelAdapter = CoreMLModelAdapter()
    private let accessibilityAnnouncer = AccessibilityAnnouncer()
    private lazy var personalizationEngine = PersonalizationEngine(store: encryptedStore)
    private lazy var runtimeFactory = InferenceRuntimeFactory(
        localModelSession: localModelSession,
        personalizationEngine: personalizationEngine,
        coreMLModelAdapter: coreMLModelAdapter
    )
    private var trainingDataExporter = TrainingDataExporter(enabled: false)

    private var telemetryManager = TelemetryManager(enabled: false)
    private var currentConfig: AppConfig?
    private var uiModel: AutoSuggestUIModel?
    private var policyEngine: PolicyEngine?
    private var inferenceEngine: InferenceEngine?
    private var orchestrator: SuggestionOrchestrator?
    private var typingPipeline: TypingPipeline?
    private var metricsRefreshTask: Task<Void, Never>?
    private var preferencesWindowController: PreferencesWindowController?
    private var manualPauseUntil: Date?
    private var lastModelError: String?
    private var diagnosticsExportPath: String?
    private var lastModelSnapshot: ModelStateSnapshot?
    private nonisolated(unsafe) var didBecomeActiveObserver: NSObjectProtocol?
    private var lastInputMonitoringTrusted = false

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

    private func bindUIModel(_ uiModel: AutoSuggestUIModel) {
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
    }

    private func bootstrapInitialModelIfNeeded() async throws {
        guard let currentConfig else { return }
        try await ensureModelAvailable(config: currentConfig)
    }

    private func ensureModelAvailable(config: AppConfig) async throws {
        guard config.localModel.autoDownloadOnFirstRun else { return }
        guard !config.localModel.isModelPresent else { return }

        let manifest = await modelManifestProvider.resolveManifest(config: config.localModel)
        logger.info("Downloading initial model from \(manifest.downloadURL.absoluteString)")
        try await modelDownloadManager.downloadIfNeeded(manifest: manifest)
        await configStore.markModelPresent()

        var updatedConfig = config
        updatedConfig.localModel.isModelPresent = true
        currentConfig = updatedConfig
    }

    private func rebuildRuntimePipelines(using config: AppConfig) {
        typingPipeline?.stop()

        policyEngine = PolicyEngine(
            defaults: .default,
            userRules: config.exclusions.userRules
        )
        // Resolve online API key if online LLM is enabled
        var onlineAPIKey: String?
        if config.onlineLLM.enabled {
            onlineAPIKey = try? secretStore.read(account: config.onlineLLM.byok.apiKeyKeychainAccount)
        }

        inferenceEngine = InferenceEngine(
            runtimes: runtimeFactory.makeRuntimes(
                config: config.localModel,
                onlineLLMConfig: config.onlineLLM,
                onlineAPIKey: onlineAPIKey
            )
        )

        prewarmFoundationModelsIfAvailable(config: config.localModel)

        if let policyEngine, let inferenceEngine {
            orchestrator = SuggestionOrchestrator(
                policyEngine: policyEngine,
                inferenceEngine: inferenceEngine
            )
        }

        if let orchestrator {
            typingPipeline = TypingPipeline(
                inputMonitor: CGEventInputMonitor(),
                shortcutMonitor: CGEventShortcutMonitor(),
                contextProvider: AXTextContextProvider(),
                suggestionOrchestrator: orchestrator,
                overlayRenderer: FloatingOverlayRenderer(),
                insertionEngine: AXTextInsertionEngine(
                    strictUndoSemantics: config.insertion.strictUndoSemantics
                ),
                metricsCollector: metricsCollector,
                telemetryManager: telemetryManager,
                personalizationEngine: personalizationEngine,
                accessibilityAnnouncer: accessibilityAnnouncer,
                trainingDataExporter: trainingDataExporter,
                batteryMode: config.battery.mode
            )
        }
    }

    /// Fire-and-forget warm-up of the FoundationModels on-device LLM to mask its
    /// ~1.3s cold start. Gated to when the SDK + OS + user config make it usable;
    /// never blocks the main thread and never crashes if it is unavailable.
    private func prewarmFoundationModelsIfAvailable(config: LocalModelConfig) {
        guard config.foundationModelsEnabled else { return }
        #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                let runtime = FoundationModelsInferenceRuntime(
                    responder: LanguageModelSessionResponder()
                )
                Task { @MainActor in runtime.prewarm() }
            }
        #endif
    }

    private func startMetricsRefreshLoop() {
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

    /// Reads installed/active model state from disk. Runs off the main actor so
    /// the synchronous UI refresh never blocks on the filesystem.
    private nonisolated func gatherModelSnapshot(config: LocalModelConfig) async -> ModelStateSnapshot {
        let installed = (try? modelManager.listInstalledModels()
            .sorted { $0.path.path < $1.path.path }) ?? []
        let report = modelCompatibilityAdvisor.buildReport(config: config, installedModels: installed)
        let activePath = (try? modelManager.readActiveModelPath()) ?? nil
        return ModelStateSnapshot(installedModels: installed, activeModelPath: activePath, report: report)
    }

    /// Async: gather disk state off-main, cache it, then publish.
    private func refreshModelState() async {
        guard let currentConfig else { return }
        lastModelSnapshot = await gatherModelSnapshot(config: currentConfig.localModel)
        refreshPresentation()
    }

    /// Synchronous, main, NO disk I/O. Rebuilds @Published UI state from
    /// currentConfig + cached model snapshot + cheap permission checks.
    private func refreshPresentation() {
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

    private func setPipelineEnabledFromCurrentState() {
        guard let typingPipeline, let currentConfig else { return }
        let shouldRun = currentConfig.enabled && manualPauseUntil == nil
        if shouldRun {
            typingPipeline.start()
        } else {
            typingPipeline.stop()
        }
    }

    private func handleDidBecomeActive() {
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

    private func openSettings(route: SettingsRoute) {
        guard let uiModel else { return }
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(uiModel: uiModel)
        }
        preferencesWindowController?.show(route: route)
    }

    private func updateEnabled(_ enabled: Bool) {
        guard var currentConfig else { return }
        currentConfig.enabled = enabled
        self.currentConfig = currentConfig

        Task {
            await configStore.updateEnabled(enabled)
        }
        refreshPresentation()
        setPipelineEnabledFromCurrentState()
    }

    private func updateBatteryMode(_ mode: BatteryMode) {
        mutateConfig { config in
            config.battery.mode = mode
        } persist: { configStore in
            await configStore.updateBattery(BatteryConfig(mode: mode))
        }
    }

    private func updateStrictUndo(_ enabled: Bool) {
        mutateConfig({ config in
            config.insertion.strictUndoSemantics = enabled
        }, persist: { configStore in
            await configStore.updateInsertion(InsertionConfig(strictUndoSemantics: enabled))
        }, rebuildPipelines: true)
    }

    private func updatePIIFiltering(_ enabled: Bool) {
        mutateConfig { config in
            config.privacy.piiFilteringEnabled = enabled
        } persist: { [weak self] configStore in
            await configStore.updatePrivacy(self?.currentConfig?.privacy ?? AppConfig.default.privacy)
        }
    }

    private func updateTelemetryEnabled(_ enabled: Bool) {
        mutateConfig({ config in
            config.telemetry.enabled = enabled
        }, persist: { [weak self] configStore in
            await configStore.updateTelemetry(self?.currentConfig?.telemetry ?? AppConfig.default.telemetry)
        }, rebuildPipelines: true)

        telemetryManager = TelemetryManager(enabled: enabled)
        if let currentConfig {
            rebuildRuntimePipelines(using: currentConfig)
            setPipelineEnabledFromCurrentState()
        }
    }

    private func updateTelemetryLocalOnly(_ enabled: Bool) {
        mutateConfig { config in
            config.telemetry.localStoreOnly = enabled
        } persist: { [weak self] configStore in
            await configStore.updateTelemetry(self?.currentConfig?.telemetry ?? AppConfig.default.telemetry)
        }
    }

    private func moveRuntime(from source: Int, to target: Int) {
        guard var currentConfig else { return }
        guard currentConfig.localModel.runtimeOrder.indices.contains(source) else { return }
        guard currentConfig.localModel.runtimeOrder.indices.contains(target) else { return }

        let item = currentConfig.localModel.runtimeOrder.remove(at: source)
        currentConfig.localModel.runtimeOrder.insert(item, at: target)
        self.currentConfig = currentConfig

        Task {
            await configStore.updateLocalModel(currentConfig.localModel)
        }
        localModelSession.invalidate()
        coreMLModelAdapter.invalidate()
        rebuildRuntimePipelines(using: currentConfig)
        refreshPresentation()
        Task { await refreshModelState() }
        setPipelineEnabledFromCurrentState()
    }

    private func switchToInstalledModel(_ model: InstalledModel) {
        do {
            try modelManager.switchActiveModel(to: model)
            localModelSession.invalidate()
            coreMLModelAdapter.invalidate()
            lastModelError = nil
            refreshPresentation()
            Task { await refreshModelState() }
            uiModel?.showBanner(
                kind: .success,
                title: "Model switched",
                message: "Now using \(model.id) \(model.version)."
            )
        } catch {
            lastModelError = error.localizedDescription
            refreshPresentation()
        }
    }

    private func ollamaService() -> OllamaModelService {
        OllamaModelService(baseURL: currentConfig?.localModel.ollama.baseURL ?? "http://127.0.0.1:11434")
    }

    private func setOllamaModel(_ name: String) {
        guard var currentConfig else { return }
        currentConfig.localModel.ollama.modelName = name
        self.currentConfig = currentConfig
        Task { await configStore.updateLocalModel(currentConfig.localModel) }
        rebuildRuntimePipelines(using: currentConfig)
        setPipelineEnabledFromCurrentState()
        Task { await refreshModelState() }
        uiModel?.showBanner(kind: .success, title: "Model switched", message: "Now using \(name).")
    }

    private func setOllamaBaseURL(_ url: String) {
        guard var currentConfig else { return }
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        currentConfig.localModel.ollama.baseURL = trimmed
        self.currentConfig = currentConfig
        Task { await configStore.updateLocalModel(currentConfig.localModel) }
        rebuildRuntimePipelines(using: currentConfig)
        setPipelineEnabledFromCurrentState()
        refreshOllama()
    }

    private func refreshOllama() {
        let service = ollamaService()
        Task { @MainActor in
            let running = await service.isRunning()
            let installed = await (try? service.listInstalled()) ?? []
            uiModel?.ollamaRunning = running
            uiModel?.ollamaInstalled = installed
        }
    }

    private func refreshLlamaCpp() {
        guard let baseURL = currentConfig?.localModel.llamaCpp.baseURL else { return }
        let runtime = LlamaCppInferenceRuntime(
            baseURL: baseURL,
            personalizationEngine: personalizationEngine
        )
        Task { @MainActor in
            let reachable = await runtime.isAvailable()
            uiModel?.llamaCppReachable = reachable
        }
    }

    private func setLlamaCppBaseURL(_ url: String) {
        guard var currentConfig else { return }
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        currentConfig.localModel.llamaCpp.baseURL = trimmed
        self.currentConfig = currentConfig
        Task { await configStore.updateLocalModel(currentConfig.localModel) }
        rebuildRuntimePipelines(using: currentConfig)
        setPipelineEnabledFromCurrentState()
        refreshLlamaCpp()
    }

    private func pullOllamaModel(_ name: String) {
        let service = ollamaService()
        Task { @MainActor in
            do {
                for try await progress in service.pull(name) {
                    uiModel?.ollamaPulls[name] = progress
                }
                uiModel?.ollamaPulls[name] = nil
                refreshOllama()
                setOllamaModel(name)
            } catch {
                uiModel?.ollamaPulls[name] = nil
                uiModel?.showBanner(
                    kind: .error,
                    title: "Download failed",
                    message: Self.friendlyModelSetupMessage(for: error)
                )
            }
        }
    }

    private func deleteOllamaModel(_ name: String) {
        let service = ollamaService()
        Task { @MainActor in
            do {
                try await service.delete(name)
                refreshOllama()
                uiModel?.showBanner(kind: .success, title: "Model deleted", message: "Removed \(name).")
            } catch {
                uiModel?.showBanner(
                    kind: .error,
                    title: "Delete failed",
                    message: Self.friendlyModelSetupMessage(for: error)
                )
            }
        }
    }

    private func rollbackModel() {
        do {
            try modelManager.rollbackActiveModel()
            localModelSession.invalidate()
            coreMLModelAdapter.invalidate()
            lastModelError = nil
            refreshPresentation()
            Task { await refreshModelState() }
            uiModel?.showBanner(
                kind: .success,
                title: "Rollback complete",
                message: "The previous model is active again."
            )
        } catch {
            lastModelError = error.localizedDescription
            refreshPresentation()
        }
    }

    private func saveModelSource(_ draft: ModelSourceDraft) {
        guard var currentConfig else { return }
        guard draft.validationMessage() == nil else { return }

        let updatedSource = draft.makeSource(using: currentConfig.localModel.customSource)
        currentConfig.localModel.customSource = updatedSource
        self.currentConfig = currentConfig

        if updatedSource.sourceType == .huggingFace, !draft.huggingFaceToken.isEmpty {
            do {
                try secretStore.upsert(
                    account: updatedSource.huggingFace.tokenKeychainAccount,
                    secret: draft.huggingFaceToken
                )
            } catch {
                lastModelError = error.localizedDescription
                refreshPresentation()
                return
            }
        }

        guard let request = buildCustomDownloadRequest(from: updatedSource) else {
            lastModelError = "Could not resolve a valid model download URL."
            refreshPresentation()
            return
        }

        Task { @MainActor in
            await configStore.updateLocalModel(currentConfig.localModel)
            setModelDownloadState(active: true)
            do {
                try await modelDownloadManager.downloadCustomModel(request)
                await configStore.markModelPresent()
                var refreshedConfig = currentConfig
                refreshedConfig.localModel.isModelPresent = true
                self.currentConfig = refreshedConfig
                localModelSession.invalidate()
                coreMLModelAdapter.invalidate()
                lastModelError = nil
                setModelDownloadState(active: false)
                rebuildRuntimePipelines(using: refreshedConfig)
                refreshPresentation()
                Task { await refreshModelState() }
                uiModel?.showBanner(
                    kind: .success,
                    title: "Model installed",
                    message: "Downloaded and activated \(updatedSource.modelID) \(updatedSource.version)."
                )
            } catch {
                lastModelError = Self.friendlyModelSetupMessage(for: error)
                setModelDownloadState(active: false)
                refreshPresentation()
                uiModel?.showBanner(
                    kind: .error,
                    title: "Model download failed",
                    message: Self.friendlyModelSetupMessage(for: error)
                )
            }
        }
    }

    private func retryModelAcquisition() {
        guard let currentConfig else { return }
        Task { @MainActor in
            setModelDownloadState(active: true)
            do {
                try await ensureModelAvailable(config: currentConfig)
                setModelDownloadState(active: false)
                rebuildRuntimePipelines(using: self.currentConfig ?? currentConfig)
                lastModelError = nil
                refreshPresentation()
                Task { await refreshModelState() }
                uiModel?.showBanner(
                    kind: .success,
                    title: "Model ready",
                    message: "Bootstrap completed successfully."
                )
            } catch {
                setModelDownloadState(active: false)
                lastModelError = Self.friendlyModelSetupMessage(for: error)
                refreshPresentation()
                uiModel?.showBanner(
                    kind: .warning,
                    title: "Model retry failed",
                    message: Self.friendlyModelSetupMessage(for: error)
                )
            }
        }
    }

    private func toggleRuleEnabled(_ rule: ExclusionRule, enabled: Bool) {
        guard var currentConfig else { return }
        guard let index = currentConfig.exclusions.userRules.firstIndex(of: rule) else { return }
        currentConfig.exclusions.userRules[index].enabled = enabled
        self.currentConfig = currentConfig

        Task {
            await configStore.updateExclusionRules(currentConfig.exclusions.userRules)
        }
        rebuildRuntimePipelines(using: currentConfig)
        refreshPresentation()
        setPipelineEnabledFromCurrentState()
    }

    private func saveExclusionRule(_ draft: ExclusionRuleDraft, originalRule: ExclusionRule?) {
        guard draft.validationMessage() == nil else { return }
        guard var currentConfig else { return }
        let newRule = draft.makeRule()

        if let originalRule, let index = currentConfig.exclusions.userRules.firstIndex(of: originalRule) {
            currentConfig.exclusions.userRules[index] = newRule
        } else {
            currentConfig.exclusions.userRules.append(newRule)
        }

        self.currentConfig = currentConfig
        Task {
            await configStore.updateExclusionRules(currentConfig.exclusions.userRules)
        }
        rebuildRuntimePipelines(using: currentConfig)
        refreshPresentation()
    }

    private func deleteExclusionRule(_ rule: ExclusionRule) {
        guard var currentConfig else { return }
        currentConfig.exclusions.userRules.removeAll { $0 == rule }
        self.currentConfig = currentConfig
        Task {
            await configStore.updateExclusionRules(currentConfig.exclusions.userRules)
        }
        rebuildRuntimePipelines(using: currentConfig)
        refreshPresentation()
    }

    private func applyExclusionPreset(_ bundleID: String) {
        guard var currentConfig else { return }
        let rule = ExclusionRule(
            enabled: true,
            bundleID: bundleID,
            windowTitleContains: nil,
            contentPattern: nil
        )
        guard !currentConfig.exclusions.userRules.contains(rule) else { return }

        currentConfig.exclusions.userRules.append(rule)
        self.currentConfig = currentConfig
        Task {
            await configStore.updateExclusionRules(currentConfig.exclusions.userRules)
        }
        rebuildRuntimePipelines(using: currentConfig)
        refreshPresentation()
    }

    private func excludeFrontmostApp() {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return }
        applyExclusionPreset(bundleID)
        uiModel?.showBanner(
            kind: .success,
            title: "App excluded",
            message: "\(bundleID) will no longer receive suggestions."
        )
    }

    private func openAccessibilitySettings() {
        _ = permissionManager.requestAccessibilityPermission()
        permissionManager.openAccessibilitySettings()
    }

    private func openInputMonitoringSettings() {
        _ = permissionManager.requestInputMonitoringPermission()
        permissionManager.openInputMonitoringSettings()
    }

    private func exportDiagnostics() {
        guard let uiModel else { return }
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("autosuggest-diagnostics-\(Int(Date().timeIntervalSince1970)).txt")
        do {
            try uiModel.diagnostics.reportText.write(to: url, atomically: true, encoding: .utf8)
            diagnosticsExportPath = url.path
            refreshPresentation()
            uiModel.showBanner(
                kind: .success,
                title: "Diagnostics exported",
                message: url.path
            )
        } catch {
            lastModelError = error.localizedDescription
            refreshPresentation()
        }
    }

    private func pauseForHour() {
        manualPauseUntil = Date().addingTimeInterval(3600)
        refreshPresentation()
        setPipelineEnabledFromCurrentState()
        uiModel?.showBanner(
            kind: .info,
            title: "Paused for one hour",
            message: "Suggestions will resume automatically."
        )
    }

    private func applyOnboardingModelChoice(_ choice: OnboardingModelChoice) {
        guard var currentConfig else { return }
        switch choice {
        case .ollama:
            currentConfig.localModel.runtimeOrder = ["ollama", "coreml", "llama.cpp"]
        case .llamaCpp:
            currentConfig.localModel.runtimeOrder = ["llama.cpp", "ollama", "coreml"]
        case .coreML:
            currentConfig.localModel.runtimeOrder = ["coreml", "ollama", "llama.cpp"]
        }
        self.currentConfig = currentConfig
        Task {
            await configStore.updateLocalModel(currentConfig.localModel)
        }
        rebuildRuntimePipelines(using: currentConfig)
        refreshPresentation()
        Task { await refreshModelState() }
    }

    private func updateOnlineLLMEnabled(_ enabled: Bool) {
        mutateConfig({ config in
            config.onlineLLM.enabled = enabled
        }, persist: { [weak self] configStore in
            guard let self else { return }
            await configStore.updateOnlineLLM(currentConfig?.onlineLLM ?? AppConfig.default.onlineLLM)
        }, rebuildPipelines: true)
    }

    private func updateOnlineLLMProvider(_ provider: OnlineLLMProvider) {
        mutateConfig({ config in
            config.onlineLLM.byok.provider = provider
            config.onlineLLM.byok.selectedModel = provider.defaultModel
            config.onlineLLM.byok.endpointURL = provider.defaultEndpoint
        }, persist: { [weak self] configStore in
            guard let self else { return }
            await configStore.updateOnlineLLM(currentConfig?.onlineLLM ?? AppConfig.default.onlineLLM)
        }, rebuildPipelines: true)
    }

    private func updateOnlineLLMModel(_ model: String) {
        mutateConfig { config in
            config.onlineLLM.byok.selectedModel = model
        } persist: { [weak self] configStore in
            guard let self else { return }
            await configStore.updateOnlineLLM(currentConfig?.onlineLLM ?? AppConfig.default.onlineLLM)
        }
    }

    private func updateOnlineLLMEndpoint(_ endpoint: String) {
        mutateConfig({ config in
            config.onlineLLM.byok.endpointURL = endpoint
        }, persist: { [weak self] configStore in
            guard let self else { return }
            await configStore.updateOnlineLLM(currentConfig?.onlineLLM ?? AppConfig.default.onlineLLM)
        }, rebuildPipelines: true)
    }

    private func updateOnlineLLMPriority(_ priority: OnlineLLMPriority) {
        mutateConfig({ config in
            config.onlineLLM.byok.priority = priority
        }, persist: { [weak self] configStore in
            guard let self else { return }
            await configStore.updateOnlineLLM(currentConfig?.onlineLLM ?? AppConfig.default.onlineLLM)
        }, rebuildPipelines: true)
    }

    private func updateOnlineLLMAPIKey(_ key: String) {
        guard let currentConfig else { return }
        do {
            try secretStore.upsert(
                account: currentConfig.onlineLLM.byok.apiKeyKeychainAccount,
                secret: key
            )
        } catch {
            logger.error("Failed to store API key: \(error.localizedDescription)")
        }
        rebuildRuntimePipelines(using: currentConfig)
        setPipelineEnabledFromCurrentState()
    }

    private func updateTrainingDataCollection(_ enabled: Bool) {
        mutateConfig { config in
            config.privacy.trainingDataCollectionEnabled = enabled
        } persist: { [weak self] configStore in
            await configStore.updatePrivacy(self?.currentConfig?.privacy ?? AppConfig.default.privacy)
        }
        trainingDataExporter = TrainingDataExporter(enabled: enabled)
        if let currentConfig {
            rebuildRuntimePipelines(using: currentConfig)
            setPipelineEnabledFromCurrentState()
        }
    }

    private func exportTrainingData() {
        Task { @MainActor in
            do {
                let url = try await trainingDataExporter.exportAnonymized()
                uiModel?.showBanner(
                    kind: .success,
                    title: "Training data exported",
                    message: url.path
                )
            } catch {
                uiModel?.showBanner(
                    kind: .error,
                    title: "Export failed",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func clearTrainingData() {
        Task { @MainActor in
            await trainingDataExporter.clearTrainingData()
            uiModel?.showBanner(
                kind: .success,
                title: "Training data cleared",
                message: "All locally stored training pairs have been removed."
            )
        }
    }

    private func updatePersonalization(_ enabled: Bool) {
        mutateConfig { config in
            config.privacy.personalizationEnabled = enabled
        } persist: { [weak self] configStore in
            await configStore.updatePrivacy(self?.currentConfig?.privacy ?? AppConfig.default.privacy)
        }
        Task { await personalizationEngine.setEnabled(enabled) }
    }

    private func clearPersonalizationData() {
        Task { @MainActor in
            await personalizationEngine.clearAll()
            refreshPersonalizationStats()
            uiModel?.showBanner(
                kind: .success,
                title: "Personalization data cleared",
                message: "All locally stored acceptance history has been removed."
            )
        }
    }

    private func refreshPersonalizationStats() {
        Task { @MainActor in
            let stats = await personalizationEngine.stats()
            uiModel?.personalizationStats = (unique: stats.uniqueCount, total: stats.totalAcceptances)
        }
    }

    private func deriveActiveRuntimeLabel(from report: ModelCompatibilityReport) -> String {
        if let ready = report.runtimeHealth.first(where: { $0.ready }) {
            return ready.name
        }
        return "No runtime ready"
    }

    private func deriveActiveModelLabel(activeModelPath: URL?, config: AppConfig) -> String {
        if let activeModelPath {
            return activeModelPath.lastPathComponent
        }
        if config.localModel.ollama.modelName.isEmpty {
            return "No local model"
        }
        return config.localModel.ollama.modelName
    }

    private func derivePauseReason(
        config: AppConfig,
        permissions: PermissionHealth,
        report: ModelCompatibilityReport
    ) -> String? {
        if let manualPauseUntil, manualPauseUntil > Date() {
            return "Paused until \(DateFormatter.localizedString(from: manualPauseUntil, dateStyle: .none, timeStyle: .short))"
        }
        if !permissions.isReady {
            return permissions.summary
        }
        if config.battery.mode == .pauseOnLowPower, ProcessInfo.processInfo.isLowPowerModeEnabled {
            return "Paused because Low Power Mode is on"
        }
        if !report.runtimeHealth.contains(where: \.ready) {
            return "No local runtime is ready"
        }
        return nil
    }

    private func derivePauseRemedy(
        config: AppConfig,
        permissions: PermissionHealth,
        report: ModelCompatibilityReport
    ) -> String? {
        let isManualPause = manualPauseUntil.map { $0 > Date() } ?? false
        return AppCoordinator.derivePauseRemedy(
            isManualPause: isManualPause,
            permissionsReady: permissions.isReady,
            lowPowerPause: config.battery.mode == .pauseOnLowPower && ProcessInfo.processInfo.isLowPowerModeEnabled,
            runtimeReady: report.runtimeHealth.contains(where: \.ready)
        )
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

    private func buildDiagnosticsReport(
        config: AppConfig,
        permissions: PermissionHealth,
        report: ModelCompatibilityReport,
        metrics: MetricsSnapshot
    ) -> String {
        var lines: [String] = []
        lines.append("AutoSuggest Diagnostics")
        lines.append("")
        lines.append("State")
        lines.append("- Enabled: \(config.enabled)")
        lines.append("- Permissions: \(permissions.summary)")
        if let pauseReason = derivePauseReason(config: config, permissions: permissions, report: report) {
            lines.append("- Pause reason: \(pauseReason)")
        }
        lines.append("")
        lines.append("Metrics")
        lines.append("- Suggestions shown: \(metrics.suggestionsShown)")
        lines.append("- Suggestions accepted: \(metrics.suggestionsAccepted)")
        lines.append("- Suggestions dismissed: \(metrics.suggestionsDismissed)")
        lines.append("- Suggestion errors: \(metrics.suggestionErrors)")
        lines.append("- Insertion failures: \(metrics.insertionFailures)")
        if metrics.avgLatencyMs > 0 {
            lines.append("- Average latency: \(Int(metrics.avgLatencyMs.rounded())) ms")
        }
        lines.append("")
        lines.append(report.detailedSummary())
        if let lastModelError {
            lines.append("")
            lines.append("Last model error")
            lines.append(lastModelError)
        }
        return lines.joined(separator: "\n")
    }

    private func buildCustomDownloadRequest(from source: LocalModelCustomSourceConfig) -> CustomModelDownloadRequest? {
        guard let url = modelSourceResolver.resolveDownloadURL(from: source) else {
            return nil
        }

        var headers: [String: String] = [:]
        if source.sourceType == .huggingFace,
           let token = try? secretStore.read(account: source.huggingFace.tokenKeychainAccount),
           !token.isEmpty {
            headers["Authorization"] = "Bearer \(token)"
        }

        return CustomModelDownloadRequest(
            modelID: source.modelID,
            version: source.version,
            downloadURL: url,
            sha256: source.sha256,
            additionalHeaders: headers
        )
    }

    private func setModelDownloadState(active: Bool) {
        guard let uiModel else { return }
        var modelHealth = uiModel.modelHealth
        modelHealth.isDownloading = active
        uiModel.modelHealth = modelHealth
    }

    private func mutateConfig(
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
}
