import XCTest
@testable import AutoSuggestApp

final class OllamaModelServiceTests: XCTestCase {
    func testParseTagsExtractsNameAndSize() throws {
        let json = #"{"models":[{"name":"qwen3:1.7b","size":1359290880},{"name":"llama3.2:1b","size":1300000000}]}"#
        let models = try OllamaModelService.parseTags(Data(json.utf8))
        XCTAssertEqual(models, [
            .init(name: "qwen3:1.7b", sizeBytes: 1_359_290_880),
            .init(name: "llama3.2:1b", sizeBytes: 1_300_000_000),
        ])
    }

    func testParseTagsEmpty() throws {
        let models = try OllamaModelService.parseTags(Data(#"{"models":[]}"#.utf8))
        XCTAssertTrue(models.isEmpty)
    }

    func testParsePullLineProgress() throws {
        let line = Data(#"{"status":"downloading","total":100,"completed":40}"#.utf8)
        let p = OllamaModelService.parsePullLine(line)
        XCTAssertEqual(p?.completed, 40)
        XCTAssertEqual(p?.total, 100)
        XCTAssertEqual(try XCTUnwrap(p).fraction, 0.4, accuracy: 0.0001)
    }

    func testParsePullLineSuccessHasZeroProgress() {
        let p = OllamaModelService.parsePullLine(Data(#"{"status":"success"}"#.utf8))
        XCTAssertEqual(p?.status, "success")
        XCTAssertEqual(p?.fraction, 0)
    }

    func testParsePullLineGarbageReturnsNil() {
        XCTAssertNil(OllamaModelService.parsePullLine(Data("not json".utf8)))
    }
}
