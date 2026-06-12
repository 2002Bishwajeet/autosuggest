import XCTest
@testable import AutoSuggestApp

final class OllamaSuggestedModelsTests: XCTestCase {
    func testListLeadsWithFastNonThinkingModelAndIsWellFormed() {
        let all = OllamaSuggestedModels.all
        XCTAssertEqual(all.first?.name, "qwen2.5-coder:1.5b")
        for m in all {
            XCTAssertTrue(m.name.contains(":"), "tag must be repo:tag — \(m.name)")
            XCTAssertFalse(m.blurb.isEmpty)
            XCTAssertGreaterThan(m.sizeGB, 0)
        }
    }
}
