#!/usr/bin/env swift
//
// ax-probe.swift — reverse-engineer the text-field AX surface of any macOS app.
//
// Usage:
//   swift scripts/ax-probe.swift          # watch mode: prints a row per new app/field
//   swift scripts/ax-probe.swift --once   # probe the focused field right now
//
// Requires Accessibility permission for the *terminal* running it
// (System Settings > Privacy & Security > Accessibility > add Terminal/iTerm/Ghostty).
//
// Privacy: never prints field contents — lengths and shapes only.
// See docs/AX_COMPAT_MATRIX.md for how to turn this output into the matrix.

import AppKit
import ApplicationServices
import CoreText
import Foundation

// MARK: - AX plumbing

func attr(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func paramAttr(_ element: AXUIElement, _ name: String, _ param: CFTypeRef) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyParameterizedAttributeValue(
        element, name as CFString, param, &value
    ) == .success else { return nil }
    return value
}

func rangeValue(_ location: Int, _ length: Int) -> AXValue? {
    var range = CFRange(location: location, length: length)
    return AXValueCreate(.cfRange, &range)
}

func asRect(_ value: CFTypeRef?) -> CGRect? {
    guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    let axValue = value as! AXValue
    var rect = CGRect.zero
    guard AXValueGetType(axValue) == .cgRect, AXValueGetValue(axValue, .cgRect, &rect) else { return nil }
    return rect
}

func asRange(_ value: CFTypeRef?) -> NSRange? {
    guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    let axValue = value as! AXValue
    var range = CFRange()
    guard AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range) else { return nil }
    return NSRange(location: range.location, length: range.length)
}

func asString(_ value: CFTypeRef?) -> String? {
    guard let value else { return nil }
    if let string = value as? String { return string }
    if CFGetTypeID(value) == CFAttributedStringGetTypeID() {
        return CFAttributedStringGetString((value as! CFAttributedString)) as String
    }
    return nil
}

/// Mirrors AXTextContextProvider.enableElectronAccessibilityIfNeeded — Chromium
/// and Electron apps hide their AX text tree until the app element opts in.
func unlockChromiumAX(pid: pid_t) {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
}

// MARK: - The probe

struct Probe {
    var bundleID = "?"
    var focusPath = "systemwide"
    var role = "?"
    var value = "FAIL"
    var selectedRange = "FAIL"
    var boundsCollapsed = "FAIL"
    var boundsOneChar = "FAIL"
    var markerRange = "no"
    var font = "FAIL"
    var secure = "no"
    var nativeSuggestion = "no"

    var markdownRow: String {
        "| \(bundleID) | \(focusPath) | \(role) | \(value) | \(selectedRange) | \(boundsCollapsed) | "
            + "\(boundsOneChar) | \(markerRange) | \(font) | \(secure) | \(nativeSuggestion) |"
    }
}

/// Resolve the focused element the way the product does (system-wide), falling back to
/// the per-application element. The system-wide read returns kAXErrorAPIDisabled (-25204)
/// in some trust configurations where the per-app read still succeeds, so record which
/// path produced the element — a `per-app` row means the system-wide-only path in
/// AXTextContextProvider would have yielded no context at all.
func focusedElement(pid: pid_t) -> (AXUIElement, String)? {
    let systemWide = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(systemWide, 1.0)
    if let raw = attr(systemWide, "AXFocusedUIElement"), CFGetTypeID(raw) == AXUIElementGetTypeID() {
        return ((raw as! AXUIElement), "systemwide")
    }
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 1.0)
    if let raw = attr(app, "AXFocusedUIElement"), CFGetTypeID(raw) == AXUIElementGetTypeID() {
        return ((raw as! AXUIElement), "per-app")
    }
    return nil
}

func probeFocusedElement() -> Probe? {
    guard let front = NSWorkspace.shared.frontmostApplication,
          let bundleID = front.bundleIdentifier else { return nil }
    unlockChromiumAX(pid: front.processIdentifier)

    guard let (element, path) = focusedElement(pid: front.processIdentifier) else { return nil }
    AXUIElementSetMessagingTimeout(element, 1.0)

    var probe = Probe()
    probe.bundleID = bundleID
    probe.focusPath = path

    let role = asString(attr(element, "AXRole")) ?? "?"
    let subrole = asString(attr(element, "AXSubrole")) ?? ""
    probe.role = subrole.isEmpty ? role : "\(role):\(subrole)"
    probe.secure = subrole == "AXSecureTextField" ? "**YES**" : "no"

    // 1. AXValue — length only, never contents.
    if let text = asString(attr(element, "AXValue")) {
        let utf16 = (text as NSString).length
        let graphemes = text.count
        probe.value = utf16 == graphemes ? "len \(utf16)" : "len \(utf16) utf16 / \(graphemes) chars"
    }

    // 2. AXSelectedTextRange — is the collapsed caret where it should be?
    var caret: NSRange?
    if let range = asRange(attr(element, "AXSelectedTextRange")) {
        caret = range
        let textLength = (asString(attr(element, "AXValue")) as NSString?)?.length
        let sane = textLength.map { range.location <= $0 } ?? true
        probe.selectedRange = "loc \(range.location) len \(range.length)\(sane ? "" : " **OUT OF BOUNDS**")"
    }

    // 3. AXBoundsForRange — collapsed caret, then the 1-char-before fallback.
    if let caret, let param = rangeValue(caret.location, caret.length),
       let rect = asRect(paramAttr(element, "AXBoundsForRange", param)) {
        probe.boundsCollapsed = rect.height > 0
            ? String(format: "%.0f,%.0f %.0fx%.0f", rect.origin.x, rect.origin.y, rect.width, rect.height)
            : "zero-rect"
    }
    if let caret, caret.location > 0, let param = rangeValue(caret.location - 1, 1),
       let rect = asRect(paramAttr(element, "AXBoundsForRange", param)) {
        probe.boundsOneChar = rect.height > 0
            ? String(format: "%.0f,%.0f %.0fx%.0f", rect.origin.x, rect.origin.y, rect.width, rect.height)
            : "zero-rect"
    }

    // 4. WebKit marker-range family.
    if let marker = attr(element, "AXSelectedTextMarkerRange") {
        let text = asString(paramAttr(element, "AXStringForTextMarkerRange", marker))
        // Report the rect's DIMENSIONS, not just whether the call answered. This is the
        // last fallback in extractCaretRect, so "answered" is not the same as "usable":
        // it is usable only when height > 0 (zero WIDTH is just a collapsed caret).
        // An earlier version printed "bounds ok" for any non-nil rect and led to the
        // wrong conclusion that Chromium composers could not be anchored at all.
        if let rect = asRect(paramAttr(element, "AXBoundsForTextMarkerRange", marker)) {
            probe.markerRange = rect.height > 0
                ? String(format: "%.0fx%.0f usable", rect.width, rect.height)
                : "zero-height"
        } else {
            probe.markerRange = "bounds FAIL"
        }
        probe.markerRange += text != nil ? " / string ok" : " / string FAIL"
    }

    // 5. Font via AXAttributedStringForRange.
    if let caret {
        let location = caret.length == 0 && caret.location > 0 ? caret.location - 1 : caret.location
        if let param = rangeValue(location, max(caret.length, 1)),
           let value = paramAttr(element, "AXAttributedStringForRange", param),
           CFGetTypeID(value) == CFAttributedStringGetTypeID() {
            let attributed = (value as! CFAttributedString) as NSAttributedString
            // Mirror AXFontExtraction.font(from:): AppKit's .font key first, then the
            // Core Text key. Checking only .font under-reports — web content and several
            // native fields populate kCTFontAttributeName instead.
            if attributed.length > 0 {
                let attrs = attributed.attributes(at: 0, effectiveRange: nil)
                if let axFont = attrs[NSAttributedString.Key("AXFont")] as? [String: Any] {
                    let name = (axFont["AXFontName"] as? String)
                        ?? (axFont["AXFontFamily"] as? String) ?? "?"
                    let size = (axFont["AXFontSize"] as? NSNumber)?.doubleValue ?? 0
                    probe.font = String(format: "%@ %.1f (AXFont)", name, size)
                } else if let font = attrs[.font] as? NSFont {
                    probe.font = String(format: "%@ %.1f (.font)", font.fontName, font.pointSize)
                } else if let raw = attrs[NSAttributedString.Key(kCTFontAttributeName as String)] {
                    let cf = raw as CFTypeRef
                    if CFGetTypeID(cf) == CTFontGetTypeID() {
                        let font = unsafeDowncast(cf, to: CTFont.self) as NSFont
                        probe.font = String(format: "%@ %.1f (CT)", font.fontName, font.pointSize)
                    } else if let font = raw as? NSFont {
                        probe.font = String(format: "%@ %.1f (CT)", font.fontName, font.pointSize)
                    } else {
                        probe.font = "no font attr"
                    }
                } else {
                    probe.font = "no font attr"
                }
            } else {
                probe.font = "empty attr string"
            }
        }
    }

    // 7. Native inline prediction already showing?
    for name in ["AXIsSuggestion", "AXCompletionText", "AXInlinePredictionText"] {
        if attr(element, name) != nil { probe.nativeSuggestion = name }
    }

    return probe
}

// MARK: - Main

let header = """
| Bundle ID | Focus path | Role | AXValue | AXSelectedTextRange | Bounds (caret) | \
Bounds (1-char) | MarkerRange | Font | Secure | Native suggestion |
|---|---|---|---|---|---|---|---|---|---|---|
"""

guard AXIsProcessTrusted() else {
    FileHandle.standardError.write(Data("""
    ax-probe: this process is not Accessibility-trusted.

    Grant it in System Settings > Privacy & Security > Accessibility, adding the
    terminal app you are running from (Terminal.app / iTerm / Ghostty), then rerun.
    Probing from an untrusted process always returns kAXErrorAPIDisabled (-25204).

    """.utf8))
    exit(1)
}

if CommandLine.arguments.contains("--once") {
    guard let probe = probeFocusedElement() else {
        FileHandle.standardError.write(Data("ax-probe: no focused element.\n".utf8))
        exit(1)
    }
    // `--expect <bundleID>` guards scripted collection: focus can move between the
    // keystroke that targets an app and this read, and a row silently attributed to
    // the wrong app is worse than no row.
    if let index = CommandLine.arguments.firstIndex(of: "--expect"),
       let expected = CommandLine.arguments.dropFirst(index + 1).first,
       expected != probe.bundleID {
        FileHandle.standardError.write(Data(
            "ax-probe: expected \(expected), focus was \(probe.bundleID).\n".utf8
        ))
        exit(3)
    }
    print(header)
    print(probe.markdownRow)
    exit(0)
}

print("ax-probe watch mode. Click into a text field in each target app and type a few")
print("characters; a row prints per new app/field. Ctrl-C when done.\n")
print(header)

var seen = Set<String>()
while true {
    if let probe = probeFocusedElement(), seen.insert("\(probe.bundleID)|\(probe.role)").inserted {
        print(probe.markdownRow)
        fflush(stdout)
    }
    Thread.sleep(forTimeInterval: 0.5)
}
