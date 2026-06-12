import AppKit
import ApplicationServices
import Foundation

@MainActor
final class FloatingOverlayRenderer: OverlayRenderer {
    private let logger = Logger(scope: "FloatingOverlayRenderer")
    private var panel: NSPanel?
    private var textField: NSTextField?
    private var hideGeneration = 0

    func showSuggestion(_ text: String, caretRectInScreen: CGRect?) {
        ensurePanel()
        guard let panel, let textField else { return }

        textField.stringValue = text
        layoutPanel(panel: panel, textField: textField, text: text, caretRectInScreen: caretRectInScreen)
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
        textField.textColor = NSColor.placeholderTextColor
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

    private func layoutPanel(panel: NSPanel, textField: NSTextField, text: String, caretRectInScreen: CGRect?) {
        // Match the ghost-text size to the caret/line height so it sits on the
        // same baseline as what the user is typing.
        if let caret = caretRectInScreen, caret.height > 8, caret.height < 64 {
            textField.font = NSFont.systemFont(ofSize: (caret.height * 0.72).rounded(), weight: .regular)
        } else {
            textField.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        }

        let measureAttributes: [NSAttributedString.Key: Any] = [.font: textField.font as Any]
        let measured = (text as NSString).size(withAttributes: measureAttributes)
        let width = min(measured.width + 4, 560)
        let height = max(measured.height, 14)

        // Hug the caret: start just after it and align vertically to its line.
        let anchor: CGPoint = if let caret = caretRectInScreen, !caret.isEmpty {
            CGPoint(x: caret.maxX + 1, y: caret.minY)
        } else {
            fallbackAnchor()
        }

        var targetFrame = NSRect(x: anchor.x, y: anchor.y, width: width, height: height)
        let screenFrame = targetScreenFrame(for: targetFrame.origin)
        targetFrame.origin.x = min(
            max(targetFrame.origin.x, screenFrame.minX + 4),
            screenFrame.maxX - targetFrame.width - 4
        )
        targetFrame.origin.y = min(
            max(targetFrame.origin.y, screenFrame.minY + 4),
            screenFrame.maxY - targetFrame.height - 4
        )

        panel.setFrame(targetFrame, display: true)
        textField.frame = NSRect(x: 0, y: 0, width: width, height: height)
    }

    private func targetScreenFrame(for point: CGPoint) -> CGRect {
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            return screen.visibleFrame
        }
        return NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 720)
    }

    private func fallbackAnchor() -> CGPoint {
        if let frame = focusedWindowFrame() {
            return CGPoint(x: frame.minX + 24, y: frame.maxY - 52)
        }
        let mouse = NSEvent.mouseLocation
        return CGPoint(x: mouse.x + 10, y: mouse.y - 12)
    }

    private func focusedWindowFrame() -> CGRect? {
        let systemWide = AXUIElementCreateSystemWide()
        guard let window = copyUIElementAttribute(named: "AXFocusedWindow", from: systemWide) else {
            return nil
        }
        guard let position = copyCGPointAttribute(named: "AXPosition", from: window),
              let size = copyCGSizeAttribute(named: "AXSize", from: window) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func copyUIElementAttribute(named attribute: String, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let value else { return nil }
        return AXHelpers.castToAXUIElement(value)
    }

    private func copyCGPointAttribute(named attribute: String, from element: AXUIElement) -> CGPoint? {
        guard let value = copyAXValueAttribute(named: attribute, from: element) else { return nil }
        var point = CGPoint.zero
        guard AXValueGetType(value) == .cgPoint, AXValueGetValue(value, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private func copyCGSizeAttribute(named attribute: String, from element: AXUIElement) -> CGSize? {
        guard let value = copyAXValueAttribute(named: attribute, from: element) else { return nil }
        var size = CGSize.zero
        guard AXValueGetType(value) == .cgSize, AXValueGetValue(value, .cgSize, &size) else {
            return nil
        }
        return size
    }

    private func copyAXValueAttribute(named attribute: String, from element: AXUIElement) -> AXValue? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let value else { return nil }
        return AXHelpers.castToAXValue(value)
    }
}
