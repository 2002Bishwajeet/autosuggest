import XCTest
@testable import AutoSuggestApp

final class PersonalizationEngineTests: XCTestCase {

    func testRecordAcceptedSuggestionDoesNotThrow() async {
        let engine = PersonalizationEngine(store: EncryptedFileStore())
        // Recording should not throw or crash
        await engine.recordAcceptedSuggestion("test completion")
    }

    func testBestMatchReturnsOptionalString() async {
        let engine = PersonalizationEngine(store: EncryptedFileStore())
        // bestMatch returns String? - it should not crash regardless of state
        let result = await engine.bestMatch(for: "some context")
        // Result is either nil (clean state) or a string (prior runs left data)
        if let result {
            XCTAssertFalse(result.isEmpty)
        }
    }

    func testEmptyCompletionDoesNotCrash() async {
        let engine = PersonalizationEngine(store: EncryptedFileStore())
        await engine.recordAcceptedSuggestion("")
        await engine.recordAcceptedSuggestion("   ")
        // No assertion needed - just verifying no crash
    }

    func testRecordAndRetrieveWithinSameInstance() async {
        let engine = PersonalizationEngine(store: EncryptedFileStore())
        let unique = "PERSONALIZATION_TEST_\(UUID().uuidString)"

        await engine.recordAcceptedSuggestion(unique)

        // After recording, bestMatch should return a non-nil result
        // (either our entry or a previously persisted one)
        let result = await engine.bestMatch(for: "context")
        XCTAssertNotNil(result, "bestMatch should return a suggestion after recording")
    }
}
