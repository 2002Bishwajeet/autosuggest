import SwiftUI

/// Dot page control for the onboarding wizard: one dot per displayed step,
/// the current dot filled brand-amber and slightly enlarged. Pure view — the
/// caller supplies position; exposes a single accessibility element
/// ("Step N of M").
struct OnboardingStepIndicator: View {
    let total: Int
    let current: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Clamps `current` into `0..<total` (0 when `total` < 1) so a caller
    /// race (e.g. the dynamic step list shrinking) can never draw out of range.
    static func clampedIndex(_ current: Int, total: Int) -> Int {
        guard total > 0 else { return 0 }
        return min(max(current, 0), total - 1)
    }

    var body: some View {
        let active = Self.clampedIndex(current, total: total)
        HStack(spacing: AutoSuggestTheme.spacingSM) {
            ForEach(0 ..< max(total, 1), id: \.self) { index in
                Circle()
                    .fill(index == active ? AutoSuggestTheme.brand : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .scaleEffect(index == active && !reduceMotion ? 1.25 : 1.0)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: active)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(active + 1) of \(max(total, 1))")
    }
}
