import AppKit
import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var uiModel: AutoSuggestUIModel

    var body: some View {
        NavigationSplitView {
            List(SettingsRoute.allCases, selection: Binding(
                get: { uiModel.selectedSettingsRoute },
                set: { if let route = $0 { uiModel.selectedSettingsRoute = route } }
            )) { route in
                Label(route.title, systemImage: route.systemImage)
                    .tag(route)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
            .listStyle(.sidebar)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: AutoSuggestTheme.spacingLG) {
                    if let banner = uiModel.banner {
                        BannerView(banner: banner, onDismiss: uiModel.dismissBanner)
                            .padding(.horizontal, AutoSuggestTheme.spacingLG)
                            .padding(.top, AutoSuggestTheme.spacingLG)
                    }
                    SettingsDetailContent(route: uiModel.selectedSettingsRoute, uiModel: uiModel)
                }
            }
            .navigationTitle(uiModel.selectedSettingsRoute.title)
        }
        .autoSuggestTinted()
    }
}

private struct SettingsDetailContent: View {
    let route: SettingsRoute
    @ObservedObject var uiModel: AutoSuggestUIModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
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
        .padding(AutoSuggestTheme.spacingLG)
    }
}
