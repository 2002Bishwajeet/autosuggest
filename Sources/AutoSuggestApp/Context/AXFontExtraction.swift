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
    // Spelled out rather than using kAXFontTextAttribute / kAXFontSizeKey / etc:
    // those bridge into Swift as non-Sendable `Unmanaged<CFString>` vars. The
    // literals are the documented, stable values of the same constants.
    private static let axFontAttributeKey = "AXFont"
    private static let axFontNameKey = "AXFontName"
    private static let axFontFamilyKey = "AXFontFamily"
    private static let axFontSizeKey = "AXFontSize"

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
        // AX's own representation (`kAXFontTextAttribute`), and the only one real
        // apps actually return: a *dictionary* of name/family/size rather than a
        // font object. TextEdit, Safari, Brave and Firefox all use this and populate
        // neither key above — see docs/AX_COMPAT_MATRIX.md. Checked before the Core
        // Text key because it is the common case, not the fallback.
        if let axFont = attrs[NSAttributedString.Key(axFontAttributeKey)] as? [String: Any],
           let font = font(fromAXFontDictionary: axFont) {
            return font
        }

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

    /// Rebuilds an `NSFont` from AX's font dictionary
    /// (`AXFontName` / `AXFontFamily` / `AXFontSize`).
    ///
    /// Size is required: the overlay wants the font for line metrics, so a font at
    /// an invented size is worse than nil (nil sends the caller to the caret-height
    /// heuristic, which at least derives from the real field).
    private static func font(fromAXFontDictionary dict: [String: Any]) -> NSFont? {
        guard let size = (dict[axFontSizeKey] as? NSNumber)?.doubleValue, size > 0 else {
            return nil
        }
        // AXFontName is a PostScript name ("Menlo-Regular"); AXFontFamily is the
        // display family ("Menlo"). Either can resolve, and neither is guaranteed
        // installed on this machine.
        for key in [axFontNameKey, axFontFamilyKey] {
            if let name = dict[key] as? String, let font = NSFont(name: name, size: size) {
                return font
            }
        }
        // Face unresolvable, but the size is real and that is what metrics need.
        return .systemFont(ofSize: size)
    }
}
