import AppKit
import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var uiModel: AutoSuggestUIModel

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(SettingsRoute.allCases) { route in
                        SettingsSidebarRow(
                            route: route,
                            isSelected: route == uiModel.selectedSettingsRoute
                        ) {
                            uiModel.selectedSettingsRoute = route
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(16)
            .frame(width: 230, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let banner = uiModel.banner {
                        BannerView(banner: banner, onDismiss: uiModel.dismissBanner)
                    }
                    SettingsDetailContent(route: uiModel.selectedSettingsRoute, uiModel: uiModel)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// A single navigation row in the Settings sidebar. Selection follows the
/// user's system accent color (HIG Rule 9.3) and the row carries the selected
/// accessibility trait and a hover affordance.
private struct SettingsSidebarRow: View {
    let route: SettingsRoute
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: route.systemImage)
                    .foregroundStyle(isSelected ? Color.white : Color.secondary)
                    .frame(width: 18)
                Text(route.title)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(rowBackground)
            .contentShape(RoundedRectangle(cornerRadius: AutoSuggestTheme.radiusSmall, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var rowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: AutoSuggestTheme.radiusSmall, style: .continuous)
        if isSelected {
            shape.fill(Color.accentColor)
        } else if isHovered {
            shape.fill(Color.primary.opacity(0.06))
        } else {
            shape.fill(Color.clear)
        }
    }
}

private struct SettingsDetailContent: View {
    let route: SettingsRoute
    @ObservedObject var uiModel: AutoSuggestUIModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(route.title)
                .font(.title2.weight(.semibold))

            switch route {
            case .general:
                GeneralSettingsView(uiModel: uiModel)
            case .models:
                ModelsSettingsView(uiModel: uiModel)
            case .onlineLLM:
                OnlineLLMSettingsView(uiModel: uiModel)
            case .permissionsPrivacy:
                PermissionsSettingsView(uiModel: uiModel)
            case .exclusions:
                ExclusionsSettingsView(uiModel: uiModel)
            case .accessibility:
                AccessibilitySettingsView(uiModel: uiModel)
            case .diagnostics:
                DiagnosticsSettingsView(uiModel: uiModel)
            }
        }
    }
}
