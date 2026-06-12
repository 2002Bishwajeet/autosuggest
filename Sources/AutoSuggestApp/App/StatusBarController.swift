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
        // Size the popover to fit the SwiftUI content so it never shows a
        // scrollbar (the content sets its own 368pt width; height is intrinsic).
        let popoverHost = NSHostingController(rootView: StatusPopoverView(uiModel: uiModel))
        popoverHost.sizingOptions = [.preferredContentSize]
        popover.contentViewController = popoverHost

        buildOverflowMenu()
        refreshAppearance()
    }

    func refreshAppearance() {
        guard let button = statusItem.button, let uiModel else { return }

        // Active state shows the brand ghost glyph; paused/permission states keep
        // their meaningful SF Symbols so the menu bar still communicates status.
        let state = MenuBarIconState.resolve(
            permissionsReady: uiModel.permissionHealth.isReady,
            enabled: uiModel.config.enabled
        )
        switch state {
        case .active:
            button.image = Self.ghostMenuBarImage()
        case .paused:
            button.image = Self.symbolImage("pause.circle")
        case .needsPermission:
            button.image = Self.symbolImage("exclamationmark.shield")
        }
        button.title = ""
        button.toolTip = state.tooltip
    }

    /// The amber-ghost brand glyph as a tintable menu-bar template image. Falls
    /// back to the `text.cursor` SF Symbol when the asset catalog isn't present
    /// (e.g. the SwiftPM `AutoSuggestRunner`, which has no Assets.xcassets).
    private static func ghostMenuBarImage() -> NSImage? {
        if let ghost = NSImage(named: NSImage.Name("MenuBarGhost")) {
            ghost.isTemplate = true
            ghost.size = NSSize(width: 16, height: 16)
            return ghost
        }
        let fallback = NSImage(systemSymbolName: "text.cursor", accessibilityDescription: "AutoSuggest")
        fallback?.isTemplate = true
        return fallback?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .medium))
    }

    private static func symbolImage(_ name: String) -> NSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: "AutoSuggest") else { return nil }
        image.isTemplate = true
        return image.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .medium))
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
