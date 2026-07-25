import AppKit
import SwiftUI

@MainActor
final class PreferencesWindowController: NSWindowController {
    init(uiModel: AutoSuggestUIModel) {
        let hostingController = NSHostingController(rootView: SettingsRootView(uiModel: uiModel))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "AutoSuggest Settings"
        window.setContentSize(NSSize(width: 720, height: 560))
        window.contentMinSize = NSSize(width: 640, height: 480)
        window.toolbarStyle = .unified
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("AutoSuggestSettingsWindow")
        super.init(window: window)
        shouldCascadeWindows = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(route: SettingsRoute) {
        if let rootView = (window?.contentViewController as? NSHostingController<SettingsRootView>)?.rootView {
            rootView.uiModel.selectedSettingsRoute = route
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
