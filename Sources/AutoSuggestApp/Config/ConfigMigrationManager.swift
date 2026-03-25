import Foundation

struct ConfigMigrationManager {
    private let logger = Logger(scope: "ConfigMigrationManager")

    func migrate(_ config: inout AppConfig) {
        let version = config.configVersion

        if version < 1 {
            migrateV0toV1(&config)
        }

        config.configVersion = AppConfig.currentConfigVersion
    }

    private func migrateV0toV1(_ config: inout AppConfig) {
        // V0 had CoreML as default primary runtime. V1 switches to Ollama-first
        // since CoreML tokenization required BPE support that was not available in V0.
        let legacyCoreMLFirst = ["coreml", "ollama", "llama.cpp"]
        if config.localModel.runtimeOrder == legacyCoreMLFirst {
            config.localModel.runtimeOrder = ["ollama", "llama.cpp", "coreml"]
            config.localModel.preferredRuntime = "ollama"
            logger.info("Migrated config v0->v1: reordered runtimes to Ollama-first.")
        }
    }
}

struct ConfigValidator {
    private static let knownRuntimes: Set<String> = ["coreml", "ollama", "llama.cpp"]
    private let logger = Logger(scope: "ConfigValidator")

    func validate(_ config: inout AppConfig) {
        validateRuntimeOrder(&config)
        validateURLs(&config)
        validateExclusionRules(&config)
    }

    private func validateRuntimeOrder(_ config: inout AppConfig) {
        let original = config.localModel.runtimeOrder
        let filtered = original.filter { Self.knownRuntimes.contains($0) }
        if filtered.count != original.count {
            let removed = Set(original).subtracting(Self.knownRuntimes)
            logger.warn("Removed unknown runtimes from order: \(removed.joined(separator: ", "))")
            config.localModel.runtimeOrder = filtered
        }
        if config.localModel.runtimeOrder.isEmpty {
            config.localModel.runtimeOrder = ["ollama", "llama.cpp", "coreml"]
            logger.warn("Runtime order was empty, reset to defaults.")
        }
    }

    private func validateURLs(_ config: inout AppConfig) {
        if !config.localModel.ollama.baseURL.isEmpty,
           URL(string: config.localModel.ollama.baseURL) == nil {
            logger.warn("Invalid Ollama base URL '\(config.localModel.ollama.baseURL)', resetting.")
            config.localModel.ollama.baseURL = "http://127.0.0.1:11434"
        }
        if !config.localModel.llamaCpp.baseURL.isEmpty,
           URL(string: config.localModel.llamaCpp.baseURL) == nil {
            logger.warn("Invalid llama.cpp base URL '\(config.localModel.llamaCpp.baseURL)', resetting.")
            config.localModel.llamaCpp.baseURL = "http://127.0.0.1:8080"
        }
    }

    private func validateExclusionRules(_ config: inout AppConfig) {
        for i in config.exclusions.userRules.indices {
            if let pattern = config.exclusions.userRules[i].contentPattern,
               !pattern.isEmpty {
                do {
                    _ = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
                } catch {
                    logger.warn("Exclusion rule has invalid regex '\(pattern)', disabling rule.")
                    config.exclusions.userRules[i].enabled = false
                }
            }
        }
    }
}
