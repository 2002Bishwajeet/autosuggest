import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let overflowMenu = NSMenu()
    private weak var uiModel: AutoSuggestUIModel?

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
        popover.contentSize = NSSize(width: 368, height: 408)
        popover.contentViewController = NSHostingController(rootView: StatusPopoverView(uiModel: uiModel))

        buildOverflowMenu()
        refreshAppearance()
    }

    func refreshAppearance() {
        guard let button = statusItem.button, let uiModel else { return }
        let symbolName: String
        if uiModel.permissionHealth.isReady {
            symbolName = uiModel.config.enabled ? "text.cursor" : "pause.circle"
        } else {
            symbolName = "exclamationmark.shield"
        }

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "AutoSuggest") {
            image.isTemplate = true
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            button.image = image.withSymbolConfiguration(config)
        }
        button.title = ""
        button.toolTip = uiModel.quickPanelState.statusHeadline
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

        let diagnosticsItem = NSMenuItem(title: "Export Diagnostics", action: #selector(exportDiagnostics), keyEquivalent: "e")
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
