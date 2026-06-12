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

    /// A failed model download must not surface a raw `NSURLErrorDomain -1011` in
    /// the banner; it should give actionable guidance.
    func testModelSetupMessageForBadServerResponseIsActionable() {
        let message = AppCoordinator.friendlyModelSetupMessage(for: URLError(.badServerResponse))
        XCTAssertFalse(message.contains("-1011"))
        XCTAssertTrue(message.contains("Settings → Models"))
    }

    func testModelSetupMessageForOfflinePointsAtServer() {
        let message = AppCoordinator.friendlyModelSetupMessage(for: URLError(.notConnectedToInternet))
        XCTAssertTrue(message.lowercased().contains("ollama"))
    }

    func testModelSetupMessageForNonURLErrorKeepsDescription() {
        struct SampleError: LocalizedError { var errorDescription: String? {
            "disk full"
        } }
        let message = AppCoordinator.friendlyModelSetupMessage(for: SampleError())
        XCTAssertTrue(message.contains("disk full"))
    }
}
