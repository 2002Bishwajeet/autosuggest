import AppKit
import Combine
import Sparkle
import SwiftUI
import AutoSuggestApp

/// Owns app startup for the MenuBarExtra app: the service, the Sparkle updater,
/// activation policy, and the published UI model that the menu-bar scene binds to.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var uiModel: AutoSuggestUIModel?

    private let service = AutoSuggestService()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    private var uiModelObservation: AnyCancellable?

    init() {
        NSApp.setActivationPolicy(.accessory)
        service.onCheckForUpdates = { [weak self] in
            self?.updaterController.updater.checkForUpdates()
        }
        service.onUIModelReady = { [weak self] uiModel in
            guard let self else { return }
            self.uiModel = uiModel
            // Forward model changes so the menu-bar icon label recomputes.
            self.uiModelObservation = uiModel.objectWillChange
                .sink { [weak self] _ in self?.objectWillChange.send() }
        }
        Task { await service.start() }
    }

    /// The menu-bar glyph for the current state; a plain ghost until the model
    /// exists.
    var menuBarIcon: NSImage {
        guard let uiModel else { return MenuBarIconRenderer.image(for: .active) }
        let state = MenuBarIconState.resolve(
            permissionsReady: uiModel.permissionHealth.isReady,
            enabled: uiModel.config.enabled
        )
        return MenuBarIconRenderer.image(for: state)
    }
}
