import ApplicationServices
import Foundation

enum AXHelpers {
    static func castToAXUIElement(_ value: CFTypeRef) -> AXUIElement? {
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        // Safe: type check guarantees the cast succeeds
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    static func castToAXValue(_ value: CFTypeRef) -> AXValue? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        // Safe: type check guarantees the cast succeeds
        return unsafeBitCast(value, to: AXValue.self)
    }

    static func castToCFAttributedString(_ value: CFTypeRef) -> CFAttributedString? {
        guard CFGetTypeID(value) == CFAttributedStringGetTypeID() else { return nil }
        return unsafeBitCast(value, to: CFAttributedString.self)
    }
}
