import Foundation
import AppKit
import ApplicationServices

final class AXTextContextProvider: TextContextProvider {
    private let logger = Logger(scope: "AXTextContextProvider")

    func currentContext() -> TextContext? {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return nil
        }

        let systemWide = AXUIElementCreateSystemWide()
        guard let focusedElement = copyUIElementAttribute(
            named: "AXFocusedUIElement",
            from: systemWide
        ) else {
            return nil
        }

        let role = (copyAttribute(named: "AXRole", from: focusedElement) as? String) ?? ""
        let subrole = (copyAttribute(named: "AXSubrole", from: focusedElement) as? String) ?? ""
        let roleMarker = [role, subrole].filter { !$0.isEmpty }.joined(separator: ":")
        let fullValue = extractFullValue(from: focusedElement)
        let selectedRange = extractSelectedRange(from: focusedElement, fullValue: fullValue)
        let textBeforeCaret = extractTextBeforeCaret(fullValue: fullValue, selectedRange: selectedRange)
        let caretRect = extractCaretRect(from: focusedElement, selectedRange: selectedRange)
        let windowTitle = extractFocusedWindowTitle(systemWideElement: systemWide)

        let context = TextContext(
            policyContext: PolicyContext(
                bundleID: bundleID,
                axRole: roleMarker,
                isSecureField: subrole == "AXSecureTextField",
                windowTitle: windowTitle,
                textPrefix: textBeforeCaret
            ),
            textBeforeCaret: textBeforeCaret,
            fullText: fullValue,
            selectedRange: selectedRange,
            caretRectInScreen: caretRect
        )
        return context
    }

    private func copyAttribute(named attribute: String, from element: AXUIElement) -> AnyObject? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else {
            return nil
        }
        return value
    }

    private func extractFullValue(from element: AXUIElement) -> String {
        if let raw = copyAttribute(named: "AXValue", from: element) {
            if let text = stringValue(from: raw) {
                return text
            }
        }

        if let selected = copyAttribute(named: "AXSelectedText", from: element) as? String {
            return selected
        }

        if let markerText = extractTextFromSelectedMarkerRange(element: element) {
            return markerText
        }

        return ""
    }

    private func stringValue(from value: AnyObject) -> String? {
        if let string = value as? String {
            return string
        }
        if let attributed = value as? NSAttributedString {
            return attributed.string
        }
        let cfValue = value as CFTypeRef
        if let cfAttr = AXHelpers.castToCFAttributedString(cfValue) {
            return CFAttributedStringGetString(cfAttr) as String
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if let describable = value as? CustomStringConvertible {
            return describable.description
        }
        return nil
    }

    private func copyUIElementAttribute(named attribute: String, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let value else {
            return nil
        }
        return AXHelpers.castToAXUIElement(value)
    }

    private func extractTextBeforeCaret(fullValue: String, selectedRange: NSRange?) -> String {
        guard let selectedRange else {
            return fullValue
        }
        let nsText = fullValue as NSString
        let caret = max(0, min(selectedRange.location, nsText.length))
        return nsText.substring(to: caret)
    }

    private func extractSelectedRange(from element: AXUIElement, fullValue: String) -> NSRange? {
        guard let selectedRangeValue = copyAttribute(named: "AXSelectedTextRange", from: element) else {
            return fallbackSelectedRange(from: element, fullValue: fullValue)
        }

        guard let axValue = AXHelpers.castToAXValue(selectedRangeValue) else {
            return fallbackSelectedRange(from: element, fullValue: fullValue)
        }
        var range = CFRange()
        guard AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range) else {
            return fallbackSelectedRange(from: element, fullValue: fullValue)
        }

        guard range.location >= 0, range.length >= 0 else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    private func extractCaretRect(from element: AXUIElement, selectedRange: NSRange?) -> CGRect? {
        guard let selectedRange else { return nil }
        var range = CFRange(location: selectedRange.location, length: selectedRange.length)
        guard let rangeValue = AXValueCreate(.cfRange, &range) else { return nil }

        var rectRef: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXBoundsForRange" as CFString,
            rangeValue,
            &rectRef
        )
        guard result == .success, let rectRef else { return nil }
        guard let axRect = AXHelpers.castToAXValue(rectRef) else { return nil }

        var rect = CGRect.zero
        if AXValueGetType(axRect) == .cgRect, AXValueGetValue(axRect, .cgRect, &rect) {
            return rect
        }
        return boundsForSelectedMarkerRange(element: element)
    }

    private func extractFocusedWindowTitle(systemWideElement: AXUIElement) -> String? {
        guard let focusedWindow = copyUIElementAttribute(
            named: "AXFocusedWindow",
            from: systemWideElement
        ) else {
            return nil
        }
        return copyAttribute(named: "AXTitle", from: focusedWindow) as? String
    }

    private func fallbackSelectedRange(from element: AXUIElement, fullValue: String) -> NSRange? {
        if let selectedText = copyAttribute(named: "AXSelectedText", from: element) as? String,
           !selectedText.isEmpty {
            let full = fullValue as NSString
            let match = full.range(of: selectedText, options: .backwards)
            if match.location != NSNotFound {
                return NSRange(location: match.location + match.length, length: 0)
            }
        }

        if copyAttribute(named: "AXSelectedTextMarkerRange", from: element) != nil {
            return NSRange(location: (fullValue as NSString).length, length: 0)
        }
        return nil
    }

    private func extractTextFromSelectedMarkerRange(element: AXUIElement) -> String? {
        guard let markerRange = copyAttribute(named: "AXSelectedTextMarkerRange", from: element) else {
            return nil
        }

        var textRef: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXStringForTextMarkerRange" as CFString,
            markerRange,
            &textRef
        )
        guard result == .success, let textRef else { return nil }
        return (textRef as? String)
    }

    private func boundsForSelectedMarkerRange(element: AXUIElement) -> CGRect? {
        guard let markerRange = copyAttribute(named: "AXSelectedTextMarkerRange", from: element) else {
            return nil
        }

        var rectRef: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXBoundsForTextMarkerRange" as CFString,
            markerRange,
            &rectRef
        )
        guard result == .success, let rectRef else { return nil }
        guard let axRect = AXHelpers.castToAXValue(rectRef) else { return nil }
        var rect = CGRect.zero
        guard AXValueGetType(axRect) == .cgRect, AXValueGetValue(axRect, .cgRect, &rect) else {
            return nil
        }
        return rect
    }
}
