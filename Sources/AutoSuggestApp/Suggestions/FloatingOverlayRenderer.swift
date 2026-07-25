import AppKit
import Foundation

@MainActor
final class FloatingOverlayRenderer: OverlayRenderer {
    /// B3 — the dim-grey ghost color. Single tunable constant.
    ///
    /// Validated against Apple's native inline-prediction grey: macOS renders
    /// inline predictions in a placeholder-weight grey, which `placeholderTextColor`
    /// matches most closely (it is the dynamic system grey Apple uses for
    /// in-field placeholder/prediction text). `tertiaryLabelColor` reads
    /// noticeably lighter/more translucent at small point sizes, so it drifts
    /// from the native ghost. Kept here as a one-line swap if Apple retunes it.
    static let ghostTextColor: NSColor = .placeholderTextColor

    private let logger = Logger(scope: "FloatingOverlayRenderer")
    private var panel: NSPanel?
    private var textField: NSTextField?
    private var hideGeneration = 0

    func showSuggestion(_ text: String, caretRectInScreen: CGRect?, font: NSFont?) {
        // #26: the ghost is only convincing when it sits at the caret. Without
        // usable caret bounds, show nothing — a box floating at the mouse or a
        // window corner reads as a glitch, not a completion. (Zero WIDTH is a
        // normal collapsed caret; zero height means the AX read failed.)
        guard let caret = caretRectInScreen, caret.height > 0 else {
            hideSuggestion()
            return
        }
        ensurePanel()
        guard let panel, let textField else { return }

        textField.stringValue = text
        layoutPanel(
            panel: panel,
            textField: textField,
            text: text,
            caretRectInScreen: caret,
            axFont: font
        )
        hideGeneration += 1
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.14
            panel.animator().alphaValue = 1
        }
    }

    func hideSuggestion() {
        guard let panel, panel.isVisible else { return }
        hideGeneration += 1
        let generation = hideGeneration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12
            panel.animator().alphaValue = 0
        } completionHandler: {
            DispatchQueue.main.async { [weak self] in
                guard let self, hideGeneration == generation else { return }
                self.panel?.orderOut(nil)
            }
        }
    }

    private func ensurePanel() {
        guard panel == nil else { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 200, y: 200, width: 160, height: 36),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = NSColor.clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false

        // Inline-style ghost text: no box, no frosted chrome — just dimmed
        // continuation text rendered right at the caret so it reads like in-field
        // autocomplete (e.g. QuickType / Copilot) rather than a floating tooltip.
        let container = NSView()
        container.wantsLayer = true

        let textField = NSTextField(labelWithString: "")
        textField.textColor = Self.ghostTextColor
        textField.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        textField.alignment = .natural
        textField.lineBreakMode = .byTruncatingTail
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.backgroundColor = .clear
        textField.frame = NSRect(x: 0, y: 0, width: 96, height: 18)
        textField.autoresizingMask = [.width, .height]

        container.addSubview(textField)
        panel.contentView = container

        self.panel = panel
        self.textField = textField
        logger.info("Overlay panel created.")
    }

    private func layoutPanel(
        panel: NSPanel,
        textField: NSTextField,
        text: String,
        caretRectInScreen: CGRect,
        axFont: NSFont?
    ) {
        // B1: render in the real field font when AX exposed one; otherwise fall
        // back to the caret-height heuristic (both handled by resolvedFont).
        let font = GhostTextLayout.resolvedFont(axFont: axFont, caretRect: caretRectInScreen)
        textField.font = font

        let measureAttributes: [NSAttributedString.Key: Any] = [.font: font]
        var measured = (text as NSString).size(withAttributes: measureAttributes)
        measured.width = min(measured.width, 556) // cap (≈560 frame after +4)

        // B2: baseline-aligned target frame from the pure layout function.
        let targetFrame = GhostTextLayout.ghostFrame(
            caretRect: caretRectInScreen,
            font: font,
            measuredSize: measured
        )

        var clampedFrame = targetFrame
        let screenFrame = targetScreenFrame(for: clampedFrame.origin)
        clampedFrame.origin.x = min(
            max(clampedFrame.origin.x, screenFrame.minX + 4),
            screenFrame.maxX - clampedFrame.width - 4
        )
        clampedFrame.origin.y = min(
            max(clampedFrame.origin.y, screenFrame.minY + 4),
            screenFrame.maxY - clampedFrame.height - 4
        )

        panel.setFrame(clampedFrame, display: true)
        textField.frame = NSRect(x: 0, y: 0, width: clampedFrame.width, height: clampedFrame.height)
    }

    private func targetScreenFrame(for point: CGPoint) -> CGRect {
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            return screen.visibleFrame
        }
        return NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 720)
    }
}
