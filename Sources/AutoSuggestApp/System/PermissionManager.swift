import ApplicationServices
import Foundation
import CoreGraphics
import AppKit

struct PermissionManager {
    func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system "wants to control this computer" prompt.
    /// Returns the current trust state. The user may still need to
    /// manually enable it in System Settings if the prompt was dismissed.
    @MainActor
    func requestAccessibilityPermission() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func hasInputMonitoringPermission() -> Bool {
        // CGPreflightListenEventAccess is the authoritative check on macOS 13+.
        if CGPreflightListenEventAccess() {
            return true
        }
        // Fallback: attempt to create a listen-only tap as a secondary indicator.
        return canCreateListenOnlyEventTap()
    }

    /// Registers the app in the Input Monitoring list so the user can enable
    /// it. On macOS 13+ this does NOT show a prompt — the user must go to
    /// System Settings > Privacy & Security > Input Monitoring and toggle it on.
    @discardableResult
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

    /// Relaunches the app. Required after Input Monitoring is granted because
    /// the CGEvent tap must be installed in a new process session.
    @MainActor
    func relaunchApp() {
        let executableURL = Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let process = Process()
        process.executableURL = executableURL
        // Small delay so the current process can cleanly exit first.
        let script = "sleep 0.4 && open \"\(Bundle.main.bundlePath)\""
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", script]
        try? shell.run()
        NSApp.terminate(nil)
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
