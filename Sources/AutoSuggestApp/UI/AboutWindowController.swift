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
        let hostingController = NSHostingController(rootView: aboutView.autoSuggestTinted())
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

/// Formats the About window's version line. Pure + testable so the fallback
/// (used when the bundle keys are missing) is locked down by a unit test rather
/// than a stale hardcoded version number.
enum AboutVersion {
    static func string(shortVersion: String?, build: String?) -> String {
        "Version \(shortVersion ?? "—") (\(build ?? "1"))"
    }
}

private struct AboutView: View {
    private let repoURL = URL(string: "https://github.com/2002Bishwajeet/autosuggest")
    private let issuesURL = URL(string: "https://github.com/2002Bishwajeet/autosuggest/issues")

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
                if let repoURL {
                    Link("View on GitHub", destination: repoURL)
                }
                if let issuesURL {
                    Link("Report an issue", destination: issuesURL)
                }
            }
            .font(.callout)
            .tint(AutoSuggestTheme.brand)

            Text("Licensed under GPL v3 · Local & private by design")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(minWidth: 300, idealWidth: 340)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var versionString: String {
        AboutVersion.string(
            shortVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
    }
}
