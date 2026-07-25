import XCTest
@testable import AutoSuggestApp

final class ExclusionRuleCodableTests: XCTestCase {
    func testEncodedJSONHasNoIdKey() throws {
        let rule = ExclusionRule(enabled: true, bundleID: "com.x", windowTitleContains: nil, contentPattern: nil)
        let data = try JSONEncoder().encode(rule)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("\"id\""), "id must not be persisted: \(json)")
    }

    func testRoundTripPreservesStoredFields() throws {
        let rule = ExclusionRule(enabled: false, bundleID: "com.a", windowTitleContains: "win", contentPattern: "re")
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(ExclusionRule.self, from: data)
        XCTAssertEqual(decoded, rule) // Equatable ignores id (see note in impl)
        XCTAssertEqual(decoded.enabled, false)
        XCTAssertEqual(decoded.bundleID, "com.a")
        XCTAssertEqual(decoded.windowTitleContains, "win")
        XCTAssertEqual(decoded.contentPattern, "re")
    }

    func testDistinctInstancesHaveDistinctIds() {
        let a = ExclusionRule(enabled: true, bundleID: "com.x", windowTitleContains: nil, contentPattern: nil)
        let b = ExclusionRule(enabled: true, bundleID: "com.x", windowTitleContains: nil, contentPattern: nil)
        XCTAssertNotEqual(a.id, b.id)
    }
}
