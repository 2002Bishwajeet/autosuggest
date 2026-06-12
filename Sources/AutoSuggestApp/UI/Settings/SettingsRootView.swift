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
                            HStack {
                                Image(systemName: route.systemImage)
                                Text(route.title)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(route == uiModel
                                        .selectedSettingsRoute ? Color(nsColor: .selectedContentBackgroundColor) :
                                        .clear)
                            )
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
