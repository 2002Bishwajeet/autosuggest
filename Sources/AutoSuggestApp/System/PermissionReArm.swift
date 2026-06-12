import Foundation

/// Pure decision for what to do when the app regains focus and we re-check
/// Input Monitoring. Separated from AppKit so it is unit-testable.
enum PermissionReArm {
    enum Action: Equatable {
        case none // nothing to do
        case rebuildAndVerify // permission present but tap not active: rebuild pipeline, then verify
    }

    static func decide(inputMonitoringNowGranted: Bool, tapCurrentlyActive: Bool) -> Action {
        guard inputMonitoringNowGranted else { return .none }
        return tapCurrentlyActive ? .none : .rebuildAndVerify
    }
}
