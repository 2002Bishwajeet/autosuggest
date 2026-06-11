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

    func replacingText(in text: String, selectedRange: NSRange, replacement: String) -> String {
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
    /// UserDefaults is not a good home for large blobs; cap the encoded crash
    /// backup at 1 MB and fall back to a plain-string backup above that.
    private static let clipboardBackupMaxBytes = 1 * 1024 * 1024

    static func restoreClipboardIfNeeded() {
        let defaults = UserDefaults.standard
        defer { defaults.removeObject(forKey: clipboardBackupKey) }
        let pasteboard = NSPasteboard.general
        if let data = defaults.data(forKey: clipboardBackupKey),
           let snapshot = try? PropertyListDecoder().decode(PasteboardSnapshot.self, from: data) {
            snapshot.restore(to: pasteboard)
        } else if let legacy = defaults.string(forKey: clipboardBackupKey) {
            pasteboard.clearContents()
            pasteboard.setString(legacy, forType: .string)
        }
    }

    private func insertByClipboardPaste(_ suggestion: String) -> Bool {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        // Back up clipboard to UserDefaults in case app crashes mid-paste.
        let defaults = UserDefaults.standard
        if let encoded = try? PropertyListEncoder().encode(snapshot),
           encoded.count <= Self.clipboardBackupMaxBytes {
            defaults.set(encoded, forKey: Self.clipboardBackupKey)
        } else if let existingString = pasteboard.string(forType: .string) {
            // UserDefaults is the wrong place for huge blobs; fall back to the
            // plain-string crash backup when the snapshot is too big to store.
            defaults.set(existingString, forKey: Self.clipboardBackupKey)
        } else {
            defaults.removeObject(forKey: Self.clipboardBackupKey)
        }

        pasteboard.clearContents()
        pasteboard.setString(suggestion, forType: .string)

        guard sendCommandV() else {
            // Restore immediately on failure.
            snapshot.restore(to: pasteboard)
            defaults.removeObject(forKey: Self.clipboardBackupKey)
            return false
        }

        // Defer restore so the paste event can be processed before the clipboard
        // is restored, without blocking the main thread. The crash-backup key is
        // cleared inside the deferred block so a crash in the 50ms window still
        // restores the user's clipboard on next launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            snapshot.restore(to: pasteboard)
            defaults.removeObject(forKey: Self.clipboardBackupKey)
        }
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

/// A full, type-preserving snapshot of an `NSPasteboard`'s contents.
///
/// Unlike a plain `string(forType:)` backup, this captures every pasteboard
/// item with every type identifier, so non-string content (images, files,
/// rich text) survives a backup/restore round-trip.
struct PasteboardSnapshot: Codable {
    /// One entry per pasteboard item; each maps raw type identifiers to data.
    let items: [[String: Data]]

    /// Above this total captured size, fall back to a string-only snapshot:
    /// losing a >16 MB clipboard to memory pressure is worse than the status quo.
    private static let maxCaptureBytes = 16 * 1024 * 1024

    @MainActor
    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        var totalBytes = 0
        var capped = false
        let items = (pasteboard.pasteboardItems ?? []).map { item -> [String: Data] in
            var entry: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    totalBytes += data.count
                    if totalBytes > maxCaptureBytes {
                        capped = true
                        break
                    }
                    entry[type.rawValue] = data
                }
            }
            return entry
        }

        guard !capped else {
            // Too large to snapshot fully; preserve only the string form.
            if let string = pasteboard.string(forType: .string),
               let data = string.data(using: .utf8) {
                return PasteboardSnapshot(items: [[NSPasteboard.PasteboardType.string.rawValue: data]])
            }
            return PasteboardSnapshot(items: [])
        }

        return PasteboardSnapshot(items: items)
    }

    @MainActor
    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let pbItems = items.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (rawType, data) in entry {
                item.setData(data, forType: NSPasteboard.PasteboardType(rawType))
            }
            return item
        }
        pasteboard.writeObjects(pbItems)
    }
}
