import AppKit
import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var uiModel: AutoSuggestUIModel

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(SettingsRoute.allCases) { route in
                        Button {
                            uiModel.selectedSettingsRoute = route
                        } label: {
                            let isSelected = route == uiModel.selectedSettingsRoute
                            HStack(spacing: 10) {
                                Image(systemName: route.systemImage)
                                    .foregroundStyle(isSelected ? AutoSuggestTheme.brand : Color.secondary)
                                    .frame(width: 18)
                                Text(route.title)
                                    .foregroundStyle(Color.primary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(isSelected ? AutoSuggestTheme.brand.opacity(0.16) : Color.clear)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
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
