import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let overflowMenu = NSMenu()
    private weak var uiModel: AutoSuggestUIModel?
    private var cancellables = Set<AnyCancellable>()

    func configure(with uiModel: AutoSuggestUIModel) {
        self.uiModel = uiModel

        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(handleStatusItemAction(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.appearsDisabled = false
            button.toolTip = "AutoSuggest"
        }

        popover.behavior = .transient
        popover.animates = true
        // Size the popover to fit the SwiftUI content so it never shows a
        // scrollbar (the content sizes itself roughly 300–360pt wide; height is intrinsic).
        let popoverHost = NSHostingController(rootView: StatusPopoverView(uiModel: uiModel))
        popoverHost.sizingOptions = [.preferredContentSize]
        popover.contentViewController = popoverHost

        buildOverflowMenu()
        refreshAppearance()

        uiModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshAppearance() }
            .store(in: &cancellables)
    }

    func refreshAppearance() {
        guard let button = statusItem.button, let uiModel else { return }

        // The brand ghost is always the base glyph. Attention states (paused,
        // needs-permission) stack a small colored badge in the bottom-right
        // corner so the icon stays recognizably AutoSuggest while still
        // communicating status.
        let state = MenuBarIconState.resolve(
            permissionsReady: uiModel.permissionHealth.isReady,
            enabled: uiModel.config.enabled,
            runtimeReady: uiModel.runtimeReady
        )
        let image = MenuBarIconRenderer.image(for: state)
        image.accessibilityDescription = state.tooltip
        button.image = image
        button.title = ""
        button.toolTip = state.tooltip
    }

    @objc private func handleStatusItemAction(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePopover(sender)
            return
        }

        switch event.type {
        case .rightMouseUp:
            popover.performClose(nil)
            statusItem.menu = overflowMenu
            sender.performClick(nil)
            statusItem.menu = nil
        default:
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            let anchorRect = sender.bounds.offsetBy(dx: 0, dy: -8)
            popover.show(relativeTo: anchorRect, of: sender, preferredEdge: .maxY)
        }
    }

    private func buildOverflowMenu() {
        overflowMenu.removeAllItems()

        let settingsItem = NSMenuItem(title: "Open Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        overflowMenu.addItem(settingsItem)

        let diagnosticsItem = NSMenuItem(
            title: "Export Diagnostics",
            action: #selector(exportDiagnostics),
            keyEquivalent: "e"
        )
        diagnosticsItem.target = self
        overflowMenu.addItem(diagnosticsItem)

        overflowMenu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "About AutoSuggest", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        overflowMenu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit AutoSuggest", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        overflowMenu.addItem(quitItem)
    }

    @objc private func openSettings() {
        uiModel?.openSettings(.general)
    }

    @objc private func exportDiagnostics() {
        uiModel?.exportDiagnostics()
    }

    @objc private func showAbout() {
        AboutWindowController.shared.showWindow()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
