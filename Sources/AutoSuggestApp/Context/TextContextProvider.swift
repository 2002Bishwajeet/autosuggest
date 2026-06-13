import AppKit
import CoreGraphics
import Foundation

struct TextContext {
    let policyContext: PolicyContext
    let textBeforeCaret: String
    let fullText: String
    let selectedRange: NSRange?
    let caretRectInScreen: CGRect?
    /// The focused field's font, read from AX (B1). `nil` when AX exposes no
    /// font — the renderer then falls back to the caret-height heuristic.
    let caretFont: NSFont?
    /// `true` when a best-effort AX read found Apple's own native inline
    /// prediction already showing on the focused element (B5). When set, we
    /// suppress our overlay to avoid a stacked double-ghost.
    let nativeInlineSuggestionPresent: Bool

    init(
        policyContext: PolicyContext,
        textBeforeCaret: String,
        fullText: String,
        selectedRange: NSRange?,
        caretRectInScreen: CGRect?,
        caretFont: NSFont? = nil,
        nativeInlineSuggestionPresent: Bool = false
    ) {
        self.policyContext = policyContext
        self.textBeforeCaret = textBeforeCaret
        self.fullText = fullText
        self.selectedRange = selectedRange
        self.caretRectInScreen = caretRectInScreen
        self.caretFont = caretFont
        self.nativeInlineSuggestionPresent = nativeInlineSuggestionPresent
    }
}

protocol TextContextProvider {
    func currentContext() -> TextContext?
}
