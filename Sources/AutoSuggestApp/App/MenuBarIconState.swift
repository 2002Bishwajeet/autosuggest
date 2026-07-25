import Foundation

/// The meaningful menu-bar states, in priority order: a missing permission
/// outranks the on/off toggle, which outranks a runtime that isn't ready.
enum MenuBarIconState: Equatable {
    case active // amber ghost
    case paused // pause.circle
    case needsPermission // exclamationmark.shield
    case degraded // enabled, but no local runtime is ready (e.g. Ollama not running)

    static func resolve(permissionsReady: Bool, enabled: Bool, runtimeReady: Bool) -> MenuBarIconState {
        guard permissionsReady else { return .needsPermission }
        guard enabled else { return .paused }
        return runtimeReady ? .active : .degraded
    }

    var tooltip: String {
        switch self {
        case .active: "AutoSuggest is active"
        case .paused: "AutoSuggest is paused"
        case .needsPermission: "AutoSuggest needs permission — click to fix"
        case .degraded: "AutoSuggest can't reach a model — click to fix"
        }
    }

    /// The status badge stacked on the brand glyph, or `nil` when the icon
    /// stands alone (active). The base menu-bar icon is always the ghost; only
    /// attention states add a badge.
    var badge: MenuBarBadge? {
        switch self {
        case .active: nil
        case .paused: .paused
        case .needsPermission: .needsPermission
        case .degraded: .degraded
        }
    }
}

/// A small corner badge composited onto the menu-bar glyph. The color is chosen
/// in the AppKit layer (`StatusBarController`); this type stays UI-framework-free
/// so it remains trivially testable.
enum MenuBarBadge: Equatable {
    case paused
    case needsPermission
    case degraded

    /// SF Symbol drawn inside the badge dot.
    var symbolName: String {
        switch self {
        case .paused: "pause.fill"
        case .needsPermission: "exclamationmark"
        case .degraded: "bolt.slash.fill"
        }
    }
}
