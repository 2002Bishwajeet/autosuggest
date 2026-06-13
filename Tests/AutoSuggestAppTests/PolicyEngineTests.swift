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
