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

    func testActiveHasNoBadge() {
        XCTAssertNil(MenuBarIconState.active.badge)
    }

    func testAttentionStatesCarryBadges() {
        XCTAssertEqual(MenuBarIconState.paused.badge, .paused)
        XCTAssertEqual(MenuBarIconState.needsPermission.badge, .needsPermission)
    }

    func testBadgeSymbols() {
        XCTAssertEqual(MenuBarBadge.paused.symbolName, "pause.fill")
        XCTAssertEqual(MenuBarBadge.needsPermission.symbolName, "exclamationmark")
    }
}
