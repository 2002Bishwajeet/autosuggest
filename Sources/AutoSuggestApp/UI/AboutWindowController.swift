import AppKit
import SwiftUI

@MainActor
final class AboutWindowController {
    static let shared = AboutWindowController()

    private var window: NSWindow?

    func showWindow() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let aboutView = AboutView()
        let hostingController = NSHostingController(rootView: aboutView)
        hostingController.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hostingController)
        window.title = "About AutoSuggest"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct AboutView: View {
    private let repoURL = URL(string: "https://github.com/2002Bishwajeet/autosuggest")!
    private let issuesURL = URL(string: "https://github.com/2002Bishwajeet/autosuggest/issues")!

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)
                .accessibilityHidden(true)

            Text("AutoSuggest")
                .font(.title2.weight(.semibold))

            Text("System-wide autocomplete powered by local LLMs")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(versionString)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)

            Divider()
                .padding(.horizontal, 32)

            VStack(spacing: 8) {
                Link("View on GitHub", destination: repoURL)
                Link("Report an issue", destination: issuesURL)
            }
            .font(.callout)
            .tint(AutoSuggestTheme.brand)

            Text("Licensed under GPL v3 · Local & private by design")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(version) (\(build))"
    }
}
