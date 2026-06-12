import XCTest
@testable import AutoSuggestApp

final class MenuBarIconStateTests: XCTestCase {
    func testNeedsPermission() {
        XCTAssertEqual(MenuBarIconState.resolve(permissionsReady: false, enabled: true), .needsPermission)
        XCTAssertEqual(MenuBarIconState.resolve(permissionsReady: false, enabled: false), .needsPermission)
    }

    func testPausedWhenReadyButDisabled() {
        XCTAssertEqual(MenuBarIconState.resolve(permissionsReady: true, enabled: false), .paused)
    }

    func testActiveWhenReadyAndEnabled() {
        XCTAssertEqual(MenuBarIconState.resolve(permissionsReady: true, enabled: true), .active)
    }
}
