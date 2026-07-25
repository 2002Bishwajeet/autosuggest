import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let service: AutoSuggestService
    private let statusBarController = StatusBarController()

    init(service: AutoSuggestService) {
        self.service = service
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        service.onUIModelReady = { [statusBarController] uiModel in
            statusBarController.configure(with: uiModel)
        }
        Task {
            await service.start()
        }
    }
}
