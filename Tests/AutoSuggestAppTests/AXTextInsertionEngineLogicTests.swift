import XCTest
@testable import AutoSuggestApp

/// Characterization tests for the pure range-math helper `replacingText`.
/// These pin down CURRENT behavior (NSString / UTF-16 semantics) so plans 003
/// and 004, which rewrite parts of AXTextInsertionEngine, cannot silently regress.
@MainActor
final class AXTextInsertionEngineLogicTests: XCTestCase {
    func testInsertAtCaretInMiddle() {
        let engine = AXTextInsertionEngine()
        // Caret (range length 0) after "Hel": insert "XYZ".
        let result = engine.replacingText(
            in: "Hello",
            selectedRange: NSRange(location: 3, length: 0),
            replacement: "XYZ"
        )
        XCTAssertEqual(result, "HelXYZlo")
    }

    func testReplaceNonEmptySelection() {
        let engine = AXTextInsertionEngine()
        // Select "llo" (location 2, length 3) and replace with "p".
        let result = engine.replacingText(
            in: "Hello",
            selectedRange: NSRange(location: 2, length: 3),
            replacement: "p"
        )
        XCTAssertEqual(result, "Hep")
    }

    func testLocationBeyondLengthClampsAndAppendsAtEnd() {
        let engine = AXTextInsertionEngine()
        // CHARACTERIZATION: location (99) beyond text length is clamped to the
        // end (lines 61-63), so the replacement is appended rather than crashing.
        let result = engine.replacingText(
            in: "Hello",
            selectedRange: NSRange(location: 99, length: 0),
            replacement: "!"
        )
        XCTAssertEqual(result, "Hello!")
    }

    func testLengthOverrunningEndClampsToAvailableLength() {
        let engine = AXTextInsertionEngine()
        // CHARACTERIZATION: length (50) past the end is clamped to the remaining
        // characters from the (clamped) location, so the tail is replaced cleanly.
        let result = engine.replacingText(
            in: "Hello",
            selectedRange: NSRange(location: 2, length: 50),
            replacement: "y"
        )
        XCTAssertEqual(result, "Hey")
    }

    func testEmptySourceTextWithInsertion() {
        let engine = AXTextInsertionEngine()
        let result = engine.replacingText(
            in: "",
            selectedRange: NSRange(location: 0, length: 0),
            replacement: "inserted"
        )
        XCTAssertEqual(result, "inserted")
    }

    func testReplacementContainingEmoji() {
        let engine = AXTextInsertionEngine()
        // NSString uses UTF-16 semantics. "Hi " is 3 UTF-16 units; inserting at
        // the end yields "Hi " followed by the emoji. Asserting the exact output
        // catches future Swift.String refactors that shift grapheme handling.
        let emoji = "👍"
        let result = engine.replacingText(
            in: "Hi ",
            selectedRange: NSRange(location: 3, length: 0),
            replacement: emoji
        )
        XCTAssertEqual(result, "Hi 👍")
        // The emoji is a single grapheme but two UTF-16 code units; the NSString
        // result length reflects that (3 + 2 = 5).
        XCTAssertEqual((result as NSString).length, 5)
    }
}
