import XCTest
@testable import AutoSuggestApp

final class PolicyEngineTests: XCTestCase {
    func testCodingBundleIsExcluded() {
        let engine = PolicyEngine(defaults: .default)
        let context = PolicyContext(
            bundleID: "com.microsoft.VSCode",
            axRole: "AXTextField",
            isSecureField: false,
            windowTitle: nil,
            textPrefix: ""
        )
        XCTAssertFalse(engine.shouldSuggest(in: context))
    }

    func testPasswordManagerBundleIsExcluded() {
        let engine = PolicyEngine(defaults: .default)
        let context = PolicyContext(
            bundleID: "com.1password.1password",
            axRole: "AXTextField",
            isSecureField: false,
            windowTitle: nil,
            textPrefix: "looking up a login"
        )
        XCTAssertFalse(engine.shouldSuggest(in: context))
    }

    /// Terminals expose a text surface that looks writable to AX but is a shell
    /// prompt. Probing (docs/AX_COMPAT_MATRIX.md) showed Terminal.app reporting the
    /// visible prompt line as AXValue, and Ghostty reporting the entire scrollback
    /// with the caret pinned at offset 0 — so the completion context is wrong even
    /// when it is readable, and an accepted suggestion lands on a command line.
    func testTerminalBundlesAreExcluded() {
        let engine = PolicyEngine(defaults: .default)
        for bundleID in ["com.apple.Terminal", "com.mitchellh.ghostty", "com.googlecode.iterm2"] {
            let context = PolicyContext(
                bundleID: bundleID,
                axRole: "AXTextArea",
                isSecureField: false,
                windowTitle: nil,
                textPrefix: "git comm"
            )
            XCTAssertFalse(engine.shouldSuggest(in: context), "\(bundleID) must not get suggestions")
        }
    }

    /// Address bars and combo boxes run their own completion UI; ghost text there would
    /// overlap the browser's own inline suggestion. Note the role is a plain text field —
    /// the pre-existing `contains("url")` check cannot catch this, which is why real
    /// browsers were never actually excluded.
    func testFieldWithNativeCompletionUIIsExcluded() {
        let engine = PolicyEngine(defaults: .default)
        let context = PolicyContext(
            bundleID: "com.apple.Safari",
            axRole: "AXTextField",
            isSecureField: false,
            hasNativeCompletionUI: true,
            windowTitle: "Example page",
            textPrefix: "https://exam"
        )
        XCTAssertFalse(engine.shouldSuggest(in: context))
    }

    func testSecureFieldIsExcluded() {
        let engine = PolicyEngine(defaults: .default)
        let context = PolicyContext(
            bundleID: "com.apple.Notes",
            axRole: "AXTextField",
            isSecureField: true,
            windowTitle: nil,
            textPrefix: ""
        )
        XCTAssertFalse(engine.shouldSuggest(in: context))
    }

    func testNormalTextFieldIsAllowed() {
        let engine = PolicyEngine(defaults: .default)
        let context = PolicyContext(
            bundleID: "com.apple.Notes",
            axRole: "AXTextArea",
            isSecureField: false,
            windowTitle: nil,
            textPrefix: "Drafting a normal message"
        )
        XCTAssertTrue(engine.shouldSuggest(in: context))
    }

    func testCodePatternTextIsExcluded() {
        let engine = PolicyEngine(defaults: .default)
        let context = PolicyContext(
            bundleID: "com.apple.Notes",
            axRole: "AXTextArea",
            isSecureField: false,
            windowTitle: nil,
            textPrefix: "func buildPlan() {"
        )
        XCTAssertFalse(engine.shouldSuggest(in: context))
    }

    func testCodeFileTitleIsExcluded() {
        let engine = PolicyEngine(defaults: .default)
        let context = PolicyContext(
            bundleID: "com.apple.TextEdit",
            axRole: "AXTextArea",
            isSecureField: false,
            windowTitle: "main.swift — Edited",
            textPrefix: "Writing notes"
        )
        XCTAssertFalse(engine.shouldSuggest(in: context))
    }

    func testUserRuleByBundleIDIsExcluded() {
        let rules = [
            ExclusionRule(
                enabled: true,
                bundleID: "com.apple.Notes",
                windowTitleContains: nil,
                contentPattern: nil
            ),
        ]
        let engine = PolicyEngine(defaults: .default, userRules: rules)
        let context = PolicyContext(
            bundleID: "com.apple.Notes",
            axRole: "AXTextArea",
            isSecureField: false,
            windowTitle: "Untitled",
            textPrefix: "Hello"
        )
        XCTAssertFalse(engine.shouldSuggest(in: context))
    }

    func testUserRuleByContentRegexIsExcluded() {
        let rules = [
            ExclusionRule(
                enabled: true,
                bundleID: nil,
                windowTitleContains: nil,
                contentPattern: "ticket\\s+#\\d+"
            ),
        ]
        let engine = PolicyEngine(defaults: .default, userRules: rules)
        let context = PolicyContext(
            bundleID: "com.apple.Notes",
            axRole: "AXTextArea",
            isSecureField: false,
            windowTitle: "Notes",
            textPrefix: "triaging ticket #1234 now"
        )
        XCTAssertFalse(engine.shouldSuggest(in: context))
    }

    func testExclusionRegexMatchingUnchangedAfterCaching() {
        // Verify that the precompiled-pattern cache does not change match semantics.
        let pattern = "secret\\s+key"
        let rules = [
            ExclusionRule(
                enabled: true,
                bundleID: nil,
                windowTitleContains: nil,
                contentPattern: pattern
            ),
        ]
        let engine = PolicyEngine(defaults: .default, userRules: rules)
        let matchCtx = PolicyContext(
            bundleID: "com.apple.Notes",
            axRole: "AXTextArea",
            isSecureField: false,
            windowTitle: nil,
            textPrefix: "my SECRET   key is here"
        )
        let noMatchCtx = PolicyContext(
            bundleID: "com.apple.Notes",
            axRole: "AXTextArea",
            isSecureField: false,
            windowTitle: nil,
            textPrefix: "nothing sensitive"
        )
        XCTAssertFalse(engine.shouldSuggest(in: matchCtx), "Should exclude: text matches cached regex")
        XCTAssertTrue(engine.shouldSuggest(in: noMatchCtx), "Should allow: text does not match pattern")
    }
}
