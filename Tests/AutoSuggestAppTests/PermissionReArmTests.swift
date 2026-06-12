import XCTest
@testable import AutoSuggestApp

final class PermissionReArmTests: XCTestCase {
    func testNoActionWhenAlreadyArmed() {
        XCTAssertEqual(PermissionReArm.decide(inputMonitoringNowGranted: true, tapCurrentlyActive: true), .none)
    }

    func testReArmWhenGrantedButTapInactive() {
        XCTAssertEqual(
            PermissionReArm.decide(inputMonitoringNowGranted: true, tapCurrentlyActive: false),
            .rebuildAndVerify
        )
    }

    func testNoActionWhenStillDenied() {
        XCTAssertEqual(PermissionReArm.decide(inputMonitoringNowGranted: false, tapCurrentlyActive: false), .none)
    }
}
