import Foundation

extension AppCoordinator {
    func bootstrapInitialModelIfNeeded() async throws {
        guard let currentConfig else { return }
        try await ensureModelAvailable(config: currentConfig)
    }

    func ensureModelAvailable(config: AppConfig) async throws {
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

    func rebuildRuntimePipelines(using config: AppConfig) {
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
                onlineAPIKey: onlineAPIKey,
                piiFilteringEnabled: config.privacy.piiFilteringEnabled
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
    func prewarmFoundationModelsIfAvailable(config: LocalModelConfig) {
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

    func moveRuntime(from source: Int, to target: Int) {
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

    func switchToInstalledModel(_ model: InstalledModel) {
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

    func rollbackModel() {
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

    func saveModelSource(_ draft: ModelSourceDraft) {
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

    func retryModelAcquisition() {
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

    func setModelDownloadState(active: Bool) {
        guard let uiModel else { return }
        var modelHealth = uiModel.modelHealth
        modelHealth.isDownloading = active
        uiModel.modelHealth = modelHealth
    }

    func buildCustomDownloadRequest(from source: LocalModelCustomSourceConfig) -> CustomModelDownloadRequest? {
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

    func ollamaService() -> OllamaModelService {
        OllamaModelService(baseURL: currentConfig?.localModel.ollama.baseURL ?? "http://127.0.0.1:11434")
    }

    func setOllamaModel(_ name: String) {
        guard var currentConfig else { return }
        currentConfig.localModel.ollama.modelName = name
        self.currentConfig = currentConfig
        Task { await configStore.updateLocalModel(currentConfig.localModel) }
        rebuildRuntimePipelines(using: currentConfig)
        setPipelineEnabledFromCurrentState()
        Task { await refreshModelState() }
        uiModel?.showBanner(kind: .success, title: "Model switched", message: "Now using \(name).")
    }

    func setOllamaBaseURL(_ url: String) {
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

    func refreshOllama() {
        let service = ollamaService()
        Task { @MainActor in
            let running = await service.isRunning()
            let installed = await (try? service.listInstalled()) ?? []
            uiModel?.ollamaRunning = running
            uiModel?.ollamaInstalled = installed
        }
    }

    func pullOllamaModel(_ name: String) {
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

    func deleteOllamaModel(_ name: String) {
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

    func refreshLlamaCpp() {
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

    func setLlamaCppBaseURL(_ url: String) {
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
}
