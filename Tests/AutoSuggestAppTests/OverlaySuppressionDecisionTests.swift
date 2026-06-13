import XCTest
@testable import AutoSuggestApp

/// B5 — double-ghost suppression decision (pure function).
/// Suppress our overlay when Apple's native inline prediction is already showing
/// (PRIMARY: AX-detected) or when the focused app is on the backstop list.
final class OverlaySuppressionDecisionTests: XCTestCase {
    func testSuppressWhenNativeCompletionPresent() {
        XCTAssertTrue(
            OverlaySuppressionDecision.shouldSuppressOverlay(
                nativeCompletionPresent: true,
                excludedApp: false
            )
        )
    }

    func testSuppressWhenExcludedApp() {
        XCTAssertTrue(
            OverlaySuppressionDecision.shouldSuppressOverlay(
                nativeCompletionPresent: false,
                excludedApp: true
            )
        )
    }

    func testSuppressWhenBoth() {
        XCTAssertTrue(
            OverlaySuppressionDecision.shouldSuppressOverlay(
                nativeCompletionPresent: true,
                excludedApp: true
            )
        )
    }

    func testDoNotSuppressWhenNeither() {
        XCTAssertFalse(
            OverlaySuppressionDecision.shouldSuppressOverlay(
                nativeCompletionPresent: false,
                excludedApp: false
            )
        )
    }

    // MARK: - Backstop list

    func testIsBackstopAppRecognizesListedBundle() {
        XCTAssertTrue(OverlaySuppressionDecision.isBackstopApp(bundleID: "com.apple.Notes"))
    }

    func testIsBackstopAppRejectsUnlistedBundle() {
        XCTAssertFalse(OverlaySuppressionDecision.isBackstopApp(bundleID: "com.test.app"))
    }

    func testIsBackstopAppNilBundleIsFalse() {
        XCTAssertFalse(OverlaySuppressionDecision.isBackstopApp(bundleID: nil))
    }
}
