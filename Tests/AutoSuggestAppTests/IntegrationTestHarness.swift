import XCTest
import CoreGraphics
@testable import AutoSuggestApp

// MARK: - Mock Input Monitor

final class MockInputMonitor: InputMonitor, @unchecked Sendable {
    private var onEvent: ((InputEvent) -> Void)?
    var startCallCount = 0
    var stopCallCount = 0

    func start(onEvent: @escaping (InputEvent) -> Void) {
        startCallCount += 1
        self.onEvent = onEvent
    }

    func stop() {
        stopCallCount += 1
        onEvent = nil
    }

    func simulateKeyPress(keyCode: UInt16 = 0, flags: UInt64 = 0) {
        onEvent?(InputEvent(timestamp: Date(), keyCode: keyCode, flags: flags))
    }
}

// MARK: - Mock Shortcut Monitor

@MainActor
final class MockShortcutMonitor: SuggestionShortcutMonitor {
    private var handler: ((SuggestionCommand) -> Bool)?
    var startCallCount = 0
    var stopCallCount = 0

    func start(handler: @escaping (SuggestionCommand) -> Bool) {
        startCallCount += 1
        self.handler = handler
    }

    func stop() {
        stopCallCount += 1
        handler = nil
    }

    @discardableResult
    func simulateCommand(_ command: SuggestionCommand) -> Bool {
        return handler?(command) ?? false
    }
}

// MARK: - Mock Text Context Provider

final class MockTextContextProvider: TextContextProvider, @unchecked Sendable {
    var nextContext: TextContext?
    var contextCallCount = 0

    func currentContext() -> TextContext? {
        contextCallCount += 1
        return nextContext
    }

    func setContext(
        text: String,
        bundleID: String = "com.test.app",
        windowTitle: String? = "Test Window",
        caretRect: CGRect? = CGRect(x: 100, y: 100, width: 1, height: 16)
    ) {
        nextContext = TextContext(
            policyContext: PolicyContext(
                bundleID: bundleID,
                axRole: "AXTextField",
                isSecureField: false,
                windowTitle: windowTitle,
                textPrefix: text
            ),
            textBeforeCaret: text,
            fullText: text,
            selectedRange: nil,
            caretRectInScreen: caretRect
        )
    }
}

// MARK: - Mock Overlay Renderer

@MainActor
final class MockOverlayRenderer: OverlayRenderer {
    var currentSuggestionText: String?
    var showCallCount = 0
    var hideCallCount = 0

    func showSuggestion(_ text: String, caretRectInScreen: CGRect?) {
        showCallCount += 1
        currentSuggestionText = text
    }

    func hideSuggestion() {
        hideCallCount += 1
        currentSuggestionText = nil
    }
}

// MARK: - Mock Text Insertion Engine

@MainActor
final class MockTextInsertionEngine: TextInsertionEngine {
    var insertedTexts: [String] = []
    var shouldSucceed = true

    func insertSuggestion(_ suggestion: String) -> Bool {
        insertedTexts.append(suggestion)
        return shouldSucceed
    }
}

// MARK: - Mock Inference Runtime

@MainActor
final class MockInferenceRuntime: InferenceRuntime {
    let name: String
    var available: Bool
    var nextSuggestion: Suggestion?
    var shouldThrow = false
    var generateCallCount = 0
    var latencyMs: UInt64 = 0

    init(name: String = "mock", available: Bool = true) {
        self.name = name
        self.available = available
    }

    func isAvailable() -> Bool { available }

    func generateSuggestion(context: String) async throws -> Suggestion {
        generateCallCount += 1
        if latencyMs > 0 {
            try? await Task.sleep(nanoseconds: latencyMs * 1_000_000)
        }
        if shouldThrow {
            throw InferenceError.runtimeUnavailable("Mock error")
        }
        return nextSuggestion ?? Suggestion(completion: "mock completion", confidence: 0.9)
    }
}

// MARK: - Mock Metrics Collector

/// Wraps MetricsCollector for test observability
@MainActor
final class TestMetricsObserver {
    let collector = MetricsCollector()

    func snapshot() async -> MetricsSnapshot {
        await collector.snapshot()
    }
}

// MARK: - Integration Tests

final class TypingPipelineIntegrationTests: XCTestCase {

    @MainActor
    func testFullAcceptFlow() async throws {
        // Setup all mocks
        let inputMonitor = MockInputMonitor()
        let shortcutMonitor = MockShortcutMonitor()
        let contextProvider = MockTextContextProvider()
        let overlayRenderer = MockOverlayRenderer()
        let insertionEngine = MockTextInsertionEngine()
        let metricsCollector = MetricsCollector()
        let telemetryManager = TelemetryManager(enabled: false)
        let personalizationEngine = PersonalizationEngine(store: EncryptedFileStore())
        let accessibilityAnnouncer = AccessibilityAnnouncer()

        // Create a mock runtime that returns a known suggestion
        let mockRuntime = MockInferenceRuntime()
        mockRuntime.nextSuggestion = Suggestion(completion: " world!", confidence: 0.95)

        let inferenceEngine = InferenceEngine(runtimes: [mockRuntime])
        let policyEngine = PolicyEngine(defaults: .default, userRules: [])
        let orchestrator = SuggestionOrchestrator(
            policyEngine: policyEngine,
            inferenceEngine: inferenceEngine
        )

        let pipeline = TypingPipeline(
            inputMonitor: inputMonitor,
            shortcutMonitor: shortcutMonitor,
            contextProvider: contextProvider,
            suggestionOrchestrator: orchestrator,
            overlayRenderer: overlayRenderer,
            insertionEngine: insertionEngine,
            metricsCollector: metricsCollector,
            telemetryManager: telemetryManager,
            personalizationEngine: personalizationEngine,
            accessibilityAnnouncer: accessibilityAnnouncer,
            batteryMode: .alwaysOn
        )

        // Start the pipeline
        pipeline.start()
        XCTAssertEqual(inputMonitor.startCallCount, 1)
        XCTAssertEqual(shortcutMonitor.startCallCount, 1)

        // Simulate user typing "Hello"
        contextProvider.setContext(text: "Hello")
        inputMonitor.simulateKeyPress(keyCode: 0)

        // Wait for debounce (150ms) + inference
        try await Task.sleep(nanoseconds: 300_000_000)

        // Suggestion should be shown
        XCTAssertEqual(overlayRenderer.currentSuggestionText, " world!")
        XCTAssertEqual(overlayRenderer.showCallCount, 1)

        // Accept the suggestion
        let consumed = shortcutMonitor.simulateCommand(.accept)
        XCTAssertTrue(consumed)
        XCTAssertEqual(insertionEngine.insertedTexts, [" world!"])

        // Overlay should be hidden
        XCTAssertNil(overlayRenderer.currentSuggestionText)

        // Stop
        pipeline.stop()
        XCTAssertEqual(inputMonitor.stopCallCount, 1)
        XCTAssertEqual(shortcutMonitor.stopCallCount, 1)
    }

    @MainActor
    func testDismissFlow() async throws {
        let inputMonitor = MockInputMonitor()
        let shortcutMonitor = MockShortcutMonitor()
        let contextProvider = MockTextContextProvider()
        let overlayRenderer = MockOverlayRenderer()
        let insertionEngine = MockTextInsertionEngine()

        let mockRuntime = MockInferenceRuntime()
        mockRuntime.nextSuggestion = Suggestion(completion: " test", confidence: 0.8)

        let inferenceEngine = InferenceEngine(runtimes: [mockRuntime])
        let policyEngine = PolicyEngine(defaults: .default, userRules: [])
        let orchestrator = SuggestionOrchestrator(
            policyEngine: policyEngine,
            inferenceEngine: inferenceEngine
        )

        let pipeline = TypingPipeline(
            inputMonitor: inputMonitor,
            shortcutMonitor: shortcutMonitor,
            contextProvider: contextProvider,
            suggestionOrchestrator: orchestrator,
            overlayRenderer: overlayRenderer,
            insertionEngine: insertionEngine,
            metricsCollector: MetricsCollector(),
            telemetryManager: TelemetryManager(enabled: false),
            personalizationEngine: PersonalizationEngine(store: EncryptedFileStore()),
            accessibilityAnnouncer: AccessibilityAnnouncer(),
            batteryMode: .alwaysOn
        )

        pipeline.start()

        // Trigger suggestion
        contextProvider.setContext(text: "Hello")
        inputMonitor.simulateKeyPress()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNotNil(overlayRenderer.currentSuggestionText)

        // Dismiss
        let consumed = shortcutMonitor.simulateCommand(.dismiss)
        XCTAssertTrue(consumed)
        XCTAssertNil(overlayRenderer.currentSuggestionText)
        XCTAssertTrue(insertionEngine.insertedTexts.isEmpty, "Dismiss should not insert")

        pipeline.stop()
    }

    @MainActor
    func testPolicyBlocksExcludedApp() async throws {
        let inputMonitor = MockInputMonitor()
        let shortcutMonitor = MockShortcutMonitor()
        let contextProvider = MockTextContextProvider()
        let overlayRenderer = MockOverlayRenderer()

        let mockRuntime = MockInferenceRuntime()
        let inferenceEngine = InferenceEngine(runtimes: [mockRuntime])

        // Exclude the test app
        let exclusionRule = ExclusionRule(
            enabled: true,
            bundleID: "com.excluded.app",
            windowTitleContains: nil,
            contentPattern: nil
        )
        let policyEngine = PolicyEngine(defaults: .default, userRules: [exclusionRule])
        let orchestrator = SuggestionOrchestrator(
            policyEngine: policyEngine,
            inferenceEngine: inferenceEngine
        )

        let pipeline = TypingPipeline(
            inputMonitor: inputMonitor,
            shortcutMonitor: shortcutMonitor,
            contextProvider: contextProvider,
            suggestionOrchestrator: orchestrator,
            overlayRenderer: overlayRenderer,
            insertionEngine: MockTextInsertionEngine(),
            metricsCollector: MetricsCollector(),
            telemetryManager: TelemetryManager(enabled: false),
            personalizationEngine: PersonalizationEngine(store: EncryptedFileStore()),
            accessibilityAnnouncer: AccessibilityAnnouncer(),
            batteryMode: .alwaysOn
        )

        pipeline.start()

        // Type in excluded app
        contextProvider.setContext(text: "Hello", bundleID: "com.excluded.app")
        inputMonitor.simulateKeyPress()
        try await Task.sleep(nanoseconds: 300_000_000)

        // No suggestion should appear
        XCTAssertNil(overlayRenderer.currentSuggestionText)
        XCTAssertEqual(mockRuntime.generateCallCount, 0, "Excluded app should not trigger inference")

        pipeline.stop()
    }

    @MainActor
    func testInsertionFailureDoesNotCrash() async throws {
        let inputMonitor = MockInputMonitor()
        let shortcutMonitor = MockShortcutMonitor()
        let contextProvider = MockTextContextProvider()
        let overlayRenderer = MockOverlayRenderer()
        let insertionEngine = MockTextInsertionEngine()
        insertionEngine.shouldSucceed = false

        let mockRuntime = MockInferenceRuntime()
        mockRuntime.nextSuggestion = Suggestion(completion: " fail", confidence: 0.5)

        let inferenceEngine = InferenceEngine(runtimes: [mockRuntime])
        let policyEngine = PolicyEngine(defaults: .default, userRules: [])
        let orchestrator = SuggestionOrchestrator(
            policyEngine: policyEngine,
            inferenceEngine: inferenceEngine
        )

        let pipeline = TypingPipeline(
            inputMonitor: inputMonitor,
            shortcutMonitor: shortcutMonitor,
            contextProvider: contextProvider,
            suggestionOrchestrator: orchestrator,
            overlayRenderer: overlayRenderer,
            insertionEngine: insertionEngine,
            metricsCollector: MetricsCollector(),
            telemetryManager: TelemetryManager(enabled: false),
            personalizationEngine: PersonalizationEngine(store: EncryptedFileStore()),
            accessibilityAnnouncer: AccessibilityAnnouncer(),
            batteryMode: .alwaysOn
        )

        pipeline.start()

        contextProvider.setContext(text: "test")
        inputMonitor.simulateKeyPress()
        try await Task.sleep(nanoseconds: 300_000_000)

        // Accept should not crash even if insertion fails
        let consumed = shortcutMonitor.simulateCommand(.accept)
        XCTAssertTrue(consumed)
        XCTAssertEqual(insertionEngine.insertedTexts, [" fail"])

        pipeline.stop()
    }

    @MainActor
    func testRuntimeErrorClearsSuggestion() async throws {
        let inputMonitor = MockInputMonitor()
        let shortcutMonitor = MockShortcutMonitor()
        let contextProvider = MockTextContextProvider()
        let overlayRenderer = MockOverlayRenderer()

        let mockRuntime = MockInferenceRuntime()
        mockRuntime.shouldThrow = true

        let inferenceEngine = InferenceEngine(runtimes: [mockRuntime])
        let policyEngine = PolicyEngine(defaults: .default, userRules: [])
        let orchestrator = SuggestionOrchestrator(
            policyEngine: policyEngine,
            inferenceEngine: inferenceEngine
        )

        let pipeline = TypingPipeline(
            inputMonitor: inputMonitor,
            shortcutMonitor: shortcutMonitor,
            contextProvider: contextProvider,
            suggestionOrchestrator: orchestrator,
            overlayRenderer: overlayRenderer,
            insertionEngine: MockTextInsertionEngine(),
            metricsCollector: MetricsCollector(),
            telemetryManager: TelemetryManager(enabled: false),
            personalizationEngine: PersonalizationEngine(store: EncryptedFileStore()),
            accessibilityAnnouncer: AccessibilityAnnouncer(),
            batteryMode: .alwaysOn
        )

        pipeline.start()

        contextProvider.setContext(text: "error test")
        inputMonitor.simulateKeyPress()
        try await Task.sleep(nanoseconds: 300_000_000)

        // Suggestion should be nil (error clears it)
        XCTAssertNil(overlayRenderer.currentSuggestionText)
        XCTAssertTrue(overlayRenderer.hideCallCount > 0)

        pipeline.stop()
    }

    @MainActor
    func testEmptyContextDoesNotTriggerInference() async throws {
        let inputMonitor = MockInputMonitor()
        let shortcutMonitor = MockShortcutMonitor()
        let contextProvider = MockTextContextProvider()
        let overlayRenderer = MockOverlayRenderer()

        let mockRuntime = MockInferenceRuntime()
        let inferenceEngine = InferenceEngine(runtimes: [mockRuntime])
        let policyEngine = PolicyEngine(defaults: .default, userRules: [])
        let orchestrator = SuggestionOrchestrator(
            policyEngine: policyEngine,
            inferenceEngine: inferenceEngine
        )

        let pipeline = TypingPipeline(
            inputMonitor: inputMonitor,
            shortcutMonitor: shortcutMonitor,
            contextProvider: contextProvider,
            suggestionOrchestrator: orchestrator,
            overlayRenderer: overlayRenderer,
            insertionEngine: MockTextInsertionEngine(),
            metricsCollector: MetricsCollector(),
            telemetryManager: TelemetryManager(enabled: false),
            personalizationEngine: PersonalizationEngine(store: EncryptedFileStore()),
            accessibilityAnnouncer: AccessibilityAnnouncer(),
            batteryMode: .alwaysOn
        )

        pipeline.start()

        // Empty context
        contextProvider.setContext(text: "")
        inputMonitor.simulateKeyPress()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(mockRuntime.generateCallCount, 0, "Empty context should skip inference")

        pipeline.stop()
    }

    @MainActor
    func testNoContextDoesNotCrash() async throws {
        let inputMonitor = MockInputMonitor()
        let shortcutMonitor = MockShortcutMonitor()
        let contextProvider = MockTextContextProvider()
        let overlayRenderer = MockOverlayRenderer()

        let mockRuntime = MockInferenceRuntime()
        let inferenceEngine = InferenceEngine(runtimes: [mockRuntime])
        let policyEngine = PolicyEngine(defaults: .default, userRules: [])
        let orchestrator = SuggestionOrchestrator(
            policyEngine: policyEngine,
            inferenceEngine: inferenceEngine
        )

        let pipeline = TypingPipeline(
            inputMonitor: inputMonitor,
            shortcutMonitor: shortcutMonitor,
            contextProvider: contextProvider,
            suggestionOrchestrator: orchestrator,
            overlayRenderer: overlayRenderer,
            insertionEngine: MockTextInsertionEngine(),
            metricsCollector: MetricsCollector(),
            telemetryManager: TelemetryManager(enabled: false),
            personalizationEngine: PersonalizationEngine(store: EncryptedFileStore()),
            accessibilityAnnouncer: AccessibilityAnnouncer(),
            batteryMode: .alwaysOn
        )

        pipeline.start()

        // No context set (nil)
        contextProvider.nextContext = nil
        inputMonitor.simulateKeyPress()
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(mockRuntime.generateCallCount, 0)

        pipeline.stop()
    }
}
