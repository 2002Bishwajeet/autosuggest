import XCTest
@testable import AutoSuggestApp

/// #27: the ghost overlay must dismiss when focus leaves the source field,
/// even though no keyDown event fires (mouse click, window switch).
@MainActor
final class TypingPipelineFocusLossTests: XCTestCase {
    private var contextProvider: MockTextContextProvider!
    private var overlayRenderer: MockOverlayRenderer!
    private var inputMonitor: MockInputMonitor!
    private var pipeline: TypingPipeline!

    private func makeSUT() {
        contextProvider = MockTextContextProvider()
        overlayRenderer = MockOverlayRenderer()
        inputMonitor = MockInputMonitor()
        let inferenceEngine = InferenceEngine(runtimes: [MockInferenceRuntime()])
        let policyEngine = PolicyEngine(defaults: .default, userRules: [])
        pipeline = TypingPipeline(
            inputMonitor: inputMonitor,
            shortcutMonitor: MockShortcutMonitor(),
            contextProvider: contextProvider,
            suggestionOrchestrator: SuggestionOrchestrator(
                policyEngine: policyEngine,
                inferenceEngine: inferenceEngine
            ),
            overlayRenderer: overlayRenderer,
            insertionEngine: MockTextInsertionEngine(),
            metricsCollector: MetricsCollector(),
            telemetryManager: TelemetryManager(enabled: false),
            personalizationEngine: PersonalizationEngine(store: EncryptedFileStore()),
            accessibilityAnnouncer: AccessibilityAnnouncer(),
            trainingDataExporter: TrainingDataExporter(enabled: false),
            batteryMode: .alwaysOn
        )
    }

    private func makeCandidate() -> SuggestionCandidate {
        SuggestionCandidate(
            requestID: 1,
            completion: " world",
            confidence: 0.9,
            sourceContext: "Hello",
            sourceBundleID: "com.test.app",
            sourceWindowTitle: "Test Window",
            latencyMs: 10
        )
    }

    func testRevalidateClearsSuggestionWhenContextGoesNil() {
        makeSUT()
        contextProvider.setContext(text: "Hello")
        pipeline.presentSuggestion(makeCandidate())
        XCTAssertEqual(overlayRenderer.showCallCount, 1)

        contextProvider.nextContext = nil
        pipeline.revalidateActiveSuggestion()
        XCTAssertEqual(overlayRenderer.hideCallCount, 1)
    }

    func testRevalidateKeepsSuggestionWhileContextValidClearsWhenFocusMoves() {
        makeSUT()
        contextProvider.setContext(text: "Hello")
        pipeline.presentSuggestion(makeCandidate())

        // Still in the same field: no dismissal.
        pipeline.revalidateActiveSuggestion()
        XCTAssertEqual(overlayRenderer.hideCallCount, 0)

        // Focus moved to another app: dismissal.
        contextProvider.setContext(text: "", bundleID: "com.other.app", windowTitle: "Other")
        pipeline.revalidateActiveSuggestion()
        XCTAssertEqual(overlayRenderer.hideCallCount, 1)
    }

    func testRevalidationTimerFiresWithoutAnyKeyEvent() {
        makeSUT()
        contextProvider.setContext(text: "Hello")
        pipeline.presentSuggestion(makeCandidate())
        contextProvider.nextContext = nil

        let hidden = XCTNSPredicateExpectation(
            predicate: NSPredicate { [overlayRenderer] _, _ in
                overlayRenderer!.hideCallCount > 0
            },
            object: nil
        )
        wait(for: [hidden], timeout: 3)
    }

    func testKeyEventWithNilContextClearsSuggestion() {
        makeSUT()
        pipeline.start()
        contextProvider.setContext(text: "Hello")
        pipeline.presentSuggestion(makeCandidate())

        contextProvider.nextContext = nil
        inputMonitor.simulateKeyPress()

        let hidden = XCTNSPredicateExpectation(
            predicate: NSPredicate { [overlayRenderer] _, _ in
                overlayRenderer!.hideCallCount > 0
            },
            object: nil
        )
        wait(for: [hidden], timeout: 3)
        pipeline.stop()
    }
}
