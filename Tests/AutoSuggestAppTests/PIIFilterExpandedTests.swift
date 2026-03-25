import XCTest
@testable import AutoSuggestApp

final class PIIFilterExpandedTests: XCTestCase {
    private var filter: PIIFilter!

    override func setUp() {
        super.setUp()
        filter = PIIFilter()
    }

    override func tearDown() {
        filter = nil
        super.tearDown()
    }

    func testSanitizesEmail() {
        let output = filter.sanitize("contact john@example.com please")
        XCTAssertEqual(output, "contact <email> please")
    }

    func testSanitizesMultipleEmails() {
        let input = "Send to alice@test.com and bob@domain.org for review."
        let output = filter.sanitize(input)
        XCTAssertFalse(output.contains("alice@test.com"))
        XCTAssertFalse(output.contains("bob@domain.org"))
        XCTAssertEqual(output.components(separatedBy: "<email>").count - 1, 2,
                        "Expected exactly two <email> replacements")
    }

    func testSanitizesUSPhoneNumber() {
        let output = filter.sanitize("call 555-123-4567 now")
        XCTAssertTrue(output.contains("<phone>"), "Phone number should be sanitized, got: \(output)")
        XCTAssertFalse(output.contains("555-123-4567"))
    }

    func testSanitizesPhoneWithCountryCode() {
        let output = filter.sanitize("call 1-555-123-4567 now")
        XCTAssertTrue(output.contains("<phone>"), "Phone with country code should be sanitized, got: \(output)")
        XCTAssertFalse(output.contains("555-123-4567"))
    }

    func testSanitizesCreditCardNumber() {
        let output = filter.sanitize("card: 4111 1111 1111 1111")
        XCTAssertEqual(output, "card: <card>")
    }

    func testSanitizesAllPIITypes() {
        let input = "Email jane@corp.com, call (800) 555-0199, card 4111 1111 1111 1111."
        let output = filter.sanitize(input)
        XCTAssertTrue(output.contains("<email>"))
        XCTAssertTrue(output.contains("<phone>"))
        XCTAssertTrue(output.contains("<card>"))
        XCTAssertFalse(output.contains("jane@corp.com"))
        XCTAssertFalse(output.contains("555-0199"))
        XCTAssertFalse(output.contains("4111"))
    }

    func testPreservesCleanText() {
        let input = "Hello world, how are you?"
        let output = filter.sanitize(input)
        XCTAssertEqual(output, input)
    }

    func testHandlesEmptyString() {
        let output = filter.sanitize("")
        XCTAssertEqual(output, "")
    }

    func testPreservesNonPIINumbers() {
        let input = "I have 42 apples"
        let output = filter.sanitize(input)
        XCTAssertEqual(output, input)
    }
}
