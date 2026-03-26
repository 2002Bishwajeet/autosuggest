import AppKit
import SwiftUI

// MARK: - Theme Colors

enum AutoSuggestTheme {
    static let accent = Color.accentColor

    static let surfacePrimary = Color(nsColor: .windowBackgroundColor)
    static let surfaceSecondary = Color(nsColor: .controlBackgroundColor)
    static let surfaceElevated = Color(nsColor: .underPageBackgroundColor)

    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)

    static let border = Color(nsColor: .separatorColor)

    static let success = Color.green
    static let warning = Color.orange
    static let error = Color.red

    // MARK: - Spacing

    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 12
    static let spacingLG: CGFloat = 16
    static let spacingXL: CGFloat = 24
    static let spacingXXL: CGFloat = 32

    // MARK: - Corner Radius

    static let radiusSmall: CGFloat = 8
    static let radiusMedium: CGFloat = 12
    static let radiusLarge: CGFloat = 16
}

// MARK: - Status Indicator

struct StatusDot: View {
    enum Status {
        case active, paused, error, inactive
    }

    let status: Status

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        switch status {
        case .active: AutoSuggestTheme.success
        case .paused: AutoSuggestTheme.warning
        case .error: AutoSuggestTheme.error
        case .inactive: AutoSuggestTheme.textTertiary
        }
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    let systemImage: String?

    init(_ title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        if let systemImage {
            Label(title, systemImage: systemImage)
                .font(.headline)
        } else {
            Text(title)
                .font(.headline)
        }
    }
}
