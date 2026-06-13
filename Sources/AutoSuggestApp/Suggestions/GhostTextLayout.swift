import AppKit
import CoreGraphics
import Foundation

/// Pure layout math for the inline ghost-text overlay.
///
/// Split out of `FloatingOverlayRenderer` so the baseline-alignment geometry
/// (Layer B / B2) can be unit-tested without an `NSPanel` or a live screen.
/// No AppKit windowing, no AX calls — only value-in / value-out arithmetic.
enum GhostTextLayout {
    /// The font the ghost should render in, given the AX-reported field font
    /// (B1) and the caret rectangle. Prefers the real field font; falls back to
    /// the legacy caret-height heuristic only when AX exposed no font.
    ///
    /// - Parameters:
    ///   - axFont: the font read from the focused field via AX, or `nil`.
    ///   - caretRect: the caret/selection rect (screen coords), or `nil`.
    /// - Returns: the font to render the ghost text in.
    static func resolvedFont(axFont: NSFont?, caretRect: CGRect?) -> NSFont {
        if let axFont {
            return axFont
        }
        // Legacy heuristic: derive a point size from the caret line height.
        // ~0.72 of line height approximates cap/point size for system fonts.
        if let caretRect, caretRect.height > 8, caretRect.height < 64 {
            return NSFont.systemFont(ofSize: (caretRect.height * 0.72).rounded(), weight: .regular)
        }
        return NSFont.systemFont(ofSize: 13, weight: .regular)
    }

    /// Baseline-aligned frame for the ghost text panel (B2).
    ///
    /// The caret rect spans the line box (top = `maxY`, bottom = `minY` in
    /// AppKit's flipped-from-AX, bottom-left-origin screen space as used by the
    /// renderer). To make the ghost text sit on the *same baseline* as the
    /// glyphs the user is typing, we anchor the text field so that, after the
    /// label's own internal text inset, the glyph baseline lands at
    /// `caret.bottom + descender`.
    ///
    /// We model the label as drawing its text with the baseline at
    /// `frame.minY + descender_magnitude` (an `NSTextField` label draws its
    /// single line bottom-aligned, so the baseline sits `|descender|` above the
    /// frame bottom). To put the baseline at the line's baseline
    /// (`caret.minY - font.descender`, since `descender` is negative), we set
    /// the frame bottom to `caret.minY`. The panel height is the font line
    /// height so the glyph cap fits.
    ///
    /// - Parameters:
    ///   - caretRect: caret/selection rect in screen coords (bottom-left origin).
    ///   - font: the resolved ghost font.
    ///   - measuredSize: the measured size of the ghost string in `font`.
    /// - Returns: the unclamped target frame (caller clamps to the screen).
    static func ghostFrame(caretRect: CGRect, font: NSFont, measuredSize: CGSize) -> NSRect {
        let width = max(measuredSize.width + 4, 1)
        // Use the font's natural line height so ascenders/descenders are not
        // clipped; never smaller than the measured glyph height.
        let lineHeight = max(font.ascender - font.descender, measuredSize.height)
        let height = max(lineHeight.rounded(.up), 14)

        // Horizontal: start just past the caret so the ghost continues the line.
        let originX = caretRect.maxX + 1

        // Vertical: align the ghost baseline to the line baseline. The caret rect
        // bottom (minY) is the line bottom; the field's text baseline sits
        // |descender| above its frame bottom, and a glyph baseline sits
        // |descender| above the line bottom — so the frame bottom equals the
        // line bottom (caret.minY). Center any extra panel height around the
        // line so the visual line stays put.
        let lineBoxHeight = caretRect.height > 0 ? caretRect.height : lineHeight
        let verticalSlack = (height - lineBoxHeight) / 2
        let originY = caretRect.minY - verticalSlack

        return NSRect(x: originX, y: originY, width: width, height: height)
    }
}
