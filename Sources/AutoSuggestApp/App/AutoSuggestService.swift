import AppKit
import Foundation

@MainActor
public final class AutoSuggestService {
    private let coordinator = AppCoordinator()

    public init() {}

    public func start() async {
        await coordinator.start()
    }
}

@MainActor
public enum AutoSuggestMenuBarApp {
    public static func run() {
        let app = NSApplication.shared
        let delegate = AppDelegate(service: AutoSuggestService())
        app.delegate = delegate
        app.mainMenu = makeMainMenu()
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private static func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "AutoSuggest"

        let quitItem = NSMenuItem(
            title: "Quit \(appName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        appMenu.addItem(quitItem)

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        return mainMenu
    }
}
