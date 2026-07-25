import XCTest
@testable import AutoSuggestApp

final class OnboardingStepIndicatorTests: XCTestCase {
    func testIndexWithinRangeIsUnchanged() {
        XCTAssertEqual(OnboardingStepIndicator.clampedIndex(2, total: 4), 2)
        XCTAssertEqual(OnboardingStepIndicator.clampedIndex(0, total: 4), 0)
        XCTAssertEqual(OnboardingStepIndicator.clampedIndex(3, total: 4), 3)
    }

    func testNegativeIndexClampsToZero() {
        XCTAssertEqual(OnboardingStepIndicator.clampedIndex(-1, total: 4), 0)
    }

    func testOverflowIndexClampsToLast() {
        XCTAssertEqual(OnboardingStepIndicator.clampedIndex(9, total: 4), 3)
    }

    func testDegenerateTotalYieldsZero() {
        XCTAssertEqual(OnboardingStepIndicator.clampedIndex(0, total: 0), 0)
        XCTAssertEqual(OnboardingStepIndicator.clampedIndex(5, total: 1), 0)
    }
}
