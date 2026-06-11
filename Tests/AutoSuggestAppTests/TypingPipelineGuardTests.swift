import XCTest
import CoreGraphics
@testable import AutoSuggestApp

// Characterization tests for the two TypingPipeline staleness/continuation
// guards (`isSuggestion(_:validFor:)` and `adjustSuggestionForSmartContinuation`)
// that protect against inserting a suggestion into the wrong field. Pins down
// current behavior ahead of plans 003/004. Reuses the mock construction pattern
// from IntegrationTestHarness.swift (mocks are in the same test target).
@MainActor
final class TypingPipelineGuardTests: XCTestCase {

    // Builds a TypingPipeline with mocks, mirroring IntegrationTestHarness.swift.
    private func makePipeline() -> TypingPipeline {
        let mockRuntime = MockInferenceRuntime()
        let inferenceEngine = InferenceEngine(runtimes: [mockRuntime])
        let policyEngine = PolicyEngine(defaults: .default, userRules: [])
        let orchestrator = SuggestionOrchestrator(
            policyEngine: policyEngine,
            inferenceEngine: inferenceEngine
        )
        return TypingPipeline(
            inputMonitor: MockInputMonitor(),
            shortcutMonitor: MockShortcutMonitor(),
            contextProvider: MockTextContextProvider(),
            suggestionOrchestrator: orchestrator,
            overlayRenderer: MockOverlayRenderer(),
            insertionEngine: MockTextInsertionEngine(),
            metricsCollector: MetricsCollector(),
            telemetryManager: TelemetryManager(enabled: false),
            personalizationEngine: PersonalizationEngine(store: EncryptedFileStore()),
            accessibilityAnnouncer: AccessibilityAnnouncer(),
            trainingDataExporter: TrainingDataExporter(enabled: false),
            batteryMode: .alwaysOn
        )
    }

    private func makeCandidate(
        completion: String,
        sourceContext: String,
        sourceBundleID: String = "com.test.app",
        sourceWindowTitle: String? = "Window"
    ) -> SuggestionCandidate {
        SuggestionCandidate(
            requestID: 1,
            completion: completion,
            confidence: 0.9,
            sourceContext: sourceContext,
            sourceBundleID: sourceBundleID,
            sourceWindowTitle: sourceWindowTitle,
            latencyMs: 10
        )
    }

    private func makeContext(
        textBeforeCaret: String,
        bundleID: String = "com.test.app",
        windowTitle: String? = "Window"
    ) -> TextContext {
        TextContext(
            policyContext: PolicyContext(
                bundleID: bundleID,
                axRole: "AXTextField",
                isSecureField: false,
                windowTitle: windowTitle,
                textPrefix: textBeforeCaret
            ),
            textBeforeCaret: textBeforeCaret,
            fullText: textBeforeCaret,
            selectedRange: nil,
            caretRectInScreen: nil
        )
    }

    // MARK: - isSuggestion(_:validFor:)

    func testIsSuggestionValidWhenBundleTitleMatchAndContextExtends() {
        let pipeline = makePipeline()
        let candidate = makeCandidate(completion: " world", sourceContext: "Hello")
        // Same bundle, same title, current context extends the source context.
        let context = makeContext(textBeforeCaret: "Hello there")
        XCTAssertTrue(pipeline.isSuggestion(candidate, validFor: context))
    }

    func testIsSuggestionInvalidWhenBundleIDDiffers() {
        let pipeline = makePipeline()
        let candidate = makeCandidate(completion: " world", sourceContext: "Hello", sourceBundleID: "com.a.app")
        let context = makeContext(textBeforeCaret: "Hello", bundleID: "com.b.app")
        XCTAssertFalse(pipeline.isSuggestion(candidate, validFor: context))
    }

    func testIsSuggestionInvalidWhenWindowTitlesDiffer() {
        let pipeline = makePipeline()
        let candidate = makeCandidate(completion: " world", sourceContext: "Hello", sourceWindowTitle: "Doc A")
        let context = makeContext(textBeforeCaret: "Hello", windowTitle: "Doc B")
        XCTAssertFalse(pipeline.isSuggestion(candidate, validFor: context))
    }

    func testIsSuggestionSkipsTitleCheckWhenBothTitlesEmpty() {
        let pipeline = makePipeline()
        // CHARACTERIZATION: when both source and current window titles are
        // empty/nil, the title check is skipped (lines 215-221); validity then
        // hinges on bundle + context prefix only.
        let candidateNil = makeCandidate(completion: " world", sourceContext: "Hello", sourceWindowTitle: nil)
        let contextNil = makeContext(textBeforeCaret: "Hello", windowTitle: nil)
        XCTAssertTrue(pipeline.isSuggestion(candidateNil, validFor: contextNil))

        // Empty-string title (mapped to "" same as nil) is also skipped.
        let candidateEmpty = makeCandidate(completion: " world", sourceContext: "Hello", sourceWindowTitle: "")
        let contextEmpty = makeContext(textBeforeCaret: "Hello", windowTitle: "")
        XCTAssertTrue(pipeline.isSuggestion(candidateEmpty, validFor: contextEmpty))
    }

    func testIsSuggestionInvalidWhenContextNeitherExtendsNorPrefixes() {
        let pipeline = makePipeline()
        let candidate = makeCandidate(completion: " world", sourceContext: "Hello")
        // "Goodbye" neither has prefix "Hello" nor is a prefix of "Hello".
        let context = makeContext(textBeforeCaret: "Goodbye")
        XCTAssertFalse(pipeline.isSuggestion(candidate, validFor: context))
    }

    // MARK: - adjustSuggestionForSmartContinuation

    func testAdjustTrimsTypedPrefixAndUpdatesSourceContext() {
        let pipeline = makePipeline()
        // Source context "Hello", completion " world". User typed " wo" more.
        let candidate = makeCandidate(completion: " world", sourceContext: "Hello")
        let adjusted = pipeline.adjustSuggestionForSmartContinuation(
            activeSuggestion: candidate,
            newContext: "Hello wo"
        )
        XCTAssertNotNil(adjusted)
        XCTAssertEqual(adjusted?.completion, "rld")
        XCTAssertEqual(adjusted?.sourceContext, "Hello wo")
    }

    func testAdjustReturnsNilWhenTypedTextDiverges() {
        let pipeline = makePipeline()
        let candidate = makeCandidate(completion: " world", sourceContext: "Hello")
        // User typed "X" which does not match the start of " world".
        let adjusted = pipeline.adjustSuggestionForSmartContinuation(
            activeSuggestion: candidate,
            newContext: "HelloX"
        )
        XCTAssertNil(adjusted)
    }

    func testAdjustReturnsNilWhenUserTypedEntireCompletion() {
        let pipeline = makePipeline()
        let candidate = makeCandidate(completion: " world", sourceContext: "Hello")
        // User typed the entire completion → remaining is empty (line 199).
        let adjusted = pipeline.adjustSuggestionForSmartContinuation(
            activeSuggestion: candidate,
            newContext: "Hello world"
        )
        XCTAssertNil(adjusted)
    }

    func testAdjustReturnsNilWhenNewContextDoesNotExtendSource() {
        let pipeline = makePipeline()
        let candidate = makeCandidate(completion: " world", sourceContext: "Hello")
        // "Goodbye" does not have prefix "Hello" → guard fails (line 194).
        let adjusted = pipeline.adjustSuggestionForSmartContinuation(
            activeSuggestion: candidate,
            newContext: "Goodbye"
        )
        XCTAssertNil(adjusted)
    }

    func testAdjustReturnsOriginalWhenContextIdenticalToSource() {
        let pipeline = makePipeline()
        let candidate = makeCandidate(completion: " world", sourceContext: "Hello")
        // Identical context → typedDelta empty → returns original unchanged (line 196).
        let adjusted = pipeline.adjustSuggestionForSmartContinuation(
            activeSuggestion: candidate,
            newContext: "Hello"
        )
        XCTAssertNotNil(adjusted)
        XCTAssertEqual(adjusted?.completion, " world")
        XCTAssertEqual(adjusted?.sourceContext, "Hello")
    }
}
