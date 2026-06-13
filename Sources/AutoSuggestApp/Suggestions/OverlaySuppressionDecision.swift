import Foundation

/// Pure decision for whether to suppress our own inline ghost-text overlay
/// (Layer B / B5 — "double-ghost suppression").
///
/// Two inputs, both already resolved by the caller:
///   - `nativeCompletionPresent`: best-effort AX read found Apple's own inline
///     prediction already showing on the focused element (PRIMARY signal).
///   - `excludedApp`: the focused app is on the double-ghost backstop list
///     (BACKSTOP — for apps where AX detection is unreliable but native
///     predictions are known to be on).
///
/// Kept as a free function with no side effects so it is trivially unit-tested
/// without AX, a renderer, or a running app.
enum OverlaySuppressionDecision {
    /// `true` when our overlay should be suppressed to avoid two stacked ghosts.
    static func shouldSuppressOverlay(
        nativeCompletionPresent: Bool,
        excludedApp: Bool
    ) -> Bool {
        nativeCompletionPresent || excludedApp
    }

    /// Bundle IDs where Apple's native inline predictions are reliably on and
    /// our AX detection is least reliable, so we suppress unconditionally as a
    /// backstop. Intentionally tiny and conservative; the per-app exclusions
    /// UI remains the user-facing escape hatch for everything else.
    static let nativePredictionBackstopBundleIDs: Set<String> = [
        // Notes drives Apple inline predictions aggressively in its TextKit2
        // editor where our AX completion-marker read is least dependable.
        "com.apple.Notes",
    ]

    /// Whether the given bundle ID is on the native-prediction backstop list.
    static func isBackstopApp(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return nativePredictionBackstopBundleIDs.contains(bundleID)
    }
}
