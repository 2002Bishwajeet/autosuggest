import AppKit
import CoreText
import XCTest
@testable import AutoSuggestApp

/// B1 — font extraction from a mock AX attributed string (present / absent).
/// AX returns the focused field's styled text; we read the font so the overlay
/// matches the real field font instead of guessing from caret height.
final class AXFontExtractionTests: XCTestCase {
    func testFontFromAppKitFontAttribute() throws {
        let font = NSFont.systemFont(ofSize: 17, weight: .regular)
        let attributed = NSAttributedString(string: "hello", attributes: [.font: font])

        let extracted = AXFontExtraction.font(from: attributed)
        XCTAssertEqual(try XCTUnwrap(extracted).pointSize, 17, accuracy: 0.01)
    }

    func testFontFromCoreTextFontAttribute() throws {
        // Some fields / CFAttributedString producers use kCTFontAttributeName
        // instead of NSAttributedString.Key.font.
        let ctFont = CTFontCreateWithName("Helvetica" as CFString, 21, nil)
        let ctKey = NSAttributedString.Key(kCTFontAttributeName as String)
        let attributed = NSAttributedString(string: "world", attributes: [ctKey: ctFont])

        let extracted = AXFontExtraction.font(from: attributed)
        XCTAssertEqual(try XCTUnwrap(extracted).pointSize, 21, accuracy: 0.01)
    }

    func testFontAbsentReturnsNil() {
        // No font attribute at all → caller must fall back to the heuristic.
        let attributed = NSAttributedString(
            string: "no font here",
            attributes: [.foregroundColor: NSColor.labelColor]
        )
        XCTAssertNil(AXFontExtraction.font(from: attributed))
    }

    func testEmptyAttributedStringReturnsNil() {
        XCTAssertNil(AXFontExtraction.font(from: NSAttributedString(string: "")))
    }

    func testPreservesCustomFamilyAndSize() throws {
        let font = NSFont(name: "Menlo", size: 14) ?? NSFont.systemFont(ofSize: 14)
        let attributed = NSAttributedString(string: "code()", attributes: [.font: font])

        let extracted = try XCTUnwrap(AXFontExtraction.font(from: attributed))
        XCTAssertEqual(extracted.pointSize, 14, accuracy: 0.01)
        // Family round-trips when the platform has the font.
        XCTAssertEqual(extracted.familyName, font.familyName)
    }
}
