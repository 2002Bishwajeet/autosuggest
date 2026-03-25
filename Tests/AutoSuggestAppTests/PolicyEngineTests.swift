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
}
