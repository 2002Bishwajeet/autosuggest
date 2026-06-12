import XCTest
@testable import AutoSuggestApp

final class AppCoordinatorPresentationTests: XCTestCase {
    func testHeadlineWhenDisabled() {
        XCTAssertEqual(AppCoordinator.statusHeadline(enabled: false, pauseReason: nil), "Autocomplete is off")
    }

    func testHeadlineWhenPaused() {
        XCTAssertEqual(
            AppCoordinator.statusHeadline(enabled: true, pauseReason: "Paused until 5:00 PM"),
            "Paused until 5:00 PM"
        )
    }

    func testHeadlineWhenLive() {
        XCTAssertEqual(AppCoordinator.statusHeadline(enabled: true, pauseReason: nil), "Suggestions are live")
    }
}
