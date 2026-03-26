import Foundation

actor ConfigStore {
    private let logger = Logger(scope: "ConfigStore")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var configURL: URL {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AutoSuggestApp/config.json")
        }
        let dir = base.appendingPathComponent("AutoSuggestApp", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("config.json")
    }

    func loadOrCreateDefault() -> AppConfig {
        if let data = try? Data(contentsOf: configURL),
           var config = try? decoder.decode(AppConfig.self, from: data) {
            let migrator = ConfigMigrationManager()
            migrator.migrate(&config)
            let validator = ConfigValidator()
            validator.validate(&config)
            persist(config)
            return config
        }

        let config = AppConfig.default
        persist(config)
        return config
    }

    func updateEnabled(_ enabled: Bool) {
        var config = loadOrCreateDefault()
        config.enabled = enabled
        persist(config)
    }

    func markModelPresent() {
        var config = loadOrCreateDefault()
        config.localModel.isModelPresent = true
        persist(config)
    }

    func updateLocalModel(_ localModel: LocalModelConfig) {
        var config = loadOrCreateDefault()
        config.localModel = localModel
        persist(config)
    }

    func getExclusionRules() -> [ExclusionRule] {
        loadOrCreateDefault().exclusions.userRules
    }

    func updateExclusionRules(_ rules: [ExclusionRule]) {
        var config = loadOrCreateDefault()
        config.exclusions.userRules = rules
        persist(config)
    }

    func updatePrivacy(_ privacy: PrivacyConfig) {
        var config = loadOrCreateDefault()
        config.privacy = privacy
        persist(config)
    }

    func updateTelemetry(_ telemetry: TelemetryConfig) {
        var config = loadOrCreateDefault()
        config.telemetry = telemetry
        persist(config)
    }

    func updateBattery(_ battery: BatteryConfig) {
        var config = loadOrCreateDefault()
        config.battery = battery
        persist(config)
    }

    func updateInsertion(_ insertion: InsertionConfig) {
        var config = loadOrCreateDefault()
        config.insertion = insertion
        persist(config)
    }

    func updateOnlineLLM(_ onlineLLM: OnlineLLMConfig) {
        var config = loadOrCreateDefault()
        config.onlineLLM = onlineLLM
        persist(config)
    }

    func updateFullConfig(_ config: AppConfig) {
        persist(config)
    }

    private func persist(_ config: AppConfig) {
        do {
            let data = try encoder.encode(config)
            try data.write(to: configURL, options: .atomic)
        } catch {
            logger.error("Failed to persist config: \(error.localizedDescription)")
        }
    }
}
