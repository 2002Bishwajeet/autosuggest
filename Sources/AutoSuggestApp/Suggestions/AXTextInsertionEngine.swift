import ApplicationServices
import AppKit
import Foundation

@MainActor
final class AXTextInsertionEngine: TextInsertionEngine {
    private let logger = Logger(scope: "AXTextInsertionEngine")
    private let strictUndoSemantics: Bool

    init(strictUndoSemantics: Bool = true) {
        self.strictUndoSemantics = strictUndoSemantics
    }

    func insertSuggestion(_ suggestion: String) -> Bool {
        guard !suggestion.isEmpty else { return false }

        // Prefer paste path so accepted suggestion is usually a separate undo operation.
        if insertByClipboardPaste(suggestion) {
            return true
        }
        if strictUndoSemantics {
            logger.warn("Strict undo semantics enabled, skipping non-paste fallbacks.")
            return false
        }

        let systemWide = AXUIElementCreateSystemWide()
        guard let focusedElement = copyUIElementAttribute(named: "AXFocusedUIElement", from: systemWide) else {
            return insertByCGEventTyping(suggestion)
        }
        guard let currentText = copyAttribute(named: "AXValue", from: focusedElement) as? String else {
            return insertByCGEventTyping(suggestion)
        }
        guard let selectedRange = extractSelectedRange(from: focusedElement) else {
            return insertByCGEventTyping(suggestion)
        }

        let updatedText = replacingText(
            in: currentText,
            selectedRange: selectedRange,
            replacement: suggestion
        )
        let setValueResult = AXUIElementSetAttributeValue(
            focusedElement,
            "AXValue" as CFString,
            updatedText as CFString
        )
        if setValueResult != .success {
            logger.warn("AX value insertion failed with status \(setValueResult.rawValue), trying fallbacks.")
            return insertByCGEventTyping(suggestion)
        }

        let cursorLocation = min(selectedRange.location + (suggestion as NSString).length, (updatedText as NSString).length)
        if let newRange = makeAXRange(location: cursorLocation, length: 0) {
            _ = AXUIElementSetAttributeValue(focusedElement, "AXSelectedTextRange" as CFString, newRange)
        }
        return true
    }

    private func replacingText(in text: String, selectedRange: NSRange, replacement: String) -> String {
        let nsText = text as NSString
        let safeLocation = max(0, min(selectedRange.location, nsText.length))
        let safeLength = max(0, min(selectedRange.length, nsText.length - safeLocation))
        let safeRange = NSRange(location: safeLocation, length: safeLength)
        return nsText.replacingCharacters(in: safeRange, with: replacement)
    }

    private func copyAttribute(named attribute: String, from element: AXUIElement) -> AnyObject? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value
    }

    private func copyUIElementAttribute(named attribute: String, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let value else { return nil }
        return AXHelpers.castToAXUIElement(value)
    }

    private func extractSelectedRange(from element: AXUIElement) -> NSRange? {
        guard let selectedRangeValue = copyAttribute(named: "AXSelectedTextRange", from: element) else {
            return nil
        }
        guard CFGetTypeID(selectedRangeValue) == AXValueGetTypeID() else {
            return nil
        }

        guard let axValue = AXHelpers.castToAXValue(selectedRangeValue) else { return nil }
        var range = CFRange()
        guard AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range) else {
            return nil
        }

        guard range.location >= 0, range.length >= 0 else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    private func makeAXRange(location: Int, length: Int) -> AXValue? {
        var range = CFRange(location: location, length: length)
        return AXValueCreate(.cfRange, &range)
    }

    private static let clipboardBackupKey = "autosuggest.clipboardBackup"

    static func restoreClipboardIfNeeded() {
        guard let backup = UserDefaults.standard.string(forKey: clipboardBackupKey) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(backup, forType: .string)
        UserDefaults.standard.removeObject(forKey: clipboardBackupKey)
    }

    private func insertByClipboardPaste(_ suggestion: String) -> Bool {
        let pasteboard = NSPasteboard.general
        let existing = pasteboard.string(forType: .string)

        // Back up clipboard to UserDefaults in case app crashes mid-paste
        if let existing {
            UserDefaults.standard.set(existing, forKey: Self.clipboardBackupKey)
        }

        pasteboard.clearContents()
        pasteboard.setString(suggestion, forType: .string)

        guard sendCommandV() else {
            // Restore immediately on failure
            if let existing {
                pasteboard.clearContents()
                pasteboard.setString(existing, forType: .string)
            }
            UserDefaults.standard.removeObject(forKey: Self.clipboardBackupKey)
            return false
        }

        // Brief delay so paste event can be processed before clipboard restore
        Thread.sleep(forTimeInterval: 0.05)

        if let existing {
            pasteboard.clearContents()
            pasteboard.setString(existing, forType: .string)
        }
        UserDefaults.standard.removeObject(forKey: Self.clipboardBackupKey)
        return true
    }

    private func insertByCGEventTyping(_ suggestion: String) -> Bool {
        for scalar in suggestion.unicodeScalars {
            guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
                return false
            }
            var value = UInt16(scalar.value)
            keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &value)
            keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &value)
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
        return true
    }

    private func sendCommandV() -> Bool {
        guard let commandDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x37, keyDown: true),  // command
              let vDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true),       // v
              let vUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false),
              let commandUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x37, keyDown: false) else {
            return false
        }

        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        commandDown.post(tap: .cghidEventTap)
        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)
        commandUp.post(tap: .cghidEventTap)
        return true
    }
}
