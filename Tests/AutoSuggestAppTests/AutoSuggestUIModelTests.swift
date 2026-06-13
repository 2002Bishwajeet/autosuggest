import XCTest
@testable import AutoSuggestApp

final class AutoSuggestUIModelTests: XCTestCase {
    func testExclusionRuleDraftRequiresAtLeastOneCondition() {
        let draft = ExclusionRuleDraft()
        XCTAssertEqual(draft.validationMessage(), "Enter at least one condition.")
    }

    func testExclusionRuleDraftRejectsInvalidRegex() {
        var draft = ExclusionRuleDraft()
        draft.contentPattern = "[invalid"
        XCTAssertEqual(draft.validationMessage(), "Content pattern is not valid regex.")
    }

    func testModelSourceDraftRequiresMetadata() {
        var draft = ModelSourceDraft(source: .default)
        draft.modelID = ""
        XCTAssertEqual(draft.validationMessage(), "Model ID is required.")
    }

    func testModelSourceDraftAcceptsValidDirectURL() {
        var draft = ModelSourceDraft(source: .default)
        draft.modelID = "custom-model"
        draft.version = "1.0.0"
        draft.directURL = "https://example.com/model.zip"
        XCTAssertNil(draft.validationMessage())
    }

    func testPermissionHealthSummaryIncludesMissingItems() {
        let health = PermissionHealth(
            accessibilityTrusted: false,
            inputMonitoringTrusted: true
        )
        XCTAssertEqual(health.summary, "Missing: Accessibility")
    }

    func testPermissionHealthReadySummary() {
        let health = PermissionHealth(
            accessibilityTrusted: true,
            inputMonitoringTrusted: true
        )

        XCTAssertEqual(health.summary, "All required permissions are granted.")
    }

    func testPauseRemedyForRuntimeDownGivesOllamaHint() {
        let remedy = AppCoordinator.derivePauseRemedy(
            isManualPause: false,
            permissionsReady: true,
            lowPowerPause: false,
            runtimeReady: false
        )
        XCTAssertEqual(
            remedy,
            "Start Ollama (`ollama serve`) or install a model via Model Source Settings…"
        )
    }

    func testPauseRemedyIsNilWhenNoPauseReason() {
        let remedy = AppCoordinator.derivePauseRemedy(
            isManualPause: false,
            permissionsReady: true,
            lowPowerPause: false,
            runtimeReady: true
        )
        XCTAssertNil(remedy)
    }

    // MARK: - RuntimeDisplayName

    func testRuntimeDisplayNameMapsKnownIdentifiers() {
        XCTAssertEqual(RuntimeDisplayName.label(for: "ollama"), "Ollama")
        XCTAssertEqual(RuntimeDisplayName.label(for: "llama.cpp"), "llama.cpp")
        XCTAssertEqual(RuntimeDisplayName.label(for: "coreml"), "Core ML")
        XCTAssertEqual(RuntimeDisplayName.label(for: "online"), "Online LLM")
    }

    func testRuntimeDisplayNameIsCaseInsensitive() {
        XCTAssertEqual(RuntimeDisplayName.label(for: "OLLAMA"), "Ollama")
        XCTAssertEqual(RuntimeDisplayName.label(for: "CoreML"), "Core ML")
    }

    func testRuntimeDisplayNameReturnsUnknownIdentifierUnchanged() {
        XCTAssertEqual(RuntimeDisplayName.label(for: "mystery-runtime"), "mystery-runtime")
    }

    // MARK: - ExclusionRule.displayTitle

    func testExclusionRuleDisplayTitlePrefersBundleID() {
        let rule = ExclusionRule(
            enabled: true,
            bundleID: "com.apple.dt.Xcode",
            windowTitleContains: "Secret",
            contentPattern: nil
        )
        XCTAssertEqual(rule.displayTitle, "com.apple.dt.Xcode")
    }

    func testExclusionRuleDisplayTitleFallsBackToWindowTitle() {
        let rule = ExclusionRule(
            enabled: true,
            bundleID: nil,
            windowTitleContains: "Password",
            contentPattern: nil
        )
        XCTAssertEqual(rule.displayTitle, "Window title contains \u{201C}Password\u{201D}")
    }

    func testExclusionRuleDisplayTitleFallsBackToContentPattern() {
        let rule = ExclusionRule(
            enabled: true,
            bundleID: nil,
            windowTitleContains: nil,
            contentPattern: "secret-\\d+"
        )
        XCTAssertEqual(rule.displayTitle, "Content matches /secret-\\d+/")
    }

    func testExclusionRuleDisplayTitleGenericWhenEmpty() {
        let rule = ExclusionRule(
            enabled: true,
            bundleID: nil,
            windowTitleContains: nil,
            contentPattern: nil
        )
        XCTAssertEqual(rule.displayTitle, "Custom rule")
    }

    func testExclusionRuleDisplayTitleTreatsEmptyStringsAsAbsent() {
        let rule = ExclusionRule(
            enabled: true,
            bundleID: "",
            windowTitleContains: "",
            contentPattern: "abc"
        )
        XCTAssertEqual(rule.displayTitle, "Content matches /abc/")
    }

    // MARK: - MetricsSnapshot acceptance rate

    func testAcceptanceRateTextWithNoSuggestions() {
        XCTAssertEqual(MetricsSnapshot.zero.acceptanceRateText, "No suggestions yet")
    }

    func testAcceptanceRateTextComputesPercentage() {
        let metrics = MetricsSnapshot(
            suggestionsShown: 4,
            suggestionsAccepted: 1,
            suggestionsDismissed: 3,
            suggestionErrors: 0,
            insertionFailures: 0,
            avgLatencyMs: 0
        )
        XCTAssertEqual(metrics.acceptanceRateText, "25% accepted")
    }
}
