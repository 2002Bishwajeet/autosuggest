import XCTest
@testable import AutoSuggestApp

final class TrainingDataExporterTests: XCTestCase {

    func testDisabledExporterDoesNotRecord() async {
        let exporter = TrainingDataExporter(enabled: false)
        await exporter.recordTrainingPair(prompt: "Hello", completion: " world")
        let count = await exporter.pairCount()
        XCTAssertEqual(count, 0, "Disabled exporter should not record anything")
    }

    func testTrainingPairCodable() throws {
        let pair = TrainingPair(
            prompt: "Hello",
            completion: " world",
            timestamp: Date()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(pair)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TrainingPair.self, from: data)
        XCTAssertEqual(decoded.prompt, "Hello")
        XCTAssertEqual(decoded.completion, " world")
    }

    func testTrainingDataErrorDescriptions() {
        let exportDisabled = TrainingDataError.exportDisabled
        XCTAssertNotNil(exportDisabled.errorDescription)
        XCTAssertTrue(exportDisabled.errorDescription!.contains("disabled"))

        let fileError = TrainingDataError.fileSystemError(
            underlying: NSError(domain: "test", code: 1, userInfo: nil)
        )
        XCTAssertNotNil(fileError.errorDescription)

        let encodingError = TrainingDataError.encodingError
        XCTAssertNotNil(encodingError.errorDescription)
    }
}
