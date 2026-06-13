import AppKit
import CoreGraphics
import XCTest
@testable import AutoSuggestApp

/// B2 — baseline-alignment pure layout function, plus B1 font resolution.
/// Verifies geometry only (no NSPanel / live screen).
final class GhostTextLayoutTests: XCTestCase {
    // MARK: - resolvedFont (B1)

    func testResolvedFontPrefersAXFont() {
        let axFont = NSFont.systemFont(ofSize: 19, weight: .regular)
        let caret = CGRect(x: 0, y: 0, width: 1, height: 16)
        let resolved = GhostTextLayout.resolvedFont(axFont: axFont, caretRect: caret)
        XCTAssertEqual(resolved.pointSize, 19, accuracy: 0.01)
    }

    func testResolvedFontFallsBackToCaretHeightHeuristic() {
        // No AX font → derive size from caret height (~0.72 * height).
        let caret = CGRect(x: 0, y: 0, width: 1, height: 20)
        let resolved = GhostTextLayout.resolvedFont(axFont: nil, caretRect: caret)
        XCTAssertEqual(resolved.pointSize, (20 * 0.72).rounded(), accuracy: 0.01)
    }

    func testResolvedFontDefaultsWhenNoFontAndNoUsableCaret() {
        // Degenerate caret height → default 13pt.
        let resolved = GhostTextLayout.resolvedFont(axFont: nil, caretRect: nil)
        XCTAssertEqual(resolved.pointSize, 13, accuracy: 0.01)

        let tinyCaret = CGRect(x: 0, y: 0, width: 1, height: 4)
        let resolvedTiny = GhostTextLayout.resolvedFont(axFont: nil, caretRect: tinyCaret)
        XCTAssertEqual(resolvedTiny.pointSize, 13, accuracy: 0.01)
    }

    // MARK: - ghostFrame baseline alignment (B2)

    func testGhostFrameStartsJustPastCaret() {
        let font = NSFont.systemFont(ofSize: 13)
        let caret = CGRect(x: 100, y: 200, width: 2, height: 16)
        let frame = GhostTextLayout.ghostFrame(
            caretRect: caret,
            font: font,
            measuredSize: CGSize(width: 40, height: 15)
        )
        // Horizontal origin hugs the caret's trailing edge.
        XCTAssertEqual(frame.origin.x, caret.maxX + 1, accuracy: 0.01)
    }

    func testGhostFrameWidthTracksMeasuredText() {
        let font = NSFont.systemFont(ofSize: 13)
        let caret = CGRect(x: 0, y: 0, width: 1, height: 16)
        let frame = GhostTextLayout.ghostFrame(
            caretRect: caret,
            font: font,
            measuredSize: CGSize(width: 80, height: 15)
        )
        XCTAssertEqual(frame.width, 80 + 4, accuracy: 0.01)
    }

    func testGhostFrameBaselineCentersOnCaretLine() {
        // When the panel is taller than the caret line box, the extra height is
        // split evenly so the visual baseline stays on the line (not shoved up
        // or down). The line's vertical center must match the caret's center.
        let font = NSFont.systemFont(ofSize: 24) // tall line height
        let caret = CGRect(x: 50, y: 300, width: 1, height: 16) // shorter caret box
        let frame = GhostTextLayout.ghostFrame(
            caretRect: caret,
            font: font,
            measuredSize: CGSize(width: 60, height: 28)
        )
        let caretCenterY = caret.midY
        let frameCenterY = frame.midY
        XCTAssertEqual(frameCenterY, caretCenterY, accuracy: 0.5)
    }

    func testGhostFrameHeightNeverBelowFloor() {
        let font = NSFont.systemFont(ofSize: 6) // absurdly small
        let caret = CGRect(x: 0, y: 0, width: 1, height: 6)
        let frame = GhostTextLayout.ghostFrame(
            caretRect: caret,
            font: font,
            measuredSize: CGSize(width: 10, height: 6)
        )
        XCTAssertGreaterThanOrEqual(frame.height, 14)
    }

    func testGhostFrameHeightUsesFontLineHeightWhenLarger() {
        let font = NSFont.systemFont(ofSize: 30)
        let caret = CGRect(x: 0, y: 0, width: 1, height: 30)
        let frame = GhostTextLayout.ghostFrame(
            caretRect: caret,
            font: font,
            measuredSize: CGSize(width: 10, height: 10) // smaller than line height
        )
        let lineHeight = (font.ascender - font.descender).rounded(.up)
        XCTAssertEqual(frame.height, max(lineHeight, 14), accuracy: 0.5)
    }
}
