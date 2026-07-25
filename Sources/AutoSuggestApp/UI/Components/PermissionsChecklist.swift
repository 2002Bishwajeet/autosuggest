import SwiftUI

/// Single source of truth for the wording of the two system permissions.
/// Onboarding and Settings previously carried diverged copies of these
/// strings; both now render through `PermissionsChecklist`.
enum PermissionCopy {
    static let accessibilityTitle = "Accessibility"
    static let accessibilityDescription =
        "Lets AutoSuggest read the text around your cursor and insert completions into any text field. Required for suggestions to work."
    static let inputMonitoringTitle = "Input Monitoring"
    static let inputMonitoringDescription =
        "Lets AutoSuggest detect Tab, Enter, and Esc so you can accept or dismiss suggestions. Requires a relaunch after granting."
}

/// Closures the checklist forwards to; each call site wires these to its own
/// backing object (`PermissionManager` in onboarding, `AutoSuggestUIModel`
/// in Settings).
struct PermissionsChecklistActions {
    var requestAccessibility: () -> Void
    var openAccessibilitySettings: () -> Void
    var requestInputMonitoring: () -> Void
    var openInputMonitoringSettings: () -> Void
}

/// The canonical Accessibility + Input Monitoring row pair. `context` selects
/// the action affordances: onboarding shows an active TCC-prompt button plus
/// an Open Settings fallback; Settings shows a single Open System Settings
/// button (macOS never re-prompts once denied, so an active prompt there
/// would silently no-op).
struct PermissionsChecklist: View {
    enum Context {
        case onboarding
        case settings
    }

    let context: Context
    let accessibilityGranted: Bool
    let inputMonitoringGranted: Bool
    let actions: PermissionsChecklistActions

    var body: some View {
        Group {
            PermissionRow(
                systemImage: "accessibility",
                title: PermissionCopy.accessibilityTitle,
                description: PermissionCopy.accessibilityDescription,
                granted: accessibilityGranted,
                primary: context == .onboarding
                    ? ("Show Prompt", actions.requestAccessibility)
                    : ("Open System Settings", actions.openAccessibilitySettings),
                secondary: context == .onboarding
                    ? ("Open Settings", actions.openAccessibilitySettings)
                    : nil
            )

            PermissionRow(
                systemImage: "keyboard",
                title: PermissionCopy.inputMonitoringTitle,
                description: PermissionCopy.inputMonitoringDescription,
                granted: inputMonitoringGranted,
                primary: context == .onboarding
                    ? ("Register App", actions.requestInputMonitoring)
                    : ("Open System Settings", actions.openInputMonitoringSettings),
                secondary: context == .onboarding
                    ? ("Open Settings", actions.openInputMonitoringSettings)
                    : nil
            )
        }
    }
}
