import AppKit
import CoreGraphics
import XCTest
@testable import AutoSuggestApp

/// Wiring tests for Layer B: confirm the AX-derived font (B1) reaches the
/// renderer through TypingPipeline, and that the suppression decision (B5)
/// actually gates `presentSuggestion`. Pure-function correctness is covered in
/// the dedicated unit-test files; these verify the connections via the mocks in
/// IntegrationTestHarness.swift.
@MainActor
final class OverlayFidelityWiringTests: XCTestCase {
    private func waitUntil(timeout: TimeInterval = 3.0, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private struct Harness {
        let inputMonitor: MockInputMonitor
        let shortcutMonitor: MockShortcutMonitor
        let contextProvider: MockTextContextProvider
        let overlayRenderer: MockOverlayRenderer
        let pipeline: TypingPipeline
    }

    private func makeHarness(completion: String = " world!") -> Harness {
        let inputMonitor = MockInputMonitor()
        let shortcutMonitor = MockShortcutMonitor()
        let contextProvider = MockTextContextProvider()
        let overlayRenderer = MockOverlayRenderer()
        let insertionEngine = MockTextInsertionEngine()

        let mockRuntime = MockInferenceRuntime()
        mockRuntime.nextSuggestion = Suggestion(completion: completion, confidence: 0.95)
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
            trainingDataExporter: TrainingDataExporter(enabled: false),
            batteryMode: .alwaysOn
        )
        return Harness(
            inputMonitor: inputMonitor,
            shortcutMonitor: shortcutMonitor,
            contextProvider: contextProvider,
            overlayRenderer: overlayRenderer,
            pipeline: pipeline
        )
    }

    // MARK: - B1: font flows to the renderer

    func testAXFontFlowsThroughPipelineToRenderer() async {
        let h = makeHarness()
        h.pipeline.start()
        defer { h.pipeline.stop() }

        let axFont = NSFont.systemFont(ofSize: 18, weight: .regular)
        h.contextProvider.setContext(text: "Hello", caretFont: axFont)
        h.inputMonitor.simulateKeyPress(keyCode: 0)

        await waitUntil { h.overlayRenderer.currentSuggestionText != nil }
        XCTAssertEqual(h.overlayRenderer.currentSuggestionText, " world!")
        XCTAssertEqual(h.overlayRenderer.lastFont?.pointSize, 18)
    }

    func testNilAXFontPassesNilToRenderer() async {
        let h = makeHarness()
        h.pipeline.start()
        defer { h.pipeline.stop() }

        h.contextProvider.setContext(text: "Hello", caretFont: nil)
        h.inputMonitor.simulateKeyPress(keyCode: 0)

        await waitUntil { h.overlayRenderer.currentSuggestionText != nil }
        XCTAssertNil(h.overlayRenderer.lastFont)
    }

    // MARK: - B5: suppression gates the overlay

    func testNativeInlineSuggestionSuppressesOverlay() async {
        let h = makeHarness()
        h.pipeline.start()
        defer { h.pipeline.stop() }

        // AX detected an active native inline prediction → our overlay is
        // suppressed even though inference produced a candidate.
        h.contextProvider.setContext(text: "Hello", nativeInlineSuggestionPresent: true)
        h.inputMonitor.simulateKeyPress(keyCode: 0)

        // Give the debounce + inference time to run; the overlay must stay hidden.
        try? await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertNil(h.overlayRenderer.currentSuggestionText)
        XCTAssertEqual(h.overlayRenderer.showCallCount, 0)
    }

    func testBackstopAppSuppressesOverlay() async {
        let h = makeHarness()
        h.pipeline.start()
        defer { h.pipeline.stop() }

        // com.apple.Notes is on the backstop list → suppressed regardless of the
        // AX native-suggestion flag.
        h.contextProvider.setContext(
            text: "Hello",
            bundleID: "com.apple.Notes",
            nativeInlineSuggestionPresent: false
        )
        h.inputMonitor.simulateKeyPress(keyCode: 0)

        try? await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertNil(h.overlayRenderer.currentSuggestionText)
        XCTAssertEqual(h.overlayRenderer.showCallCount, 0)
    }

    func testNoSuppressionShowsOverlayNormally() async {
        let h = makeHarness()
        h.pipeline.start()
        defer { h.pipeline.stop() }

        h.contextProvider.setContext(
            text: "Hello",
            bundleID: "com.test.app",
            nativeInlineSuggestionPresent: false
        )
        h.inputMonitor.simulateKeyPress(keyCode: 0)

        await waitUntil { h.overlayRenderer.currentSuggestionText != nil }
        XCTAssertEqual(h.overlayRenderer.showCallCount, 1)
    }
}
