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
        // Within a single actor instance, the in-memory cache is authoritative.
        // Record a unique high-frequency entry that should dominate.
        let engine = PersonalizationEngine(store: EncryptedFileStore())
        let unique = "PERSONALIZATION_TEST_\(UUID().uuidString)"

        // Record enough times to guarantee it outranks any stale data
        for _ in 0..<100 {
            await engine.recordAcceptedSuggestion(unique)
        }

        let result = await engine.bestMatch(for: "context")
        XCTAssertEqual(result, unique)
    }
}
