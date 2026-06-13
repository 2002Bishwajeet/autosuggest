import AppKit
import CoreGraphics
import Foundation

@MainActor
protocol OverlayRenderer {
    /// Shows the ghost text at the caret.
    /// - Parameters:
    ///   - text: the completion to render as dimmed ghost text.
    ///   - caretRectInScreen: caret/selection rect in screen coords.
    ///   - font: the focused field's font read via AX (B1), or `nil` to fall
    ///     back to the caret-height heuristic.
    func showSuggestion(_ text: String, caretRectInScreen: CGRect?, font: NSFont?)
    func hideSuggestion()
}
