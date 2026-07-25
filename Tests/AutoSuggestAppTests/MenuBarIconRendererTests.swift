import AppKit
import XCTest
@testable import AutoSuggestApp

final class MenuBarIconRendererTests: XCTestCase {
    func testProducesImageForEveryState() {
        for state in [MenuBarIconState.active, .paused, .needsPermission] {
            let image = MenuBarIconRenderer.image(for: state)
            XCTAssertGreaterThan(image.size.width, 0, "empty image for \(state)")
        }
    }

    func testActiveIsTemplateBadgedIsNot() {
        XCTAssertTrue(MenuBarIconRenderer.image(for: .active).isTemplate)
        XCTAssertFalse(MenuBarIconRenderer.image(for: .paused).isTemplate)
        XCTAssertFalse(MenuBarIconRenderer.image(for: .needsPermission).isTemplate)
    }
}
