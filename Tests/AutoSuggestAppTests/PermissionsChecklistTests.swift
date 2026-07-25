import XCTest
@testable import AutoSuggestApp

/// Locks the canonical permission copy. Both onboarding and Settings render
/// `PermissionsChecklist`, which reads only these strings — so this test is
/// the regression lock keeping the two screens' wording identical.
final class PermissionsChecklistTests: XCTestCase {
    func testCanonicalAccessibilityCopy() {
        XCTAssertEqual(PermissionCopy.accessibilityTitle, "Accessibility")
        XCTAssertEqual(
            PermissionCopy.accessibilityDescription,
            "Lets AutoSuggest read the text around your cursor and insert completions into any text field. Required for suggestions to work."
        )
    }

    func testCanonicalInputMonitoringCopy() {
        XCTAssertEqual(PermissionCopy.inputMonitoringTitle, "Input Monitoring")
        XCTAssertEqual(
            PermissionCopy.inputMonitoringDescription,
            "Lets AutoSuggest detect Tab, Enter, and Esc so you can accept or dismiss suggestions. Requires a relaunch after granting."
        )
    }
}
