import AppKit
import ApplicationServices
import Foundation

final class AXTextContextProvider: TextContextProvider {
    private let logger = Logger(scope: "AXTextContextProvider")

    /// Bundle-ID prefixes/markers for Chromium-class apps whose AX text stays
    /// hidden until we opt the app element into accessibility (B6).
    /// Verified against installed bundles with `scripts/ax-probe.swift`; see
    /// `docs/AX_COMPAT_MATRIX.md`. Electron ships whatever bundle ID the vendor
    /// picks, so there is no pattern to match — each app is listed by hand.
    static let chromiumBundleMarkers = [
        "com.google.Chrome",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.vivaldi.Vivaldi",
        "company.thebrowser.Browser", // Arc
        "com.github.Electron",
        "com.microsoft.VSCode", // VS Code (also matches VSCodeInsiders)
        "com.visualstudio.code", // VS Code OSS / VSCodium builds
        "com.google.antigravity", // Antigravity (VS Code fork)
        "com.todesktop", // Cursor and other ToDesktop-packaged editors
        "com.tinyspeck.slackmacgap", // Slack
        "com.hnc.Discord",
        "org.whispersystems.signal-desktop", // Signal
        "md.obsidian", // Obsidian
        "com.figma.Desktop",
        "notion.id", // Notion
        "com.electron", // generic Electron prefix
    ]

    /// Whether `bundleID` names a Chromium/Electron app that needs the
    /// `AXManualAccessibility` opt-in before its text tree is readable.
    static func needsChromiumAXUnlock(bundleID: String) -> Bool {
        chromiumBundleMarkers.contains { bundleID.hasPrefix($0) }
    }

    func currentContext() -> TextContext? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontApp.bundleIdentifier else {
            return nil
        }

        // B6: unlock AX text in Chromium/Electron apps before reading.
        enableElectronAccessibilityIfNeeded(bundleID: bundleID, pid: frontApp.processIdentifier)

        guard let (focusedElement, focusRoot) = focusedElementAndRoot(
            pid: frontApp.processIdentifier
        ) else {
            return nil
        }
        AXUIElementSetMessagingTimeout(focusedElement, 0.5)

        let role = (copyAttribute(named: "AXRole", from: focusedElement) as? String) ?? ""
        let subrole = (copyAttribute(named: "AXSubrole", from: focusedElement) as? String) ?? ""
        let roleMarker = [role, subrole].filter { !$0.isEmpty }.joined(separator: ":")
        let fullValue = extractFullValue(from: focusedElement)
        let selectedRange = extractSelectedRange(from: focusedElement, fullValue: fullValue)
        let textBeforeCaret = extractTextBeforeCaret(fullValue: fullValue, selectedRange: selectedRange)
        let caretRect = extractCaretRect(from: focusedElement, selectedRange: selectedRange)
        let windowTitle = extractFocusedWindowTitle(focusRoot: focusRoot)
        let caretFont = extractCaretFont(from: focusedElement, selectedRange: selectedRange)
        let nativeSuggestionPresent = detectNativeInlineSuggestion(from: focusedElement)

        return TextContext(
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
            caretRectInScreen: caretRect,
            caretFont: caretFont,
            nativeInlineSuggestionPresent: nativeSuggestionPresent
        )
    }

    /// Resolves the focused element, and the root it was resolved from.
    ///
    /// The system-wide element is the normal path, but it can return
    /// `kAXErrorAPIDisabled (-25204)` in trust configurations where the per-application
    /// element still answers fine (observed while probing for #30 — see
    /// docs/AX_COMPAT_MATRIX.md). System-wide-only means the whole feature goes silent
    /// there, so fall back to the app element rather than giving up.
    ///
    /// The root comes back with the element because the focused *window* has to be read
    /// from the same one — a system-wide root that cannot answer `AXFocusedUIElement`
    /// will not answer `AXFocusedWindow` either.
    ///
    /// Costs no extra AX IPC on the happy path: the fallback is only consulted when the
    /// system-wide read already failed, which would otherwise have returned nil.
    func focusedElementAndRoot(pid: pid_t) -> (element: AXUIElement, root: AXUIElement)? {
        // Creating the elements is local (no IPC); only the attribute reads talk to
        // other processes, and those stop at the first root that answers.
        focusedElementAndRoot(roots: [AXUIElementCreateSystemWide(), AXUIElementCreateApplication(pid)])
    }

    /// First root that can answer `AXFocusedUIElement`, with that root.
    /// Split out from `focusedElementAndRoot(pid:)` so the "nothing answers" contract is
    /// testable without Accessibility trust.
    func focusedElementAndRoot(roots: [AXUIElement]) -> (element: AXUIElement, root: AXUIElement)? {
        for root in roots {
            // ponytail: these reads run synchronously on the main thread on every
            // keystroke and issue cross-process AX IPC (incl. parameterized layout
            // queries). Without a timeout a hung/busy target app blocks typing
            // indefinitely. Cap every AX message at 0.5s — a hang guard, not a perf
            // knob; a slow-but-working app just yields no context for that event.
            AXUIElementSetMessagingTimeout(root, 0.5)
            if let element = copyUIElementAttribute(named: "AXFocusedUIElement", from: root) {
                return (element, root)
            }
        }
        return nil
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

    func stringValue(from value: AnyObject) -> String? {
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

    func extractTextBeforeCaret(fullValue: String, selectedRange: NSRange?) -> String {
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
        if let rect = boundsForRange(
            CFRange(location: selectedRange.location, length: selectedRange.length),
            element: element
        ) {
            return axRectToCocoa(rect)
        }
        // A collapsed caret range often yields no bounds; probe the character
        // before the caret and use its rect (whose trailing edge is the caret
        // position) — same trick extractCaretFont uses.
        if selectedRange.length == 0, selectedRange.location > 0,
           let rect = boundsForRange(
               CFRange(location: selectedRange.location - 1, length: 1),
               element: element
           ) {
            return axRectToCocoa(rect)
        }
        if let rect = boundsForSelectedMarkerRange(element: element) {
            return axRectToCocoa(rect)
        }
        return nil
    }

    private func boundsForRange(_ range: CFRange, element: AXUIElement) -> CGRect? {
        var range = range
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
        guard AXValueGetType(axRect) == .cgRect, AXValueGetValue(axRect, .cgRect, &rect) else {
            return nil
        }
        // A zero-height rect is a failed read (some apps return .zero instead
        // of an error); zero WIDTH is fine — that's a collapsed caret.
        guard rect.height > 0 else { return nil }
        return rect
    }

    /// AX rects are top-left-origin; everything downstream of TextContext is
    /// Cocoa bottom-left. Convert once, here at the AX boundary.
    private func axRectToCocoa(_ rect: CGRect) -> CGRect {
        GhostTextLayout.cocoaRect(
            fromAXRect: rect,
            primaryScreenHeight: NSScreen.screens.first?.frame.height ?? 0
        )
    }

    private func extractFocusedWindowTitle(focusRoot: AXUIElement) -> String? {
        guard let focusedWindow = copyUIElementAttribute(
            named: "AXFocusedWindow",
            from: focusRoot
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

    // MARK: - B1: real field font

    /// Reads the focused field's font via the `AXAttributedStringForRange`
    /// parameterized attribute over the caret/selection range, then extracts
    /// the `.font` / `kCTFontAttributeName` attribute (B1). Returns `nil` when AX
    /// exposes no styled text or no font; the renderer then falls back to the
    /// caret-height heuristic.
    func extractCaretFont(from element: AXUIElement, selectedRange: NSRange?) -> NSFont? {
        guard let selectedRange else { return nil }
        // A zero-length caret range yields no glyphs; read one character around
        // the caret so the attributed run carries a font.
        let probeLength = max(selectedRange.length, 1)
        let probeLocation = selectedRange.length == 0 && selectedRange.location > 0
            ? selectedRange.location - 1
            : selectedRange.location
        var range = CFRange(location: probeLocation, length: probeLength)
        guard let rangeValue = AXValueCreate(.cfRange, &range) else { return nil }

        var attrRef: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXAttributedStringForRange" as CFString,
            rangeValue,
            &attrRef
        )
        guard result == .success, let attrRef else { return nil }

        // The value is a CFAttributedString, bridged to NSAttributedString.
        if let nsAttr = attrRef as? NSAttributedString {
            return AXFontExtraction.font(from: nsAttr)
        }
        if let cfAttr = AXHelpers.castToCFAttributedString(attrRef) {
            // Bridge CFAttributedString -> NSAttributedString.
            let nsAttr = cfAttr as NSAttributedString
            return AXFontExtraction.font(from: nsAttr)
        }
        return nil
    }

    // MARK: - B5: native inline-suggestion detection (best-effort)

    /// Best-effort AX read of whether Apple's own native inline prediction is
    /// already showing on the focused element (B5 PRIMARY signal). Reads the
    /// completion-markup attributes the RE spike found readable
    /// (`AXIsSuggestion` / `AXCompletionText` family). Best-effort: any failure
    /// returns `false` (we show our overlay) and the per-app backstop covers the
    /// gap. Never logs the suggestion text (privacy invariant).
    func detectNativeInlineSuggestion(from element: AXUIElement) -> Bool {
        // Boolean marker attribute: present + true means a suggestion is active.
        if let flag = copyAttribute(named: "AXIsSuggestion", from: element) as? NSNumber,
           flag.boolValue {
            return true
        }
        // Some fields expose the active completion as a non-empty string.
        if let completion = copyAttribute(named: "AXCompletionText", from: element) as? String,
           !completion.isEmpty {
            return true
        }
        // TextKit2 inline-prediction marker seen on native NSTextViews.
        if let inline = copyAttribute(named: "AXInlinePredictionText", from: element) as? String,
           !inline.isEmpty {
            return true
        }
        return false
    }

    // MARK: - B6: Electron / Chromium AX coverage

    /// Many Chromium/Electron apps hide their AX text tree until the app element
    /// is explicitly opted in. On detecting such an app we set
    /// `AXManualAccessibility` (and the older `AXEnhancedUserInterface`) = true
    /// on the application element to unlock AX text (B6). Idempotent and cheap;
    /// when it has no effect we keep the existing "no overlay when AX empty"
    /// behavior — no regressions.
    ///
    /// For apps that still refuse, launch them with the Chromium flag
    /// `--force-renderer-accessibility=complete` (documented for users).
    private func enableElectronAccessibilityIfNeeded(bundleID: String, pid: pid_t) {
        guard Self.needsChromiumAXUnlock(bundleID: bundleID) else {
            return
        }
        let appElement = AXUIElementCreateApplication(pid)
        let trueValue = kCFBooleanTrue as CFTypeRef
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, trueValue)
        AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, trueValue)
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
