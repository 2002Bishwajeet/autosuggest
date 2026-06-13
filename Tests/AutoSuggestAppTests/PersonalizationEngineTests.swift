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

    // MARK: - stats(), clearAll(), setEnabled()

    func testStatsReflectsRecordedCompletions() async {
        let engine = PersonalizationEngine(store: EncryptedFileStore())
        // Clear first so we start from a known state
        await engine.clearAll()

        await engine.recordAcceptedSuggestion("alpha")
        await engine.recordAcceptedSuggestion("beta")
        await engine.recordAcceptedSuggestion("alpha") // duplicate → count = 2

        let stats = await engine.stats()
        XCTAssertEqual(stats.uniqueCount, 2, "Should have 2 unique completions")
        XCTAssertEqual(stats.totalAcceptances, 3, "Should have 3 total acceptances")
    }

    func testClearAllEmptiesStore() async {
        let engine = PersonalizationEngine(store: EncryptedFileStore())
        await engine.recordAcceptedSuggestion("something")

        await engine.clearAll()

        let stats = await engine.stats()
        XCTAssertEqual(stats.uniqueCount, 0, "clearAll should remove all completions")
        XCTAssertEqual(stats.totalAcceptances, 0, "clearAll should zero totals")
    }

    func testSetEnabledFalseBlocksRecord() async {
        let engine = PersonalizationEngine(store: EncryptedFileStore())
        await engine.clearAll()

        await engine.setEnabled(false)
        await engine.recordAcceptedSuggestion("should not be recorded")

        let stats = await engine.stats()
        XCTAssertEqual(stats.uniqueCount, 0, "record should be a no-op when disabled")
    }

    func testSetEnabledFalseMakesBestMatchReturnNil() async {
        let engine = PersonalizationEngine(store: EncryptedFileStore())
        await engine.clearAll()
        await engine.setEnabled(true)
        await engine.recordAcceptedSuggestion("hello world")

        await engine.setEnabled(false)
        let result = await engine.bestMatch(for: "hello")
        XCTAssertNil(result, "bestMatch should return nil when disabled")
    }

    func testSetEnabledTrueRestoresRecordBehavior() async {
        let engine = PersonalizationEngine(store: EncryptedFileStore())
        await engine.clearAll()

        await engine.setEnabled(false)
        await engine.recordAcceptedSuggestion("ignored")
        await engine.setEnabled(true)
        await engine.recordAcceptedSuggestion("recorded")

        let stats = await engine.stats()
        XCTAssertEqual(stats.uniqueCount, 1, "Only entry recorded while enabled should be present")
        XCTAssertEqual(stats.totalAcceptances, 1)
    }
}
