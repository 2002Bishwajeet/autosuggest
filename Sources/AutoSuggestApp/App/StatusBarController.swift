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

        // The brand ghost is always the base glyph. Attention states (paused,
        // needs-permission) stack a small colored badge in the bottom-right
        // corner so the icon stays recognizably AutoSuggest while still
        // communicating status.
        let state = MenuBarIconState.resolve(
            permissionsReady: uiModel.permissionHealth.isReady,
            enabled: uiModel.config.enabled,
            runtimeReady: uiModel.modelHealth.report.runtimeHealth.contains(where: \.ready)
        )
        let image = Self.menuBarImage(for: state)
        image?.accessibilityDescription = state.tooltip
        button.image = image
        button.title = ""
        button.toolTip = state.tooltip
    }

    /// The ghost glyph, optionally with a stacked status badge. Active state
    /// returns a clean monochrome template (the standard menu-bar look); badged
    /// states return a colored composite.
    private static func menuBarImage(for state: MenuBarIconState) -> NSImage? {
        guard let badge = state.badge else {
            let ghost = ghostBaseImage()
            ghost?.isTemplate = true
            return ghost
        }
        return badgedGhostImage(badge)
    }

    /// The amber-ghost brand glyph as a tintable template image. Falls back to
    /// the `text.cursor` SF Symbol when the asset catalog isn't present (e.g. the
    /// SwiftPM `AutoSuggestRunner`, which has no Assets.xcassets).
    private static func ghostBaseImage() -> NSImage? {
        if let ghost = NSImage(named: NSImage.Name("MenuBarGhost")) {
            ghost.isTemplate = true
            ghost.size = NSSize(width: 16, height: 16)
            return ghost
        }
        let fallback = NSImage(systemSymbolName: "text.cursor", accessibilityDescription: "AutoSuggest")
        fallback?.isTemplate = true
        return fallback?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .medium))
    }

    /// Composites the ghost with a colored badge dot + inner glyph in the
    /// bottom-right corner. Uses a deferred `drawingHandler` so the ghost's
    /// adaptive `labelColor` is resolved in the menu bar's own appearance every
    /// time it renders (baking it once produces a near-black glyph that vanishes
    /// on a dark menu bar). A transparent "halo" is knocked out of the ghost
    /// around the dot so the badge reads as a separate stacked layer.
    private static func badgedGhostImage(_ badge: MenuBarBadge) -> NSImage {
        let canvas = NSSize(width: 18, height: 18)
        let image = NSImage(size: canvas, flipped: false) { _ in
            guard let ghost = ghostBaseImage() else { return false }
            ghost.isTemplate = true

            // Ghost, tinted to the menu-bar label color (adapts light/dark).
            let ghostRect = NSRect(x: 0, y: 2, width: 16, height: 16)
            ghost.draw(in: ghostRect)
            NSColor.labelColor.set()
            ghostRect.fill(using: .sourceAtop)

            // Badge dot, bottom-right, with a knocked-out halo for separation.
            let diameter: CGFloat = 11
            let badgeRect = NSRect(x: canvas.width - diameter, y: 0, width: diameter, height: diameter)
            if let ctx = NSGraphicsContext.current {
                ctx.compositingOperation = .clear
                NSBezierPath(ovalIn: badgeRect.insetBy(dx: -1.5, dy: -1.5)).fill()
                ctx.compositingOperation = .sourceOver
            }
            badgeColor(for: badge).setFill()
            NSBezierPath(ovalIn: badgeRect).fill()

            // Inner glyph, tinted white in isolation so only the symbol is white
            // (not the whole dot), then composited onto the dot.
            if let symbol = NSImage(systemSymbolName: badge.symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 7, weight: .bold)) {
                symbol.isTemplate = true
                let white = tinted(symbol, .white)
                let size = white.size
                let glyphRect = NSRect(
                    x: badgeRect.midX - size.width / 2,
                    y: badgeRect.midY - size.height / 2,
                    width: size.width,
                    height: size.height
                )
                white.draw(in: glyphRect)
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Returns a copy of a template image tinted a solid color, with the
    /// background left transparent (so only the symbol's pixels take the color).
    private static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        let out = NSImage(size: image.size)
        out.lockFocus()
        defer { out.unlockFocus() }
        let rect = NSRect(origin: .zero, size: image.size)
        image.draw(in: rect)
        color.set()
        rect.fill(using: .sourceAtop)
        return out
    }

    private static func badgeColor(for badge: MenuBarBadge) -> NSColor {
        switch badge {
        case .paused: brandAmber
        case .needsPermission: .systemRed
        case .degraded: .systemOrange
        }
    }

    /// Lantern-amber brand accent (#E3A411 / #F0B43C in dark), matching
    /// `AutoSuggestTheme.brand`.
    private static let brandAmber = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0xF0 / 255.0, green: 0xB4 / 255.0, blue: 0x3C / 255.0, alpha: 1)
            : NSColor(srgbRed: 0xE3 / 255.0, green: 0xA4 / 255.0, blue: 0x11 / 255.0, alpha: 1)
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
