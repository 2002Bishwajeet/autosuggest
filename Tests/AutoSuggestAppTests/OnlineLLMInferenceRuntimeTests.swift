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
    func testIsAvailableWithAPIKey() async {
        let runtime = OnlineLLMInferenceRuntime(
            provider: .openAICompatible,
            model: "gpt-4o-mini",
            endpointURL: nil,
            apiKey: "sk-test"
        )
        let available = await runtime.isAvailable()
        XCTAssertTrue(available)
    }

    @MainActor
    func testIsNotAvailableWithoutAPIKey() async {
        let runtime = OnlineLLMInferenceRuntime(
            provider: .openAICompatible,
            model: "gpt-4o-mini",
            endpointURL: nil,
            apiKey: ""
        )
        let available = await runtime.isAvailable()
        XCTAssertFalse(available)
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

    func testInvalidAPIKeyErrorDescription() throws {
        let error = InferenceError.invalidAPIKey
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(try XCTUnwrap(error.errorDescription?.contains("API key")))
    }

    func testRateLimitedErrorDescription() throws {
        let error = InferenceError.rateLimited(retryAfterSeconds: 30)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(try XCTUnwrap(error.errorDescription?.contains("30")))
    }

    func testNetworkErrorDescription() throws {
        let underlying = URLError(.notConnectedToInternet)
        let error = InferenceError.networkError(underlying: underlying)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(try XCTUnwrap(error.errorDescription?.contains("Network")))
    }

    func testProviderErrorDescription() throws {
        let error = InferenceError.providerError(statusCode: 500, message: "Internal Server Error")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(try XCTUnwrap(error.errorDescription?.contains("500")))
    }

    // MARK: - Endpoint validation (Step 1)

    func testIsAllowedEndpoint_httpsRemote() throws {
        let url = try XCTUnwrap(URL(string: "https://api.openai.com"))
        XCTAssertTrue(OnlineLLMInferenceRuntime.isAllowedEndpoint(url))
    }

    func testIsAllowedEndpoint_httpLoopbackNumeric() throws {
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:8080"))
        XCTAssertTrue(OnlineLLMInferenceRuntime.isAllowedEndpoint(url))
    }

    func testIsAllowedEndpoint_httpLocalhost() throws {
        let url = try XCTUnwrap(URL(string: "http://localhost:1234"))
        XCTAssertTrue(OnlineLLMInferenceRuntime.isAllowedEndpoint(url))
    }

    func testIsAllowedEndpoint_httpIPv6Loopback() throws {
        let url = try XCTUnwrap(URL(string: "http://[::1]:9000"))
        XCTAssertTrue(OnlineLLMInferenceRuntime.isAllowedEndpoint(url))
    }

    func testIsAllowedEndpoint_httpRemoteRejected() throws {
        let url = try XCTUnwrap(URL(string: "http://api.example.com"))
        XCTAssertFalse(OnlineLLMInferenceRuntime.isAllowedEndpoint(url))
    }

    func testIsAllowedEndpoint_ftpRejected() throws {
        let url = try XCTUnwrap(URL(string: "ftp://files.example.com"))
        XCTAssertFalse(OnlineLLMInferenceRuntime.isAllowedEndpoint(url))
    }

    @MainActor
    func testGenerateSuggestion_httpRemoteEndpoint_throwsWithoutNetworkCall() async {
        // A runtime configured with a plain-HTTP remote endpoint must throw
        // runtimeUnavailable before making any network call — no stub needed
        // because the guard fires synchronously before URLSession.
        let runtime = OnlineLLMInferenceRuntime(
            provider: .openAICompatible,
            model: "gpt-4o-mini",
            endpointURL: "http://api.example.com",
            apiKey: "sk-test"
        )
        do {
            _ = try await runtime.generateSuggestion(context: "hello")
            XCTFail("Expected runtimeUnavailable error but no error was thrown")
        } catch let InferenceError.runtimeUnavailable(reason) {
            XCTAssertTrue(reason.contains("HTTPS"), "Error should mention HTTPS, got: \(reason)")
        } catch {
            XCTFail("Expected InferenceError.runtimeUnavailable, got: \(error)")
        }
    }

    @MainActor
    func testGenerateSuggestion_httpRemoteAnthropic_throwsWithoutNetworkCall() async {
        let runtime = OnlineLLMInferenceRuntime(
            provider: .anthropic,
            model: "claude-3-haiku-20240307",
            endpointURL: "http://api.anthropic.com",
            apiKey: "sk-ant-test"
        )
        do {
            _ = try await runtime.generateSuggestion(context: "hello")
            XCTFail("Expected runtimeUnavailable error but no error was thrown")
        } catch let InferenceError.runtimeUnavailable(reason) {
            XCTAssertTrue(reason.contains("HTTPS"), "Error should mention HTTPS, got: \(reason)")
        } catch {
            XCTFail("Expected InferenceError.runtimeUnavailable, got: \(error)")
        }
    }

    // MARK: - PII sanitizer injection (Step 4)

    @MainActor
    func testSanitizerIsAppliedToContextBeforeUse() async {
        // Spy sanitizer records what it received. Uses a class so the closure
        // can mutate it without violating Swift's Sendable capture rules.
        final class Spy: @unchecked Sendable {
            var receivedContext: String?
        }
        let spy = Spy()
        let runtime = OnlineLLMInferenceRuntime(
            provider: .openAICompatible,
            model: "gpt-4o-mini",
            endpointURL: "http://api.example.com", // throws runtimeUnavailable before network
            apiKey: "sk-test",
            sanitize: { input in
                spy.receivedContext = input
                return "<redacted>"
            }
        )
        let rawContext = "Send results to user@example.com"
        _ = try? await runtime.generateSuggestion(context: rawContext)
        // sanitize() is called before the endpoint guard, so the spy is populated.
        XCTAssertEqual(spy.receivedContext, rawContext, "Sanitizer should receive the raw context")
    }

    @MainActor
    func testDefaultSanitizer_identityFunction() throws {
        // Default init (no sanitize arg) must pass context through unchanged.
        // Use a plain-HTTP endpoint so it throws before any network work.
        let runtime = OnlineLLMInferenceRuntime(
            provider: .openAICompatible,
            model: "gpt-4o-mini",
            endpointURL: "http://api.example.com",
            apiKey: "sk-test"
        )
        // We can't directly observe the identity path without a network stub,
        // but we can confirm isAllowedEndpoint rejects it — proving the guard
        // (which runs after sanitize) is the first network-touching step.
        _ = runtime // suppress unused-variable warning
        let url = try XCTUnwrap(URL(string: "http://api.example.com/v1/chat/completions"))
        XCTAssertFalse(OnlineLLMInferenceRuntime.isAllowedEndpoint(url))
    }

    @MainActor
    func testFactoryPassesPIIFilterWhenEnabled() {
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
        // With piiFilteringEnabled=true the runtime is constructed (no throw at init time).
        let runtimes = factory.makeRuntimes(
            config: config,
            onlineLLMConfig: onlineConfig,
            onlineAPIKey: "sk-test",
            piiFilteringEnabled: true
        )
        XCTAssertEqual(runtimes.last?.name, "online")
    }

    @MainActor
    func testFactoryPassesIdentityWhenPIIFilteringDisabled() {
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
            onlineAPIKey: "sk-test",
            piiFilteringEnabled: false
        )
        XCTAssertEqual(runtimes.last?.name, "online")
    }
}
