import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let service: AutoSuggestService

    init(service: AutoSuggestService) {
        self.service = service
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            await service.start()
        }
    }
}
