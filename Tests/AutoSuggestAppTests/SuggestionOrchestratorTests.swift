import XCTest
@testable import AutoSuggestApp

@MainActor
final class SuggestionOrchestratorTests: XCTestCase {

    // MARK: - Test Helpers

    private func makeOrchestrator(runtimes: [InferenceRuntime]) -> SuggestionOrchestrator {
        let policy = PolicyEngine(defaults: .default, userRules: [])
        let inference = InferenceEngine(runtimes: runtimes)
        return SuggestionOrchestrator(policyEngine: policy, inferenceEngine: inference)
    }

    private var normalPolicyContext: PolicyContext {
        PolicyContext(
            bundleID: "com.apple.Notes",
            axRole: "AXTextField",
            isSecureField: false,
            windowTitle: "Notes",
            textPrefix: "Hello "
        )
    }

    private var securePolicyContext: PolicyContext {
        PolicyContext(
            bundleID: "com.apple.Notes",
            axRole: "AXTextField",
            isSecureField: true,
            windowTitle: "Notes",
            textPrefix: "Hello "
        )
    }

    // MARK: - Tests

    func testScheduleSuggestionCallsOnSuggestion() {
        let exp = XCTestExpectation(description: "onSuggestion called")
        let orchestrator = makeOrchestrator(runtimes: [
            TestRuntime(name: "test", available: true, result: "world")
        ])

        var receivedCandidate: SuggestionCandidate?
        orchestrator.onSuggestion = { candidate in
            receivedCandidate = candidate
            exp.fulfill()
        }

        orchestrator.scheduleSuggestion(context: "Hello ", policyContext: normalPolicyContext)

        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(receivedCandidate?.completion, "world")
    }

    func testPolicyRejectionClearsSuggestion() {
        let exp = XCTestExpectation(description: "onClearSuggestion called")
        let orchestrator = makeOrchestrator(runtimes: [
            TestRuntime(name: "test", available: true, result: "world")
        ])

        orchestrator.onClearSuggestion = {
            exp.fulfill()
        }
        orchestrator.onSuggestion = { _ in
            XCTFail("onSuggestion should not be called for a secure field")
        }

        orchestrator.scheduleSuggestion(context: "Hello ", policyContext: securePolicyContext)

        wait(for: [exp], timeout: 1.0)
    }

    func testEmptyInferenceClearsSuggestion() {
        let exp = XCTestExpectation(description: "onClearSuggestion called for empty inference")
        let orchestrator = makeOrchestrator(runtimes: [
            TestRuntime(name: "test", available: true, result: "")
        ])

        orchestrator.onClearSuggestion = {
            exp.fulfill()
        }
        orchestrator.onSuggestion = { _ in
            XCTFail("onSuggestion should not be called for empty inference")
        }

        orchestrator.scheduleSuggestion(context: "Hello ", policyContext: normalPolicyContext)

        wait(for: [exp], timeout: 1.0)
    }

    func testClearSuggestionCancelsPending() {
        let suggestionExp = XCTestExpectation(description: "onSuggestion should not be called")
        suggestionExp.isInverted = true

        let orchestrator = makeOrchestrator(runtimes: [
            TestRuntime(name: "test", available: true, result: "world")
        ])

        orchestrator.onSuggestion = { _ in
            suggestionExp.fulfill()
        }

        orchestrator.scheduleSuggestion(context: "Hello ", policyContext: normalPolicyContext)
        orchestrator.clearSuggestion()

        wait(for: [suggestionExp], timeout: 1.0)
    }

    func testErrorCallsOnError() {
        let errorExp = XCTestExpectation(description: "onError called")
        let clearExp = XCTestExpectation(description: "onClearSuggestion called on error")

        let orchestrator = makeOrchestrator(runtimes: [
            ThrowingRuntime(name: "broken")
        ])

        orchestrator.onError = {
            errorExp.fulfill()
        }
        orchestrator.onClearSuggestion = {
            clearExp.fulfill()
        }

        orchestrator.scheduleSuggestion(context: "Hello ", policyContext: normalPolicyContext)

        wait(for: [errorExp, clearExp], timeout: 1.0)
    }
}

// MARK: - Test Mocks

private struct TestRuntime: InferenceRuntime {
    let name: String
    let available: Bool
    let result: String

    func isAvailable() -> Bool { available }

    func generateSuggestion(context: String) async throws -> Suggestion {
        Suggestion(completion: result, confidence: 0.5)
    }
}

private struct ThrowingRuntime: InferenceRuntime {
    let name: String

    func isAvailable() -> Bool { true }

    func generateSuggestion(context: String) async throws -> Suggestion {
        throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Simulated failure"])
    }
}
