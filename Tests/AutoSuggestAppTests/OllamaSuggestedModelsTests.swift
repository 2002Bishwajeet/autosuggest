import XCTest
@testable import AutoSuggestApp

final class OllamaSuggestedModelsTests: XCTestCase {
    func testListLeadsWithSmallestQwen3AndIsWellFormed() {
        let all = OllamaSuggestedModels.all
        XCTAssertEqual(all.first?.name, "qwen3:0.6b")
        for m in all {
            XCTAssertTrue(m.name.contains(":"), "tag must be repo:tag — \(m.name)")
            XCTAssertFalse(m.blurb.isEmpty)
            XCTAssertGreaterThan(m.sizeGB, 0)
        }
    }
}
