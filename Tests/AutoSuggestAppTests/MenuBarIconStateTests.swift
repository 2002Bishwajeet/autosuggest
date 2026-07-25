import XCTest
@testable import AutoSuggestApp

final class MenuBarIconStateTests: XCTestCase {
    func testNeedsPermission() {
        XCTAssertEqual(
            MenuBarIconState.resolve(permissionsReady: false, enabled: true, runtimeReady: true),
            .needsPermission
        )
        XCTAssertEqual(
            MenuBarIconState.resolve(permissionsReady: false, enabled: false, runtimeReady: false),
            .needsPermission
        )
    }

    func testPausedWhenReadyButDisabled() {
        XCTAssertEqual(MenuBarIconState.resolve(permissionsReady: true, enabled: false, runtimeReady: true), .paused)
    }

    func testActiveWhenReadyEnabledAndRuntimeReady() {
        XCTAssertEqual(MenuBarIconState.resolve(permissionsReady: true, enabled: true, runtimeReady: true), .active)
    }

    func testDegradedWhenEnabledButNoRuntimeReady() {
        XCTAssertEqual(MenuBarIconState.resolve(permissionsReady: true, enabled: true, runtimeReady: false), .degraded)
    }

    func testActiveHasNoBadge() {
        XCTAssertNil(MenuBarIconState.active.badge)
    }

    func testAttentionStatesCarryBadges() {
        XCTAssertEqual(MenuBarIconState.paused.badge, .paused)
        XCTAssertEqual(MenuBarIconState.needsPermission.badge, .needsPermission)
        XCTAssertEqual(MenuBarIconState.degraded.badge, .degraded)
    }

    func testBadgeSymbols() {
        XCTAssertEqual(MenuBarBadge.paused.symbolName, "pause.fill")
        XCTAssertEqual(MenuBarBadge.needsPermission.symbolName, "exclamationmark")
        XCTAssertEqual(MenuBarBadge.degraded.symbolName, "bolt.slash.fill")
    }
}
