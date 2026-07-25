import SwiftUI

/// Titled grouped container for settings content. Canonical replacement for the
/// near-duplicate `SettingsCard` and `SimplePanel`.
struct SettingsSection<Content: View>: View {
    let title: String?
    let systemImage: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AutoSuggestTheme.spacingMD) {
            if let title {
                SectionHeader(title, systemImage: systemImage)
            }
            content
        }
        .padding(AutoSuggestTheme.spacingLG)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AutoSuggestTheme.radiusMedium, style: .continuous)
                .fill(AutoSuggestTheme.surfaceSecondary)
        )
    }
}
