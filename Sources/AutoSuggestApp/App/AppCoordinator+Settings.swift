import Foundation

extension AppCoordinator {
    func updateEnabled(_ enabled: Bool) {
        guard var currentConfig else { return }
        currentConfig.enabled = enabled
        self.currentConfig = currentConfig

        Task {
            await configStore.updateEnabled(enabled)
        }
        refreshPresentation()
        setPipelineEnabledFromCurrentState()
    }

    func updateBatteryMode(_ mode: BatteryMode) {
        mutateConfig { config in
            config.battery.mode = mode
        } persist: { configStore in
            await configStore.updateBattery(BatteryConfig(mode: mode))
        }
    }

    func updateStrictUndo(_ enabled: Bool) {
        mutateConfig({ config in
            config.insertion.strictUndoSemantics = enabled
        }, persist: { configStore in
            await configStore.updateInsertion(InsertionConfig(strictUndoSemantics: enabled))
        }, rebuildPipelines: true)
    }

    func updatePIIFiltering(_ enabled: Bool) {
        mutateConfig { config in
            config.privacy.piiFilteringEnabled = enabled
        } persist: { [weak self] configStore in
            await configStore.updatePrivacy(self?.currentConfig?.privacy ?? AppConfig.default.privacy)
        }
    }

    func updateTelemetryEnabled(_ enabled: Bool) {
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

    func updateTelemetryLocalOnly(_ enabled: Bool) {
        mutateConfig { config in
            config.telemetry.localStoreOnly = enabled
        } persist: { [weak self] configStore in
            await configStore.updateTelemetry(self?.currentConfig?.telemetry ?? AppConfig.default.telemetry)
        }
    }

    func updatePersonalization(_ enabled: Bool) {
        mutateConfig { config in
            config.privacy.personalizationEnabled = enabled
        } persist: { [weak self] configStore in
            await configStore.updatePrivacy(self?.currentConfig?.privacy ?? AppConfig.default.privacy)
        }
        Task { await personalizationEngine.setEnabled(enabled) }
    }

    func clearPersonalizationData() {
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

    func refreshPersonalizationStats() {
        Task { @MainActor in
            let stats = await personalizationEngine.stats()
            uiModel?.personalizationStats = (unique: stats.uniqueCount, total: stats.totalAcceptances)
        }
    }

    func updateTrainingDataCollection(_ enabled: Bool) {
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

    func exportTrainingData() {
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

    func clearTrainingData() {
        Task { @MainActor in
            await trainingDataExporter.clearTrainingData()
            uiModel?.showBanner(
                kind: .success,
                title: "Training data cleared",
                message: "All locally stored training pairs have been removed."
            )
        }
    }

    func updateOnlineLLMEnabled(_ enabled: Bool) {
        mutateConfig({ config in
            config.onlineLLM.enabled = enabled
        }, persist: { [weak self] configStore in
            guard let self else { return }
            await configStore.updateOnlineLLM(currentConfig?.onlineLLM ?? AppConfig.default.onlineLLM)
        }, rebuildPipelines: true)
    }

    func updateOnlineLLMProvider(_ provider: OnlineLLMProvider) {
        mutateConfig({ config in
            config.onlineLLM.byok.provider = provider
            config.onlineLLM.byok.selectedModel = provider.defaultModel
            config.onlineLLM.byok.endpointURL = provider.defaultEndpoint
        }, persist: { [weak self] configStore in
            guard let self else { return }
            await configStore.updateOnlineLLM(currentConfig?.onlineLLM ?? AppConfig.default.onlineLLM)
        }, rebuildPipelines: true)
    }

    func updateOnlineLLMModel(_ model: String) {
        mutateConfig { config in
            config.onlineLLM.byok.selectedModel = model
        } persist: { [weak self] configStore in
            guard let self else { return }
            await configStore.updateOnlineLLM(currentConfig?.onlineLLM ?? AppConfig.default.onlineLLM)
        }
    }

    func updateOnlineLLMEndpoint(_ endpoint: String) {
        mutateConfig({ config in
            config.onlineLLM.byok.endpointURL = endpoint
        }, persist: { [weak self] configStore in
            guard let self else { return }
            await configStore.updateOnlineLLM(currentConfig?.onlineLLM ?? AppConfig.default.onlineLLM)
        }, rebuildPipelines: true)
    }

    func updateOnlineLLMPriority(_ priority: OnlineLLMPriority) {
        mutateConfig({ config in
            config.onlineLLM.byok.priority = priority
        }, persist: { [weak self] configStore in
            guard let self else { return }
            await configStore.updateOnlineLLM(currentConfig?.onlineLLM ?? AppConfig.default.onlineLLM)
        }, rebuildPipelines: true)
    }

    func updateOnlineLLMAPIKey(_ key: String) {
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
}
