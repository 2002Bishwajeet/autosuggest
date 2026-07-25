import SwiftUI

/// System-permission status row: icon tile + title + status badge + action(s).
/// Canonical replacement for `PermissionSettingsRow` (single action) and
/// `PermissionDetailRow` (two actions).
struct PermissionRow: View {
    let systemImage: String
    let title: String
    let description: String
    let granted: Bool
    let primary: (label: String, action: () -> Void)
    let secondary: (label: String, action: () -> Void)?

    @ScaledMetric(relativeTo: .headline) private var tileSize: CGFloat = 40

    init(
        systemImage: String,
        title: String,
        description: String,
        granted: Bool,
        primary: (label: String, action: () -> Void),
        secondary: (label: String, action: () -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.description = description
        self.granted = granted
        self.primary = primary
        self.secondary = secondary
    }

    private var accent: Color {
        granted ? AutoSuggestTheme.success : AutoSuggestTheme.warning
    }

    var body: some View {
        HStack(alignment: .top, spacing: AutoSuggestTheme.spacingMD) {
            ZStack {
                RoundedRectangle(cornerRadius: AutoSuggestTheme.radiusSmall, style: .continuous)
                    .fill(accent.opacity(AutoSuggestTheme.badgeFillOpacity))
                    .frame(width: tileSize, height: tileSize)
                Image(systemName: granted ? "checkmark.shield.fill" : systemImage)
                    .font(.headline)
                    .foregroundStyle(accent)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AutoSuggestTheme.spacingXS) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    StatusBadge(granted ? "Granted" : "Required", style: granted ? .granted : .required)
                }
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !granted {
                    HStack(spacing: AutoSuggestTheme.spacingSM) {
                        Button(primary.label, action: primary.action)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        if let secondary {
                            Button(secondary.label, action: secondary.action)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                    .padding(.top, AutoSuggestTheme.spacingXS)
                }
            }
        }
        .padding(AutoSuggestTheme.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: AutoSuggestTheme.radiusMedium, style: .continuous)
                .fill(AutoSuggestTheme.surfaceSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: AutoSuggestTheme.radiusMedium, style: .continuous)
                        .stroke(granted ? AutoSuggestTheme.success.opacity(0.2) : AutoSuggestTheme.border, lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(granted ? "Granted" : "Required"). \(description)")
    }
}
