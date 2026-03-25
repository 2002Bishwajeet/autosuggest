import AppKit
import SwiftUI

@MainActor
final class OnboardingManager {
    private let defaultsKey = "autosuggest.onboarding.complete.v3"
    private var window: NSWindow?

    func showIfNeeded(
        permissionManager: PermissionManager,
        localModelConfig: LocalModelConfig,
        onSelectModelChoice: @escaping (OnboardingModelChoice) -> Void,
        downloadCoreML: @escaping () async throws -> Void,
        onOpenSettings: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) {
        guard !UserDefaults.standard.bool(forKey: defaultsKey) else {
            onComplete()
            return
        }

        let rootView = OnboardingFlowView(
            permissionManager: permissionManager,
            localModelConfig: localModelConfig,
            onSelectModelChoice: onSelectModelChoice,
            onDownloadCoreML: downloadCoreML,
            onOpenSettings: onOpenSettings,
            onComplete: { [weak self] in
                UserDefaults.standard.set(true, forKey: self?.defaultsKey ?? "")
                self?.window?.close()
                self?.window = nil
                onComplete()
            }
        )

        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "AutoSuggest Setup"
        window.setContentSize(NSSize(width: 760, height: 620))
        window.minSize = NSSize(width: 680, height: 540)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("AutoSuggestOnboardingWindow")
        window.toolbarStyle = .unifiedCompact
        window.titleVisibility = .hidden

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
