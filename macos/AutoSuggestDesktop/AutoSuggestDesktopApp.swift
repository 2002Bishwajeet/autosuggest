import AppKit
import Sparkle
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

    // Sparkle's standard updater controller. `startingUpdater: true` starts the
    // updater immediately, honoring SUEnableAutomaticChecks / SUScheduledCheckInterval
    // from Info.plist for background daily checks.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // This is a menu-bar accessory app with no standard menu bar, so the
        // "Check for Updates…" affordance lives in the library's status popover.
        // Wire the library callback to Sparkle's manual update check here.
        service.onCheckForUpdates = { [weak self] in
            self?.updaterController.updater.checkForUpdates()
        }

        Task {
            await service.start()
        }
    }
}
