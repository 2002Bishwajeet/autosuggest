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

    // MARK: - AXFont dictionary (what real apps actually return)

    /// Probed via `scripts/ax-probe.swift` (see docs/AX_COMPAT_MATRIX.md): TextEdit,
    /// Safari, Brave and Firefox all return the font under the AX-native `AXFont`
    /// key as a *dictionary*, never as an NSFont/CTFont. Neither `.font` nor
    /// `kCTFontAttributeName` is ever populated, so those paths alone yield nil in
    /// production and the overlay silently falls back to the caret-height guess.
    func testFontFromAXFontDictionary() throws {
        // Exactly the payload Safari returns for a 16px Helvetica field.
        let axFont: [String: Any] = [
            "AXFontName": "Helvetica",
            "AXFontFamily": "Helvetica",
            "AXFontSize": 16,
        ]
        let attributed = NSAttributedString(
            string: "hello",
            attributes: [NSAttributedString.Key("AXFont"): axFont]
        )

        let extracted = try XCTUnwrap(AXFontExtraction.font(from: attributed))
        XCTAssertEqual(extracted.pointSize, 16, accuracy: 0.01)
        XCTAssertEqual(extracted.familyName, "Helvetica")
    }

    /// TextEdit's payload: a PostScript name with a hyphenated style.
    func testFontFromAXFontDictionaryResolvesPostScriptName() throws {
        let axFont: [String: Any] = [
            "AXFontName": "Menlo-Regular",
            "AXFontFamily": "Menlo",
            "AXFontSize": 11,
            "AXVisibleName": "Menlo Regular",
        ]
        let attributed = NSAttributedString(
            string: "code()",
            attributes: [NSAttributedString.Key("AXFont"): axFont]
        )

        let extracted = try XCTUnwrap(AXFontExtraction.font(from: attributed))
        XCTAssertEqual(extracted.pointSize, 11, accuracy: 0.01)
        XCTAssertEqual(extracted.familyName, "Menlo")
    }

    /// An unresolvable face still carries a usable size — size-correct beats nil,
    /// because the overlay's whole purpose for the font is line metrics.
    func testFontFromAXFontDictionaryFallsBackToSystemFontForUnknownFace() throws {
        let axFont: [String: Any] = [
            "AXFontName": "NoSuchFontFace-Ultra",
            "AXFontSize": 13,
        ]
        let attributed = NSAttributedString(
            string: "x",
            attributes: [NSAttributedString.Key("AXFont"): axFont]
        )

        let extracted = try XCTUnwrap(AXFontExtraction.font(from: attributed))
        XCTAssertEqual(extracted.pointSize, 13, accuracy: 0.01)
    }

    /// No usable size → nil, so the caller uses the caret-height heuristic rather
    /// than rendering ghost text at an invented size.
    func testFontFromAXFontDictionaryWithoutSizeReturnsNil() {
        let axFont: [String: Any] = ["AXFontName": "Helvetica"]
        let attributed = NSAttributedString(
            string: "x",
            attributes: [NSAttributedString.Key("AXFont"): axFont]
        )
        XCTAssertNil(AXFontExtraction.font(from: attributed))
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
