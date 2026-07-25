import XCTest
@testable import AutoSuggestApp

final class DesignSystemTests: XCTestCase {
    func testBadgeFillOpacityIsCanonical() {
        XCTAssertEqual(AutoSuggestTheme.badgeFillOpacity, 0.15, accuracy: 0.0001)
    }

    func testRadiusScaleIsMonotonic() {
        XCTAssertLessThan(AutoSuggestTheme.radiusExtraSmall, AutoSuggestTheme.radiusSmall)
        XCTAssertLessThan(AutoSuggestTheme.radiusSmall, AutoSuggestTheme.radiusMedium)
        XCTAssertLessThan(AutoSuggestTheme.radiusMedium, AutoSuggestTheme.radiusLarge)
    }
}
