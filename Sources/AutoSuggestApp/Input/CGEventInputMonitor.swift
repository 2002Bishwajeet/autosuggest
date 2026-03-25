import Foundation
import CoreGraphics

final class CGEventInputMonitor: InputMonitor {
    private let logger = Logger(scope: "CGEventInputMonitor")
    private let permissionManager = PermissionManager()
    private let inputMethodMonitor = InputMethodMonitor()
    private var onEvent: ((InputEvent) -> Void)?
    private var isStarted = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func start(onEvent: @escaping (InputEvent) -> Void) {
        guard !isStarted else { return }
        self.onEvent = onEvent

        if !permissionManager.hasInputMonitoringPermission() {
            logger.warn("Input Monitoring permission missing; requesting access.")
            _ = permissionManager.requestInputMonitoringPermission()
        }
        guard permissionManager.hasInputMonitoringPermission() else {
            logger.error("Input Monitoring permission denied. Event tap will not start.")
            self.onEvent = nil
            return
        }

        guard installEventTap() else {
            logger.error("Failed to install CGEvent tap.")
            self.onEvent = nil
            return
        }
        isStarted = true
        logger.info("CGEvent monitor started.")
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        uninstallEventTap()
        onEvent = nil
        logger.info("CGEvent monitor stopped.")
    }

    private func installEventTap() -> Bool {
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let monitor = Unmanaged<CGEventInputMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            monitor.handleCGEvent(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: userInfo
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        return true
    }

    private func uninstallEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
    }

    private func handleCGEvent(type: CGEventType, event: CGEvent) {
        guard type == .keyDown else { return }
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 1 {
            return
        }
        if inputMethodMonitor.isIMEActive() {
            return
        }
        onEvent?(
            InputEvent(
                timestamp: Date(),
                keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
                flags: UInt64(event.flags.rawValue)
            )
        )
    }
}
