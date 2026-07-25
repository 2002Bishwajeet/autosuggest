import SwiftUI
import AutoSuggestApp

@main
struct AutoSuggestDesktopApp: App {
    @StateObject private var app = AppModel()

    var body: some Scene {
        MenuBarExtra {
            if let uiModel = app.uiModel {
                StatusPopoverView(uiModel: uiModel)
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Starting AutoSuggest…").foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(width: 260)
            }
        } label: {
            Image(nsImage: app.menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }
}
