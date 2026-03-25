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
}
