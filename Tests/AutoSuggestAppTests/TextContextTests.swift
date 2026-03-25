import XCTest
import CoreGraphics
@testable import AutoSuggestApp

final class TextContextTests: XCTestCase {

    // MARK: - ExclusionRule Equality

    func testExclusionRuleEquality() {
        let rule1 = ExclusionRule(
            enabled: true,
            bundleID: "com.apple.Notes",
            windowTitleContains: "Untitled",
            contentPattern: "hello.*"
        )
        let rule2 = ExclusionRule(
            enabled: true,
            bundleID: "com.apple.Notes",
            windowTitleContains: "Untitled",
            contentPattern: "hello.*"
        )
        XCTAssertEqual(rule1, rule2)
    }

    func testExclusionRuleInequality() {
        let rule1 = ExclusionRule(
            enabled: true,
            bundleID: "com.apple.Notes",
            windowTitleContains: nil,
            contentPattern: nil
        )
        let rule2 = ExclusionRule(
            enabled: true,
            bundleID: "com.apple.Safari",
            windowTitleContains: nil,
            contentPattern: nil
        )
        XCTAssertNotEqual(rule1, rule2)
    }

    // MARK: - ExclusionRule Codable

    func testExclusionRuleCodable() throws {
        let rule = ExclusionRule(
            enabled: true,
            bundleID: "com.apple.Notes",
            windowTitleContains: "Meeting",
            contentPattern: "\\d{3}-\\d{4}"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(rule)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ExclusionRule.self, from: data)

        XCTAssertEqual(decoded, rule)
        XCTAssertEqual(decoded.enabled, true)
        XCTAssertEqual(decoded.bundleID, "com.apple.Notes")
        XCTAssertEqual(decoded.windowTitleContains, "Meeting")
        XCTAssertEqual(decoded.contentPattern, "\\d{3}-\\d{4}")
    }

    func testExclusionRuleWithNilFields() throws {
        let rule = ExclusionRule(
            enabled: false,
            bundleID: nil,
            windowTitleContains: nil,
            contentPattern: nil
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(rule)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ExclusionRule.self, from: data)

        XCTAssertEqual(decoded, rule)
        XCTAssertEqual(decoded.enabled, false)
        XCTAssertNil(decoded.bundleID)
        XCTAssertNil(decoded.windowTitleContains)
        XCTAssertNil(decoded.contentPattern)
    }

    // MARK: - BatteryMode Codable

    func testBatteryModeCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // alwaysOn
        XCTAssertEqual(BatteryMode.alwaysOn.rawValue, "always_on")
        let alwaysOnData = try encoder.encode(BatteryMode.alwaysOn)
        let decodedAlwaysOn = try decoder.decode(BatteryMode.self, from: alwaysOnData)
        XCTAssertEqual(decodedAlwaysOn, .alwaysOn)

        // pauseOnLowPower
        XCTAssertEqual(BatteryMode.pauseOnLowPower.rawValue, "pause_on_low_power")
        let pauseData = try encoder.encode(BatteryMode.pauseOnLowPower)
        let decodedPause = try decoder.decode(BatteryMode.self, from: pauseData)
        XCTAssertEqual(decodedPause, .pauseOnLowPower)
    }

    // MARK: - TextContext Creation

    func testTextContextCreation() {
        let policy = PolicyContext(
            bundleID: "com.apple.TextEdit",
            axRole: "AXTextArea",
            isSecureField: false,
            windowTitle: "Document.txt",
            textPrefix: "Hello world"
        )
        let selectedRange = NSRange(location: 5, length: 6)
        let caretRect = CGRect(x: 100, y: 200, width: 1, height: 16)

        let context = TextContext(
            policyContext: policy,
            textBeforeCaret: "Hello",
            fullText: "Hello world",
            selectedRange: selectedRange,
            caretRectInScreen: caretRect
        )

        XCTAssertEqual(context.policyContext.bundleID, "com.apple.TextEdit")
        XCTAssertEqual(context.textBeforeCaret, "Hello")
        XCTAssertEqual(context.fullText, "Hello world")
        XCTAssertEqual(context.selectedRange, selectedRange)
        XCTAssertEqual(context.caretRectInScreen, caretRect)
    }

    // MARK: - PolicyContext Creation

    func testPolicyContextCreation() {
        let context = PolicyContext(
            bundleID: "com.apple.Safari",
            axRole: "AXTextField",
            isSecureField: true,
            windowTitle: "Google",
            textPrefix: "search query"
        )

        XCTAssertEqual(context.bundleID, "com.apple.Safari")
        XCTAssertEqual(context.axRole, "AXTextField")
        XCTAssertTrue(context.isSecureField)
        XCTAssertEqual(context.windowTitle, "Google")
        XCTAssertEqual(context.textPrefix, "search query")
    }
}
