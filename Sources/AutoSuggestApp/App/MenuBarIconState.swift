import Foundation

/// The three meaningful menu-bar states, in priority order: a missing
/// permission outranks the on/off toggle.
enum MenuBarIconState: Equatable {
    case active // amber ghost
    case paused // pause.circle
    case needsPermission // exclamationmark.shield

    static func resolve(permissionsReady: Bool, enabled: Bool) -> MenuBarIconState {
        guard permissionsReady else { return .needsPermission }
        return enabled ? .active : .paused
    }

    var tooltip: String {
        switch self {
        case .active: "AutoSuggest is active"
        case .paused: "AutoSuggest is paused"
        case .needsPermission: "AutoSuggest needs permission — click to fix"
        }
    }
}
