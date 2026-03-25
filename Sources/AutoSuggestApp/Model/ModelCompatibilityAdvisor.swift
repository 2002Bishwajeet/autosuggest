import Foundation

struct ModelCompatibilityReport {
    let recommendedMaxParamsB: Double
    let hardMaxParamsB: Double
    let totalMemoryGB: Double
    let availableMemoryGB: Double?
    let runtimeHealth: [RuntimeHealth]
    let installedAssessments: [InstalledModelAssessment]
    let suggestedModels: [String]

    func menuSummary() -> String {
        "Model Fit: recommend <= \(formatParams(recommendedMaxParamsB))"
    }

    func detailedSummary() -> String {
        var lines: [String] = []
        lines.append("Device memory: total \(formatGB(totalMemoryGB))")
        if let availableMemoryGB {
            lines.append("Available now: \(formatGB(availableMemoryGB))")
        }
        lines.append("Recommended model size: <= \(formatParams(recommendedMaxParamsB))")
        lines.append("Likely unstable above: \(formatParams(hardMaxParamsB))")
        lines.append("")
        lines.append("Runtime readiness:")
        for item in runtimeHealth {
            let mark = item.ready ? "OK" : "Not Ready"
            lines.append("- \(item.name): \(mark) (\(item.detail))")
        }

        if !installedAssessments.isEmpty {
            lines.append("")
            lines.append("Installed models:")
            for model in installedAssessments {
                lines.append("- \(model.id) \(model.version): \(model.verdict) (\(model.reason))")
            }
        }

        if !suggestedModels.isEmpty {
            lines.append("")
            lines.append("Suggested models (examples):")
            for model in suggestedModels {
                lines.append("- \(model)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func formatGB(_ value: Double) -> String {
        String(format: "%.1f GB", value)
    }

    private func formatParams(_ value: Double) -> String {
        String(format: "%.1fB params", value)
    }
}

struct RuntimeHealth {
    let name: String
    let ready: Bool
    let detail: String
}

struct InstalledModelAssessment {
    let id: String
    let version: String
    let verdict: String
    let reason: String
}

struct ModelCompatibilityAdvisor {
    private let resourceMonitor = SystemResourceMonitor()

    func buildReport(config: LocalModelConfig, installedModels: [InstalledModel]) -> ModelCompatibilityReport {
        let snapshot = resourceMonitor.memorySnapshot()
        return buildReport(
            totalMemoryGB: snapshot.totalGB,
            availableMemoryGB: snapshot.availableGB,
            runtimeOrder: config.runtimeOrder,
            installedModels: installedModels
        )
    }

    func buildReport(
        totalMemoryGB: Double,
        availableMemoryGB: Double?,
        runtimeOrder: [String],
        installedModels: [InstalledModel]
    ) -> ModelCompatibilityReport {
        let tier = memoryTier(totalMemoryGB: totalMemoryGB, availableMemoryGB: availableMemoryGB)
        let orderedRuntimes = runtimeOrder.isEmpty ? ["coreml", "ollama", "llama.cpp"] : runtimeOrder

        let runtimeStatuses = orderedRuntimes.map { name in
            runtimeStatus(for: name, totalMemoryGB: totalMemoryGB, availableMemoryGB: availableMemoryGB)
        }
        let installedAssessments = installedModels.map {
            assessInstalledModel($0, recommendedMaxParamsB: tier.recommendedMaxParamsB, hardMaxParamsB: tier.hardMaxParamsB)
        }

        return ModelCompatibilityReport(
            recommendedMaxParamsB: tier.recommendedMaxParamsB,
            hardMaxParamsB: tier.hardMaxParamsB,
            totalMemoryGB: totalMemoryGB,
            availableMemoryGB: availableMemoryGB,
            runtimeHealth: runtimeStatuses,
            installedAssessments: installedAssessments,
            suggestedModels: suggestedModels(recommendedMaxParamsB: tier.recommendedMaxParamsB)
        )
    }

    private func memoryTier(totalMemoryGB: Double, availableMemoryGB: Double?) -> (recommendedMaxParamsB: Double, hardMaxParamsB: Double) {
        var recommended: Double
        var hardMax: Double

        switch totalMemoryGB {
        case ..<8:
            recommended = 1.5
            hardMax = 2.0
        case ..<16:
            recommended = 3.0
            hardMax = 4.0
        case ..<24:
            recommended = 7.0
            hardMax = 8.0
        case ..<32:
            recommended = 13.0
            hardMax = 14.0
        default:
            recommended = 20.0
            hardMax = 34.0
        }

        if let availableMemoryGB {
            if availableMemoryGB < 2 {
                recommended = min(recommended, 1.5)
                hardMax = min(hardMax, 3.0)
            } else if availableMemoryGB < 4 {
                recommended = min(recommended, 3.0)
                hardMax = min(hardMax, 4.0)
            } else if availableMemoryGB < 8 {
                recommended = min(recommended, 7.0)
                hardMax = min(hardMax, 8.0)
            }
        }

        return (recommended, hardMax)
    }

    private func runtimeStatus(for name: String, totalMemoryGB: Double, availableMemoryGB: Double?) -> RuntimeHealth {
        switch name.lowercased() {
        case "coreml":
            let ready = resourceMonitor.hasSufficientMemoryForPrimaryRuntime()
            let detail = ready
                ? "memory check passed"
                : "low free memory; use smaller model or fallback runtime"
            return RuntimeHealth(name: "coreml", ready: ready, detail: detail)
        case "ollama":
            let ready = isProcessRunning("ollama")
            return RuntimeHealth(
                name: "ollama",
                ready: ready,
                detail: ready ? "local ollama process detected" : "run `ollama serve` first"
            )
        case "llama.cpp", "llamacpp", "llama_cpp":
            let ready = isProcessRunning("llama-server") || isProcessRunning("llama.cpp")
            return RuntimeHealth(
                name: "llama.cpp",
                ready: ready,
                detail: ready ? "llama.cpp server detected" : "start `llama-server` first"
            )
        default:
            let detail = "custom runtime '\(name)' configured"
            return RuntimeHealth(name: name, ready: false, detail: detail)
        }
    }

    private func assessInstalledModel(_ model: InstalledModel, recommendedMaxParamsB: Double, hardMaxParamsB: Double) -> InstalledModelAssessment {
        let estimated = parseParamsB(from: "\(model.id) \(model.version) \(model.path.lastPathComponent)")
        guard let estimated else {
            return InstalledModelAssessment(
                id: model.id,
                version: model.version,
                verdict: "Unknown",
                reason: "cannot infer parameter size from name"
            )
        }

        if estimated <= recommendedMaxParamsB {
            return InstalledModelAssessment(
                id: model.id,
                version: model.version,
                verdict: "Good",
                reason: "estimated \(String(format: "%.1f", estimated))B is within recommended range"
            )
        }
        if estimated <= hardMaxParamsB {
            return InstalledModelAssessment(
                id: model.id,
                version: model.version,
                verdict: "Borderline",
                reason: "estimated \(String(format: "%.1f", estimated))B may be slower on this device"
            )
        }
        return InstalledModelAssessment(
            id: model.id,
            version: model.version,
            verdict: "Not Recommended",
            reason: "estimated \(String(format: "%.1f", estimated))B is likely too large for stable local use"
        )
    }

    private func parseParamsB(from text: String) -> Double? {
        let pattern = #"(\d+(?:\.\d+)?)\s*[bB]\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1 else {
            return nil
        }
        let numberRange = match.range(at: 1)
        guard numberRange.location != NSNotFound else { return nil }
        let numberString = nsText.substring(with: numberRange)
        return Double(numberString)
    }

    private func suggestedModels(recommendedMaxParamsB: Double) -> [String] {
        if recommendedMaxParamsB <= 1.5 {
            return [
                "qwen2.5:1.5b (Ollama)",
                "TinyLlama 1.1B GGUF (llama.cpp)",
                "autosuggest-small-1b (CoreML)",
            ]
        }
        if recommendedMaxParamsB <= 3.0 {
            return [
                "qwen2.5:1.5b (Ollama)",
                "llama3.2:3b (Ollama)",
                "Q4 3B GGUF variants (llama.cpp)",
            ]
        }
        if recommendedMaxParamsB <= 7.0 {
            return [
                "qwen2.5:3b or qwen2.5:7b (Ollama)",
                "mistral:7b (Ollama)",
                "Q4 7B GGUF variants (llama.cpp)",
            ]
        }
        if recommendedMaxParamsB <= 13.0 {
            return [
                "llama3.1:8b (Ollama)",
                "qwen2.5:7b (Ollama)",
                "Q4 8B-13B GGUF variants (llama.cpp)",
            ]
        }
        return [
            "llama3.1:8b-13b class models (Ollama)",
            "qwen2.5:14b class models (Ollama, if memory headroom is stable)",
            "Q4/Q5 13B+ GGUF variants (llama.cpp)",
        ]
    }

    private func isProcessRunning(_ processName: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", processName]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
