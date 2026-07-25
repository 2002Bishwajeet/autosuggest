import SwiftUI
import XCTest
@testable import AutoSuggestApp

final class StatusBadgeTests: XCTestCase {
    func testTintMapping() {
        XCTAssertEqual(StatusBadge.tint(for: .granted), AutoSuggestTheme.success)
        XCTAssertEqual(StatusBadge.tint(for: .required), AutoSuggestTheme.warning)
        XCTAssertEqual(StatusBadge.tint(for: .neutral), AutoSuggestTheme.textSecondary)
    }
}
