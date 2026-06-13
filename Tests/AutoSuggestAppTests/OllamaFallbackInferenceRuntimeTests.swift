import Foundation
import XCTest
@testable import AutoSuggestApp

/// Unit tests for the pure error-mapping helpers on `OllamaFallbackInferenceRuntime`.
/// These exercise the "Ollama isn't running" vs "model not installed" vs
/// "generic provider error" branches without needing a live daemon — the exact
/// distinctions that used to collapse into a misleading shared failure.
final class OllamaFallbackInferenceRuntimeTests: XCTestCase {
    // MARK: - Not-reachable detection

    func testRefusedConnectionIsTreatedAsNotReachable() {
        XCTAssertTrue(OllamaFallbackInferenceRuntime.isNotReachable(URLError(.cannotConnectToHost)))
    }

    func testTimeoutIsTreatedAsNotReachable() {
        // A hung/stale daemon surfaces as a timeout, not a refused connection —
        // it must still map to the friendly "Ollama isn't running" message.
        XCTAssertTrue(OllamaFallbackInferenceRuntime.isNotReachable(URLError(.timedOut)))
    }

    func testWrongHostIsTreatedAsNotReachable() {
        XCTAssertTrue(OllamaFallbackInferenceRuntime.isNotReachable(URLError(.cannotFindHost)))
        XCTAssertTrue(OllamaFallbackInferenceRuntime.isNotReachable(URLError(.dnsLookupFailed)))
    }

    func testNonConnectivityErrorIsNotTreatedAsNotReachable() {
        // A malformed-server-response is NOT "Ollama isn't running" — it must not
        // be swallowed by the not-reachable branch.
        XCTAssertFalse(OllamaFallbackInferenceRuntime.isNotReachable(URLError(.badServerResponse)))
        XCTAssertFalse(OllamaFallbackInferenceRuntime.isNotReachable(URLError(.cancelled)))
    }

    // MARK: - Error-response mapping

    func testModelNotFoundBodyMapsToModelNotInstalled() {
        let body = Data(#"{"error":"model \"qwen2.5-coder:1.5b\" not found, try pulling it first"}"#.utf8)
        let mapped = OllamaFallbackInferenceRuntime.mapErrorResponse(
            statusCode: 404,
            body: body,
            model: "qwen2.5-coder:1.5b"
        )
        guard case let .ollamaModelNotInstalled(model) = mapped else {
            return XCTFail("Expected .ollamaModelNotInstalled, got \(mapped)")
        }
        XCTAssertEqual(model, "qwen2.5-coder:1.5b")
    }

    func test404WithoutBodyStillMapsToModelNotInstalled() {
        let mapped = OllamaFallbackInferenceRuntime.mapErrorResponse(
            statusCode: 404,
            body: Data(),
            model: "gemma3:1b"
        )
        guard case let .ollamaModelNotInstalled(model) = mapped else {
            return XCTFail("Expected .ollamaModelNotInstalled, got \(mapped)")
        }
        XCTAssertEqual(model, "gemma3:1b")
    }

    func testGenericServerErrorMapsToProviderError() {
        let body = Data(#"{"error":"something exploded"}"#.utf8)
        let mapped = OllamaFallbackInferenceRuntime.mapErrorResponse(
            statusCode: 500,
            body: body,
            model: "qwen2.5-coder:1.5b"
        )
        guard case let .providerError(statusCode, message) = mapped else {
            return XCTFail("Expected .providerError, got \(mapped)")
        }
        XCTAssertEqual(statusCode, 500)
        XCTAssertEqual(message, "something exploded")
    }

    // MARK: - Messaging is distinct and accurate

    func testNotReachableAndModelMissingHaveDistinctMessages() {
        let notReachable = InferenceError.ollamaNotReachable.errorDescription ?? ""
        let modelMissing = InferenceError.ollamaModelNotInstalled(model: "qwen2.5-coder:1.5b")
            .errorDescription ?? ""

        XCTAssertTrue(notReachable.lowercased().contains("ollama serve"))
        XCTAssertTrue(modelMissing.lowercased().contains("ollama pull"))
        XCTAssertNotEqual(notReachable, modelMissing)
        // Neither must read like an opaque -1011/setup error.
        XCTAssertFalse(notReachable.contains("-1011"))
        XCTAssertFalse(modelMissing.contains("-1011"))
    }
}
