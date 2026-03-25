import XCTest
@testable import AutoSuggestApp

final class PIIFilterTests: XCTestCase {
    func testSanitizeEmailAndPhone() {
        let filter = PIIFilter()
        let input = "Contact me at test@example.com or (415) 555-1234."
        let output = filter.sanitize(input)
        XCTAssertFalse(output.contains("test@example.com"))
        XCTAssertFalse(output.contains("555-1234"))
        XCTAssertTrue(output.contains("<email>"))
        XCTAssertTrue(output.contains("<phone>"))
    }
}
