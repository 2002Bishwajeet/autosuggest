import ApplicationServices
import Foundation
import CoreGraphics
import AppKit

struct PermissionManager {
    func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    @MainActor
    func requestAccessibilityPermission() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func hasInputMonitoringPermission() -> Bool {
        if CGPreflightListenEventAccess() {
            return true
        }
        return canCreateListenOnlyEventTap()
    }

    func requestInputMonitoringPermission() -> Bool {
        CGRequestListenEventAccess()
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    private func canCreateListenOnlyEventTap() -> Bool {
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, _, event, _ in
            Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: nil
        ) else {
            return false
        }

        CFMachPortInvalidate(tap)
        return true
    }
}
