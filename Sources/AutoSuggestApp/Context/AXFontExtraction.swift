import AppKit
import CoreText
import Foundation

/// Pure extraction of a field's font from an AX attributed string (Layer B / B1).
///
/// AX exposes the focused field's styled text via the `AXAttributedStringForRange`
/// parameterized attribute, returning a `CFAttributedString` (bridged to
/// `NSAttributedString`). The font lives under either the AppKit `.font`
/// (`NSFontAttributeName`) key or the Core Text `kCTFontAttributeName` key,
/// depending on the app. This helper normalizes both into an `NSFont` so the
/// overlay can match the real field font instead of guessing from caret height.
///
/// Pure and side-effect free: it takes an already-fetched attributed string, so
/// it is unit-testable with a mock without touching live AX.
enum AXFontExtraction {
    /// Reads the font attribute from the first character of `attributed`.
    ///
    /// - Returns: the field's `NSFont`, or `nil` when no font attribute is
    ///   present (caller falls back to the caret-height heuristic).
    static func font(from attributed: NSAttributedString) -> NSFont? {
        guard attributed.length > 0 else { return nil }
        let attrs = attributed.attributes(at: 0, effectiveRange: nil)

        // AppKit key: most native fields populate NSAttributedString.Key.font.
        if let nsFont = attrs[.font] as? NSFont {
            return nsFont
        }

        // Core Text key: some fields (and CFAttributedString producers) use
        // kCTFontAttributeName, whose value is a CTFont toll-free bridged to
        // NSFont/CTFontRef. NSAttributedString.Key(kCTFontAttributeName) is the
        // same string key.
        let ctFontKey = NSAttributedString.Key(kCTFontAttributeName as String)
        if let raw = attrs[ctFontKey] {
            // CTFont is toll-free bridged with NSFont; this cast succeeds when
            // the value is a CTFontRef.
            let cf = raw as CFTypeRef
            if CFGetTypeID(cf) == CTFontGetTypeID() {
                // Safe: type check guarantees the bridge.
                let ctFont = unsafeDowncast(cf, to: CTFont.self)
                return ctFont as NSFont
            }
            if let nsFont = raw as? NSFont {
                return nsFont
            }
        }

        return nil
    }
}
