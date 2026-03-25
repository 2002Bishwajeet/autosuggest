import AppKit
import SwiftUI
import AutoSuggestApp

@main
struct AutoSuggestDesktopApp: App {
    @NSApplicationDelegateAdaptor(HostDelegate.self) private var hostDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class HostDelegate: NSObject, NSApplicationDelegate {
    private let service = AutoSuggestService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task {
            await service.start()
        }
    }
}
