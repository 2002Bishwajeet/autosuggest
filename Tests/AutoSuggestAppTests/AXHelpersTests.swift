import ApplicationServices
import XCTest

@testable import AutoSuggestApp

final class AXHelpersTests: XCTestCase {

    // MARK: - castToAXUIElement

    func testCastValidAXUIElement() {
        let element = AXUIElementCreateSystemWide()
        let result = AXHelpers.castToAXUIElement(element)
        XCTAssertNotNil(result)
    }

    func testCastInvalidAXUIElementReturnsNil() {
        let string = "hello" as CFString
        let result = AXHelpers.castToAXUIElement(string)
        XCTAssertNil(result)
    }

    // MARK: - castToAXValue

    func testCastValidAXValue() {
        var range = CFRange(location: 0, length: 5)
        guard let axValue = AXValueCreate(.cfRange, &range) else {
            XCTFail("Failed to create AXValue")
            return
        }
        let result = AXHelpers.castToAXValue(axValue)
        XCTAssertNotNil(result)
    }

    func testCastInvalidAXValueReturnsNil() {
        let string = "hello" as CFString
        let result = AXHelpers.castToAXValue(string)
        XCTAssertNil(result)
    }

    // MARK: - castToCFAttributedString

    func testCastValidCFAttributedString() {
        let attrString = CFAttributedStringCreate(
            kCFAllocatorDefault,
            "hello" as CFString,
            [:] as CFDictionary
        )!
        let result = AXHelpers.castToCFAttributedString(attrString)
        XCTAssertNotNil(result)
    }

    func testCastInvalidCFAttributedStringReturnsNil() {
        var intValue: Int32 = 42
        let number = CFNumberCreate(kCFAllocatorDefault, .sInt32Type, &intValue)!
        let result = AXHelpers.castToCFAttributedString(number)
        XCTAssertNil(result)
    }
}
