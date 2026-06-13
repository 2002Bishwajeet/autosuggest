import AppKit
import SwiftUI

// MARK: - Theme Colors

enum AutoSuggestTheme {
    static let accent = Color.accentColor

    /// Lantern-amber brand accent (#E3A411), brightened in dark mode (#F0B43C)
    /// to match the design system. Used for brand accent moments; surfaces and
    /// most controls keep system colors to respect the user's system accent.
    static let brand = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0xF0 / 255.0, green: 0xB4 / 255.0, blue: 0x3C / 255.0, alpha: 1)
            : NSColor(srgbRed: 0xE3 / 255.0, green: 0xA4 / 255.0, blue: 0x11 / 255.0, alpha: 1)
    })

    static let surfacePrimary = Color(nsColor: .windowBackgroundColor)
    static let surfaceSecondary = Color(nsColor: .controlBackgroundColor)
    static let surfaceElevated = Color(nsColor: .underPageBackgroundColor)

    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)

    static let border = Color(nsColor: .separatorColor)

    /// Semantic status colors. These map to SwiftUI's adaptive colors, which
    /// already vary across Light/Dark and respond to Increase Contrast, so they
    /// stay legible in every appearance.
    static let success = Color.green
    static let warning = Color.orange
    static let error = Color.red
    static let info = Color.blue

    /// Selection / interactive accent. Follows the user's system accent color
    /// rather than a fixed brand hue, per the HIG (Rule 9.3). Use `brand` only
    /// for deliberate brand moments (the menu-bar glyph, the About links).
    static let accentInteractive = Color.accentColor

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
