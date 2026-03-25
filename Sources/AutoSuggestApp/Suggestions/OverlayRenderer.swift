import CoreGraphics
import Foundation

@MainActor
protocol OverlayRenderer {
    func showSuggestion(_ text: String, caretRectInScreen: CGRect?)
    func hideSuggestion()
}
