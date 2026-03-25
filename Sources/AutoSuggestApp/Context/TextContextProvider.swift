import Foundation
import CoreGraphics

struct TextContext {
    let policyContext: PolicyContext
    let textBeforeCaret: String
    let fullText: String
    let selectedRange: NSRange?
    let caretRectInScreen: CGRect?
}

protocol TextContextProvider {
    func currentContext() -> TextContext?
}
