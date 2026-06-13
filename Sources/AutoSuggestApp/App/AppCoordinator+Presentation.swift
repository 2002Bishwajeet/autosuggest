import Foundation

extension AppCoordinator {
    func deriveActiveRuntimeLabel(from report: ModelCompatibilityReport) -> String {
        if let ready = report.runtimeHealth.first(where: { $0.ready }) {
            return ready.name
        }
        return "No runtime ready"
    }

    func deriveActiveModelLabel(activeModelPath: URL?, config: AppConfig) -> String {
        if let activeModelPath {
            return activeModelPath.lastPathComponent
        }
        if config.localModel.ollama.modelName.isEmpty {
            return "No local model"
        }
        return config.localModel.ollama.modelName
    }

    func derivePauseReason(
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

    func derivePauseRemedy(
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

    func buildDiagnosticsReport(
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
}
