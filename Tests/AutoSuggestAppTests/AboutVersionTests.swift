import XCTest
@testable import AutoSuggestApp

final class AboutVersionTests: XCTestCase {
    func testFormatsPresentValues() {
        XCTAssertEqual(AboutVersion.string(shortVersion: "1.2", build: "5"), "Version 1.2 (5)")
    }

    func testMissingShortVersionFallsBackToNeutralDash() {
        let result = AboutVersion.string(shortVersion: nil, build: nil)
        XCTAssertEqual(result, "Version — (1)")
        XCTAssertFalse(result.contains("0.3.0"), "must not surface a stale hardcoded version")
    }
}
