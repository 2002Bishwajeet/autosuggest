import Foundation

struct AppConfig: Codable {
    static let currentConfigVersion = 2

    var configVersion: Int
    var enabled: Bool
    var distribution: DistributionConfig
    var localModel: LocalModelConfig
    var onlineLLM: OnlineLLMConfig
    var privacy: PrivacyConfig
    var telemetry: TelemetryConfig
    var exclusions: ExclusionConfig
    var battery: BatteryConfig
    var insertion: InsertionConfig
    var shortcuts: ShortcutConfig

    private enum CodingKeys: String, CodingKey {
        case configVersion
        case enabled
        case distribution
        case localModel
        case onlineLLM
        case privacy
        case telemetry
        case exclusions
        case battery
        case insertion
        case shortcuts
    }

    init(
        configVersion: Int = AppConfig.currentConfigVersion,
        enabled: Bool,
        distribution: DistributionConfig,
        localModel: LocalModelConfig,
        onlineLLM: OnlineLLMConfig,
        privacy: PrivacyConfig,
        telemetry: TelemetryConfig,
        exclusions: ExclusionConfig,
        battery: BatteryConfig,
        insertion: InsertionConfig,
        shortcuts: ShortcutConfig
    ) {
        self.configVersion = configVersion
        self.enabled = enabled
        self.distribution = distribution
        self.localModel = localModel
        self.onlineLLM = onlineLLM
        self.privacy = privacy
        self.telemetry = telemetry
        self.exclusions = exclusions
        self.battery = battery
        self.insertion = insertion
        self.shortcuts = shortcuts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        configVersion = try container.decodeIfPresent(Int.self, forKey: .configVersion) ?? 0
        enabled = try container.decode(Bool.self, forKey: .enabled)
        distribution = try container.decode(DistributionConfig.self, forKey: .distribution)
        localModel = try container.decode(LocalModelConfig.self, forKey: .localModel)
        onlineLLM = try container.decode(OnlineLLMConfig.self, forKey: .onlineLLM)
        privacy = try container.decodeIfPresent(PrivacyConfig.self, forKey: .privacy)
            ?? PrivacyConfig(
                encryptedStorageEnabled: true,
                piiFilteringEnabled: true,
                trainingAllowlistBundleIDs: [],
                trainingDataCollectionEnabled: false
            )
        telemetry = try container.decodeIfPresent(TelemetryConfig.self, forKey: .telemetry)
            ?? TelemetryConfig(enabled: false, localStoreOnly: true)
        exclusions = try container.decodeIfPresent(ExclusionConfig.self, forKey: .exclusions)
            ?? ExclusionConfig(userRules: [])
        battery = try container.decodeIfPresent(BatteryConfig.self, forKey: .battery)
            ?? BatteryConfig(mode: .alwaysOn)
        insertion = try container.decodeIfPresent(InsertionConfig.self, forKey: .insertion)
            ?? InsertionConfig(strictUndoSemantics: true)
        shortcuts = try container.decodeIfPresent(ShortcutConfig.self, forKey: .shortcuts)
            ?? ShortcutConfig(acceptKeyCodes: [48, 36, 76], dismissKeyCodes: [53])
    }
}

struct DistributionConfig: Codable {
    var notarizationEnabled: Bool
    var releaseChannel: String
}

struct LocalModelConfig: Codable {
    var autoDownloadOnFirstRun: Bool
    var preferredRuntime: String
    var runtimeOrder: [String]
    var fallbackRuntimeEnabled: Bool
    var fallbackModelName: String
    var isModelPresent: Bool
    var manifestSourceURL: URL
    var fallbackManifest: ModelManifest
    var customSource: LocalModelCustomSourceConfig
    var ollama: OllamaRuntimeConfig
    var llamaCpp: LlamaCppRuntimeConfig

    private enum CodingKeys: String, CodingKey {
        case autoDownloadOnFirstRun
        case preferredRuntime
        case runtimeOrder
        case fallbackRuntimeEnabled
        case fallbackModelName
        case isModelPresent
        case manifestSourceURL
        case fallbackManifest
        case customSource
        case ollama
        case llamaCpp
        case manifest
    }

    init(
        autoDownloadOnFirstRun: Bool,
        preferredRuntime: String,
        runtimeOrder: [String],
        fallbackRuntimeEnabled: Bool,
        fallbackModelName: String,
        isModelPresent: Bool,
        manifestSourceURL: URL,
        fallbackManifest: ModelManifest,
        customSource: LocalModelCustomSourceConfig,
        ollama: OllamaRuntimeConfig,
        llamaCpp: LlamaCppRuntimeConfig
    ) {
        self.autoDownloadOnFirstRun = autoDownloadOnFirstRun
        self.preferredRuntime = preferredRuntime
        self.runtimeOrder = runtimeOrder
        self.fallbackRuntimeEnabled = fallbackRuntimeEnabled
        self.fallbackModelName = fallbackModelName
        self.isModelPresent = isModelPresent
        self.manifestSourceURL = manifestSourceURL
        self.fallbackManifest = fallbackManifest
        self.customSource = customSource
        self.ollama = ollama
        self.llamaCpp = llamaCpp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoDownloadOnFirstRun = try container.decode(Bool.self, forKey: .autoDownloadOnFirstRun)
        preferredRuntime = try container.decode(String.self, forKey: .preferredRuntime)
        runtimeOrder = try container.decodeIfPresent([String].self, forKey: .runtimeOrder)
            ?? ["ollama", "llama.cpp", "coreml"]
        fallbackRuntimeEnabled = try container.decode(Bool.self, forKey: .fallbackRuntimeEnabled)
        fallbackModelName = try container.decodeIfPresent(String.self, forKey: .fallbackModelName)
            ?? "qwen2.5:1.5b"
        isModelPresent = try container.decode(Bool.self, forKey: .isModelPresent)
        manifestSourceURL = try container.decodeIfPresent(URL.self, forKey: .manifestSourceURL)
            ?? defaultManifestURL
        fallbackManifest = try container.decodeIfPresent(ModelManifest.self, forKey: .fallbackManifest)
            ?? container.decode(ModelManifest.self, forKey: .manifest)
        customSource = try container.decodeIfPresent(LocalModelCustomSourceConfig.self, forKey: .customSource)
            ?? .default
        ollama = try container.decodeIfPresent(OllamaRuntimeConfig.self, forKey: .ollama)
            ?? OllamaRuntimeConfig(baseURL: "http://127.0.0.1:11434", modelName: "qwen2.5:1.5b")
        llamaCpp = try container.decodeIfPresent(LlamaCppRuntimeConfig.self, forKey: .llamaCpp)
            ?? LlamaCppRuntimeConfig(baseURL: "http://127.0.0.1:8080")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(autoDownloadOnFirstRun, forKey: .autoDownloadOnFirstRun)
        try container.encode(preferredRuntime, forKey: .preferredRuntime)
        try container.encode(runtimeOrder, forKey: .runtimeOrder)
        try container.encode(fallbackRuntimeEnabled, forKey: .fallbackRuntimeEnabled)
        try container.encode(fallbackModelName, forKey: .fallbackModelName)
        try container.encode(isModelPresent, forKey: .isModelPresent)
        try container.encode(manifestSourceURL, forKey: .manifestSourceURL)
        try container.encode(fallbackManifest, forKey: .fallbackManifest)
        try container.encode(customSource, forKey: .customSource)
        try container.encode(ollama, forKey: .ollama)
        try container.encode(llamaCpp, forKey: .llamaCpp)
    }
}

enum LocalModelSourceType: String, Codable {
    case directURL = "direct_url"
    case huggingFace = "hugging_face"
}

struct LocalModelCustomSourceConfig: Codable {
    var sourceType: LocalModelSourceType
    var modelID: String
    var version: String
    var sha256: String
    var directURL: String
    var huggingFace: HuggingFaceModelSourceConfig
}

struct HuggingFaceModelSourceConfig: Codable {
    var repoID: String
    var revision: String
    var filePath: String
    var tokenKeychainAccount: String
}

extension LocalModelCustomSourceConfig {
    static let `default` = LocalModelCustomSourceConfig(
        sourceType: .directURL,
        modelID: "custom-local-model",
        version: "0.1.0",
        sha256: "",
        directURL: "",
        huggingFace: HuggingFaceModelSourceConfig(
            repoID: "",
            revision: "main",
            filePath: "",
            tokenKeychainAccount: "autosuggest.huggingface.token"
        )
    )
}

struct OllamaRuntimeConfig: Codable {
    var baseURL: String
    var modelName: String
}

struct LlamaCppRuntimeConfig: Codable {
    var baseURL: String
}

struct OnlineLLMConfig: Codable {
    var enabled: Bool
    var rolloutStage: String
    var byok: BYOKConfig

    private enum CodingKeys: String, CodingKey {
        case enabled
        case rolloutStage
        case byok
    }

    init(enabled: Bool, rolloutStage: String, byok: BYOKConfig) {
        self.enabled = enabled
        self.rolloutStage = rolloutStage
        self.byok = byok
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        rolloutStage = try container.decode(String.self, forKey: .rolloutStage)
        byok = try container.decodeIfPresent(BYOKConfig.self, forKey: .byok) ?? .default
    }
}

enum OnlineLLMProvider: String, Codable, CaseIterable, Identifiable, Hashable {
    case openAICompatible = "openai-compatible"
    case anthropic = "anthropic"
    case openRouter = "openrouter"
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAICompatible: return "OpenAI-Compatible"
        case .anthropic: return "Anthropic"
        case .openRouter: return "OpenRouter"
        case .custom: return "Custom Endpoint"
        }
    }

    var defaultEndpoint: String {
        switch self {
        case .openAICompatible: return "https://api.openai.com"
        case .anthropic: return "https://api.anthropic.com"
        case .openRouter: return "https://openrouter.ai/api"
        case .custom: return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .openAICompatible: return "gpt-4o-mini"
        case .anthropic: return "claude-3-haiku-20240307"
        case .openRouter: return "openai/gpt-4o-mini"
        case .custom: return "default"
        }
    }

    var requiresEndpointField: Bool {
        self == .custom
    }
}

enum OnlineLLMPriority: String, Codable, Hashable {
    case primary
    case fallback
}

struct BYOKConfig: Codable {
    var provider: OnlineLLMProvider
    var selectedModel: String
    var endpointURL: String?
    var apiKeyKeychainAccount: String
    var priority: OnlineLLMPriority

    private enum CodingKeys: String, CodingKey {
        case provider
        case selectedProvider
        case selectedModel
        case endpointURL
        case apiKeyKeychainAccount
        case priority
    }

    init(
        provider: OnlineLLMProvider,
        selectedModel: String,
        endpointURL: String?,
        apiKeyKeychainAccount: String,
        priority: OnlineLLMPriority = .fallback
    ) {
        self.provider = provider
        self.selectedModel = selectedModel
        self.endpointURL = endpointURL
        self.apiKeyKeychainAccount = apiKeyKeychainAccount
        self.priority = priority
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Support legacy "selectedProvider" string
        if let providerEnum = try container.decodeIfPresent(OnlineLLMProvider.self, forKey: .provider) {
            provider = providerEnum
        } else if let legacyString = try container.decodeIfPresent(String.self, forKey: .selectedProvider) {
            provider = OnlineLLMProvider(rawValue: legacyString) ?? .openAICompatible
        } else {
            provider = .openAICompatible
        }

        selectedModel = try container.decodeIfPresent(String.self, forKey: .selectedModel) ?? provider.defaultModel
        endpointURL = try container.decodeIfPresent(String.self, forKey: .endpointURL)
        apiKeyKeychainAccount = try container.decodeIfPresent(String.self, forKey: .apiKeyKeychainAccount) ?? "autosuggest.online.byok.default"
        priority = try container.decodeIfPresent(OnlineLLMPriority.self, forKey: .priority) ?? .fallback
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(provider, forKey: .provider)
        try container.encode(selectedModel, forKey: .selectedModel)
        try container.encodeIfPresent(endpointURL, forKey: .endpointURL)
        try container.encode(apiKeyKeychainAccount, forKey: .apiKeyKeychainAccount)
        try container.encode(priority, forKey: .priority)
    }
}

extension BYOKConfig {
    static let `default` = BYOKConfig(
        provider: .openAICompatible,
        selectedModel: "gpt-4o-mini",
        endpointURL: nil,
        apiKeyKeychainAccount: "autosuggest.online.byok.default",
        priority: .fallback
    )
}

struct PrivacyConfig: Codable {
    var encryptedStorageEnabled: Bool
    var piiFilteringEnabled: Bool
    var trainingAllowlistBundleIDs: [String]
    var trainingDataCollectionEnabled: Bool

    private enum CodingKeys: String, CodingKey {
        case encryptedStorageEnabled
        case piiFilteringEnabled
        case trainingAllowlistBundleIDs
        case trainingDataCollectionEnabled
    }

    init(
        encryptedStorageEnabled: Bool,
        piiFilteringEnabled: Bool,
        trainingAllowlistBundleIDs: [String],
        trainingDataCollectionEnabled: Bool = false
    ) {
        self.encryptedStorageEnabled = encryptedStorageEnabled
        self.piiFilteringEnabled = piiFilteringEnabled
        self.trainingAllowlistBundleIDs = trainingAllowlistBundleIDs
        self.trainingDataCollectionEnabled = trainingDataCollectionEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        encryptedStorageEnabled = try container.decode(Bool.self, forKey: .encryptedStorageEnabled)
        piiFilteringEnabled = try container.decode(Bool.self, forKey: .piiFilteringEnabled)
        trainingAllowlistBundleIDs = try container.decode([String].self, forKey: .trainingAllowlistBundleIDs)
        trainingDataCollectionEnabled = try container.decodeIfPresent(Bool.self, forKey: .trainingDataCollectionEnabled) ?? false
    }
}

struct TelemetryConfig: Codable {
    var enabled: Bool
    var localStoreOnly: Bool
}

struct ExclusionConfig: Codable {
    var userRules: [ExclusionRule]
}

struct BatteryConfig: Codable {
    var mode: BatteryMode
}

struct InsertionConfig: Codable {
    var strictUndoSemantics: Bool
}

struct ShortcutConfig: Codable {
    var acceptKeyCodes: [UInt16]
    var dismissKeyCodes: [UInt16]
}

enum BatteryMode: String, Codable {
    case alwaysOn = "always_on"
    case pauseOnLowPower = "pause_on_low_power"
}

struct ExclusionRule: Codable, Equatable {
    var enabled: Bool
    var bundleID: String?
    var windowTitleContains: String?
    var contentPattern: String?
}

private let defaultManifestURL = URL(string: "https://raw.githubusercontent.com/autosuggest/models/main/manifest/stable.json")
    ?? URL(fileURLWithPath: "/dev/null")

extension AppConfig {
    static let `default` = AppConfig(
        enabled: true,
        distribution: DistributionConfig(
            notarizationEnabled: false,
            releaseChannel: "unsigned-pre-mvp"
        ),
        localModel: LocalModelConfig(
            autoDownloadOnFirstRun: false,
            preferredRuntime: "ollama",
            runtimeOrder: ["ollama", "llama.cpp", "coreml"],
            fallbackRuntimeEnabled: true,
            fallbackModelName: "qwen2.5:1.5b",
            isModelPresent: false,
            manifestSourceURL: defaultManifestURL,
            fallbackManifest: .initial,
            customSource: .default,
            ollama: OllamaRuntimeConfig(
                baseURL: "http://127.0.0.1:11434",
                modelName: "qwen2.5:1.5b"
            ),
            llamaCpp: LlamaCppRuntimeConfig(
                baseURL: "http://127.0.0.1:8080"
            )
        ),
        onlineLLM: OnlineLLMConfig(
            enabled: false,
            rolloutStage: "available",
            byok: .default
        ),
        privacy: PrivacyConfig(
            encryptedStorageEnabled: true,
            piiFilteringEnabled: true,
            trainingAllowlistBundleIDs: [],
            trainingDataCollectionEnabled: false
        ),
        telemetry: TelemetryConfig(
            enabled: false,
            localStoreOnly: true
        ),
        exclusions: ExclusionConfig(
            userRules: []
        ),
        battery: BatteryConfig(
            mode: .alwaysOn
        ),
        insertion: InsertionConfig(
            strictUndoSemantics: true
        ),
        shortcuts: ShortcutConfig(
            acceptKeyCodes: [48, 36, 76],
            dismissKeyCodes: [53]
        )
    )
}
