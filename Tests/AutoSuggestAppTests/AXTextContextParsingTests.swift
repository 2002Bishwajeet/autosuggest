import XCTest
@testable import AutoSuggestApp

/// Characterization tests for the pure AX context-parsing helpers that feed the
/// policy engine (which decides whether to suggest in secure fields). Pins down
/// current caret-extraction and value-coercion behavior ahead of plan 004.
final class AXTextContextParsingTests: XCTestCase {
    // MARK: - Fields that run their own completion UI

    /// Safari's address bar. Non-localized and stable, unlike its AXDescription.
    func testNativeCompletionUIDetectsSafariAddressBar() {
        XCTAssertTrue(AXTextContextProvider.hasNativeCompletionUI(
            role: "AXTextField",
            identifier: "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD",
            autocompleteValue: nil,
            domClassList: nil
        ))
    }

    /// Chromium's omnibox declares its own autocomplete. Probing showed ordinary web
    /// inputs and contenteditables do not expose this attribute at all, so it is a
    /// specific signal rather than a blunt one.
    func testNativeCompletionUIDetectsChromiumOmnibox() {
        XCTAssertTrue(AXTextContextProvider.hasNativeCompletionUI(
            role: "AXTextField",
            identifier: nil,
            autocompleteValue: "both",
            domClassList: nil
        ))
        // Belt and braces: the DOM class name is not localized either.
        XCTAssertTrue(AXTextContextProvider.hasNativeCompletionUI(
            role: "AXTextField",
            identifier: nil,
            autocompleteValue: nil,
            domClassList: ["BraveOmniboxViewViews"]
        ))
    }

    /// Firefox's address bar exposes no identifier and only a localized description —
    /// the role is the one stable signal.
    func testNativeCompletionUIDetectsFirefoxAddressBar() {
        XCTAssertTrue(AXTextContextProvider.hasNativeCompletionUI(
            role: "AXComboBox",
            identifier: nil,
            autocompleteValue: nil,
            domClassList: nil
        ))
    }

    /// The fields we exist to serve must be untouched: a plain input, a textarea, and a
    /// rich composer all carry none of these signals.
    func testNativeCompletionUISkipsOrdinaryTextFields() {
        for role in ["AXTextField", "AXTextArea", "AXWebArea"] {
            XCTAssertFalse(AXTextContextProvider.hasNativeCompletionUI(
                role: role,
                identifier: nil,
                autocompleteValue: nil,
                domClassList: ["someLayoutClass"]
            ), "\(role) must still receive suggestions")
        }
    }

    /// When no root can answer `AXFocusedUIElement`, the result must be nil rather than a
    /// half-built context. Roots built from pids that own no AX-visible application answer
    /// nothing regardless of Accessibility trust, so this is deterministic in CI.
    ///
    /// The success paths (system-wide, and the per-app fallback) need a live focused app
    /// and are exercised by `scripts/ax-probe.swift` instead — see docs/AX_COMPAT_MATRIX.md.
    func testFocusedElementAndRootReturnsNilWhenNoRootAnswers() {
        let provider = AXTextContextProvider()
        let deadRoots = [AXUIElementCreateApplication(-1), AXUIElementCreateApplication(-2)]
        XCTAssertNil(provider.focusedElementAndRoot(roots: deadRoots))
    }

    /// Ordering is the point of the fallback: the system-wide root is tried first and the
    /// per-app root only backs it up, so an empty list must not silently succeed.
    func testFocusedElementAndRootReturnsNilForNoRoots() {
        XCTAssertNil(AXTextContextProvider().focusedElementAndRoot(roots: []))
    }

    // MARK: - extractTextBeforeCaret

    func testExtractTextBeforeCaretMidText() {
        let provider = AXTextContextProvider()
        let result = provider.extractTextBeforeCaret(
            fullValue: "Hello world",
            selectedRange: NSRange(location: 5, length: 0)
        )
        XCTAssertEqual(result, "Hello")
    }

    func testExtractTextBeforeCaretNilRangeReturnsFullValue() {
        let provider = AXTextContextProvider()
        let result = provider.extractTextBeforeCaret(
            fullValue: "Hello world",
            selectedRange: nil
        )
        XCTAssertEqual(result, "Hello world")
    }

    func testExtractTextBeforeCaretLocationZeroReturnsEmpty() {
        let provider = AXTextContextProvider()
        let result = provider.extractTextBeforeCaret(
            fullValue: "Hello world",
            selectedRange: NSRange(location: 0, length: 0)
        )
        XCTAssertEqual(result, "")
    }

    func testExtractTextBeforeCaretLocationBeyondLengthClampsToFull() {
        let provider = AXTextContextProvider()
        // CHARACTERIZATION: caret beyond text length is clamped to the end
        // (line 107), returning the full value rather than crashing.
        let result = provider.extractTextBeforeCaret(
            fullValue: "Hello",
            selectedRange: NSRange(location: 99, length: 0)
        )
        XCTAssertEqual(result, "Hello")
    }

    // MARK: - stringValue(from:)

    func testStringValueFromSwiftString() {
        let provider = AXTextContextProvider()
        let value: AnyObject = "plain string" as NSString
        XCTAssertEqual(provider.stringValue(from: value), "plain string")
    }

    func testStringValueFromAttributedStringReturnsString() {
        let provider = AXTextContextProvider()
        let attributed = NSAttributedString(string: "attributed text")
        XCTAssertEqual(provider.stringValue(from: attributed), "attributed text")
    }

    func testStringValueFromNumberReturnsStringValue() {
        let provider = AXTextContextProvider()
        let number = NSNumber(value: 42)
        XCTAssertEqual(provider.stringValue(from: number), "42")
    }

    // MARK: - Chromium/Electron AX unlock list

    /// Electron apps ship arbitrary bundle IDs, so every high-traffic one has to
    /// be listed by hand or its text tree stays invisible to us.
    func testChromiumUnlockCoversHighTrafficElectronApps() {
        for bundleID in [
            "com.microsoft.VSCode",
            "com.microsoft.VSCodeInsiders",
            "com.google.antigravity",
            "com.tinyspeck.slackmacgap",
            "com.hnc.Discord",
            "org.whispersystems.signal-desktop",
            "md.obsidian",
            "com.google.Chrome",
            "com.brave.Browser",
        ] {
            XCTAssertTrue(
                AXTextContextProvider.needsChromiumAXUnlock(bundleID: bundleID),
                "\(bundleID) must get the AXManualAccessibility opt-in"
            )
        }
    }

    func testChromiumUnlockSkipsNativeApps() {
        for bundleID in ["com.apple.TextEdit", "com.apple.Safari", "net.whatsapp.WhatsApp", "ru.keepcoder.Telegram"] {
            XCTAssertFalse(
                AXTextContextProvider.needsChromiumAXUnlock(bundleID: bundleID),
                "\(bundleID) is native; it must not be treated as Chromium"
            )
        }
    }
}
