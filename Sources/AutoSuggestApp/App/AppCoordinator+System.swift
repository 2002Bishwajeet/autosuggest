import AppKit
import Foundation

extension AppCoordinator {
    func openAccessibilitySettings() {
        _ = permissionManager.requestAccessibilityPermission()
        permissionManager.openAccessibilitySettings()
    }

    func openInputMonitoringSettings() {
        _ = permissionManager.requestInputMonitoringPermission()
        permissionManager.openInputMonitoringSettings()
    }

    func exportDiagnostics() {
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

    func pauseForHour() {
        manualPauseUntil = Date().addingTimeInterval(3600)
        refreshPresentation()
        setPipelineEnabledFromCurrentState()
        uiModel?.showBanner(
            kind: .info,
            title: "Paused for one hour",
            message: "Suggestions will resume automatically."
        )
    }

    func applyOnboardingModelChoice(_ choice: OnboardingModelChoice) {
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
}
