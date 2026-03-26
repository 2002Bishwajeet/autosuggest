import XCTest
@testable import AutoSuggestApp

final class OnlineLLMInferenceRuntimeTests: XCTestCase {

    // MARK: - Runtime basics

    @MainActor
    func testRuntimeName() {
        let runtime = OnlineLLMInferenceRuntime(
            provider: .openAICompatible,
            model: "gpt-4o-mini",
            endpointURL: nil,
            apiKey: "sk-test"
        )
        XCTAssertEqual(runtime.name, "online")
    }

    @MainActor
    func testIsAvailableWithAPIKey() {
        let runtime = OnlineLLMInferenceRuntime(
            provider: .openAICompatible,
            model: "gpt-4o-mini",
            endpointURL: nil,
            apiKey: "sk-test"
        )
        XCTAssertTrue(runtime.isAvailable())
    }

    @MainActor
    func testIsNotAvailableWithoutAPIKey() {
        let runtime = OnlineLLMInferenceRuntime(
            provider: .openAICompatible,
            model: "gpt-4o-mini",
            endpointURL: nil,
            apiKey: ""
        )
        XCTAssertFalse(runtime.isAvailable())
    }

    // MARK: - Provider configs

    func testOpenAICompatibleDefaults() {
        let provider = OnlineLLMProvider.openAICompatible
        XCTAssertEqual(provider.displayName, "OpenAI-Compatible")
        XCTAssertEqual(provider.defaultEndpoint, "https://api.openai.com")
        XCTAssertEqual(provider.defaultModel, "gpt-4o-mini")
        XCTAssertFalse(provider.requiresEndpointField)
    }

    func testAnthropicDefaults() {
        let provider = OnlineLLMProvider.anthropic
        XCTAssertEqual(provider.displayName, "Anthropic")
        XCTAssertEqual(provider.defaultEndpoint, "https://api.anthropic.com")
        XCTAssertFalse(provider.requiresEndpointField)
    }

    func testOpenRouterDefaults() {
        let provider = OnlineLLMProvider.openRouter
        XCTAssertEqual(provider.displayName, "OpenRouter")
        XCTAssertEqual(provider.defaultEndpoint, "https://openrouter.ai/api")
        XCTAssertFalse(provider.requiresEndpointField)
    }

    func testCustomProviderRequiresEndpoint() {
        XCTAssertTrue(OnlineLLMProvider.custom.requiresEndpointField)
    }

    // MARK: - Factory integration

    @MainActor
    func testFactoryAddsOnlineRuntimeAsFallback() {
        let factory = InferenceRuntimeFactory(
            localModelSession: LocalModelSession(),
            personalizationEngine: PersonalizationEngine(store: EncryptedFileStore()),
            coreMLModelAdapter: CoreMLModelAdapter()
        )
        let config = AppConfig.default.localModel
        let onlineConfig = OnlineLLMConfig(
            enabled: true,
            rolloutStage: "available",
            byok: BYOKConfig(
                provider: .openAICompatible,
                selectedModel: "gpt-4o-mini",
                endpointURL: nil,
                apiKeyKeychainAccount: "test",
                priority: .fallback
            )
        )
        let runtimes = factory.makeRuntimes(
            config: config,
            onlineLLMConfig: onlineConfig,
            onlineAPIKey: "sk-test"
        )
        XCTAssertEqual(runtimes.last?.name, "online")
    }

    @MainActor
    func testFactoryAddsOnlineRuntimeAsPrimary() {
        let factory = InferenceRuntimeFactory(
            localModelSession: LocalModelSession(),
            personalizationEngine: PersonalizationEngine(store: EncryptedFileStore()),
            coreMLModelAdapter: CoreMLModelAdapter()
        )
        let config = AppConfig.default.localModel
        let onlineConfig = OnlineLLMConfig(
            enabled: true,
            rolloutStage: "available",
            byok: BYOKConfig(
                provider: .anthropic,
                selectedModel: "claude-3-haiku",
                endpointURL: nil,
                apiKeyKeychainAccount: "test",
                priority: .primary
            )
        )
        let runtimes = factory.makeRuntimes(
            config: config,
            onlineLLMConfig: onlineConfig,
            onlineAPIKey: "sk-test"
        )
        XCTAssertEqual(runtimes.first?.name, "online")
    }

    // MARK: - BYOKConfig Coding

    func testBYOKConfigRoundTrips() throws {
        let original = BYOKConfig(
            provider: .anthropic,
            selectedModel: "claude-3-haiku",
            endpointURL: "https://api.anthropic.com",
            apiKeyKeychainAccount: "test-account",
            priority: .primary
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BYOKConfig.self, from: data)
        XCTAssertEqual(decoded.provider, .anthropic)
        XCTAssertEqual(decoded.selectedModel, "claude-3-haiku")
        XCTAssertEqual(decoded.priority, .primary)
    }

    func testBYOKConfigLegacyDecoding() throws {
        let legacyJSON = """
        {
            "selectedProvider": "openai-compatible",
            "selectedModel": "gpt-4o-mini",
            "apiKeyKeychainAccount": "test-account"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(BYOKConfig.self, from: legacyJSON)
        XCTAssertEqual(decoded.provider, .openAICompatible)
        XCTAssertEqual(decoded.selectedModel, "gpt-4o-mini")
        XCTAssertEqual(decoded.priority, .fallback)
    }

    // MARK: - Error descriptions

    func testInvalidAPIKeyErrorDescription() {
        let error = InferenceError.invalidAPIKey
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("API key"))
    }

    func testRateLimitedErrorDescription() {
        let error = InferenceError.rateLimited(retryAfterSeconds: 30)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("30"))
    }

    func testNetworkErrorDescription() {
        let underlying = URLError(.notConnectedToInternet)
        let error = InferenceError.networkError(underlying: underlying)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Network"))
    }

    func testProviderErrorDescription() {
        let error = InferenceError.providerError(statusCode: 500, message: "Internal Server Error")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("500"))
    }
}
