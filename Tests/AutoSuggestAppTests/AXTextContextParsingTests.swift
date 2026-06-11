import XCTest
@testable import AutoSuggestApp

/// Characterization tests for the pure AX context-parsing helpers that feed the
/// policy engine (which decides whether to suggest in secure fields). Pins down
/// current caret-extraction and value-coercion behavior ahead of plan 004.
final class AXTextContextParsingTests: XCTestCase {
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
}
