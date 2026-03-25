import CoreGraphics
import Foundation

@MainActor
final class CGEventShortcutMonitor: SuggestionShortcutMonitor {
    private let logger = Logger(scope: "CGEventShortcutMonitor")
    private var isStarted = false
    private var handler: ((SuggestionCommand) -> Bool)?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func start(handler: @escaping (SuggestionCommand) -> Bool) {
        guard !isStarted else { return }
        self.handler = handler

        guard installEventTap() else {
            logger.error("Failed to install shortcut event tap.")
            self.handler = nil
            return
        }
        isStarted = true
        logger.info("Shortcut monitor started.")
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        uninstallEventTap()
        handler = nil
        logger.info("Shortcut monitor stopped.")
    }

    private func installEventTap() -> Bool {
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }
            let monitor = Unmanaged<CGEventShortcutMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            let shouldConsume = monitor.handle(type: type, event: event)
            if shouldConsume {
                return nil
            }
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

    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        guard type == .keyDown else { return false }
        let modifiers = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        if !modifiers.isEmpty {
            return false
        }
        let command = mapKeyCodeToCommand(UInt16(event.getIntegerValueField(.keyboardEventKeycode)))
        guard let command else { return false }
        return handler?(command) ?? false
    }

    private func mapKeyCodeToCommand(_ keyCode: UInt16) -> SuggestionCommand? {
        switch keyCode {
        case 48, 36, 76:
            return .accept
        case 53:
            return .dismiss
        default:
            return nil
        }
    }
}
