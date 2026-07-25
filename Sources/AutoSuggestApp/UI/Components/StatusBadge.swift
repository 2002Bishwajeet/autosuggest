import SwiftUI

/// Small capsule status label (e.g. "Granted" / "Required"). One definition
/// replacing the divergent inline capsules that used 0.12 / 0.14 / 0.16 fills.
struct StatusBadge: View {
    enum Style {
        case granted, required, neutral
    }

    let text: String
    let style: Style

    init(_ text: String, style: Style) {
        self.text = text
        self.style = style
    }

    static func tint(for style: Style) -> Color {
        switch style {
        case .granted: AutoSuggestTheme.success
        case .required: AutoSuggestTheme.warning
        case .neutral: AutoSuggestTheme.textSecondary
        }
    }

    var body: some View {
        let color = StatusBadge.tint(for: style)
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, AutoSuggestTheme.spacingSM)
            .padding(.vertical, AutoSuggestTheme.spacingXS)
            .background(Capsule().fill(color.opacity(AutoSuggestTheme.badgeFillOpacity)))
            .foregroundStyle(color)
    }
}
