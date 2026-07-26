import Foundation

struct PolicyRules {
    let blacklistedBundleIDs: Set<String>
    let codingBundleIDs: Set<String>
}

extension PolicyRules {
    static let `default` = PolicyRules(
        blacklistedBundleIDs: [
            "com.apple.loginwindow",
            "com.1password.1password",
            "com.agilebits.onepassword7",
            "com.bitwarden.desktop",
            "org.keepassxc.keepassxc",
            "com.lastpass.LastPass",
            // Terminals: AX reports a text surface, but it is a shell prompt. Probed
            // (docs/AX_COMPAT_MATRIX.md): Terminal.app exposes the visible prompt as
            // AXValue; Ghostty exposes the whole scrollback with the caret stuck at
            // offset 0. Context is wrong even where it is readable, and an accepted
            // completion lands on a command line. Terminal.app and Ghostty are
            // probe-verified; the rest share the same shell-prompt shape.
            "com.apple.Terminal",
            "com.mitchellh.ghostty",
            "com.googlecode.iterm2",
            "net.kovidgoyal.kitty",
            "org.alacritty",
            "com.github.wez.wezterm",
            "dev.warp.Warp-Stable",
        ],
        codingBundleIDs: [
            "com.microsoft.VSCode",
            "com.apple.dt.Xcode",
            "com.jetbrains.intellij",
        ]
    )
}

struct PolicyContext {
    let bundleID: String
    let axRole: String
    let isSecureField: Bool
    /// Field runs its own completion UI (browser address bar, combo box). Defaulted so
    /// existing call sites and fixtures are unaffected.
    var hasNativeCompletionUI: Bool = false
    let windowTitle: String?
    let textPrefix: String
}

struct PolicyEngine {
    private let defaults: PolicyRules
    private let userRules: [ExclusionRule]
    private let compiledPatterns: [String: NSRegularExpression]
    private let codeLikePatterns = [
        "func ",
        "class ",
        "import ",
        "const ",
        "let ",
        "var ",
        "=>",
        "{",
        "};",
    ]
    private let codeFileExtensions = [
        ".swift",
        ".py",
        ".js",
        ".ts",
        ".tsx",
        ".java",
        ".cpp",
        ".c",
        ".h",
        ".go",
        ".rs",
        ".rb",
        ".php",
    ]

    init(defaults: PolicyRules, userRules: [ExclusionRule] = []) {
        self.defaults = defaults
        self.userRules = userRules
        var compiled: [String: NSRegularExpression] = [:]
        for rule in userRules {
            if let pattern = rule.contentPattern, compiled[pattern] == nil,
               let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                compiled[pattern] = regex
            }
        }
        compiledPatterns = compiled
    }

    func shouldSuggest(in context: PolicyContext) -> Bool {
        if defaults.blacklistedBundleIDs.contains(context.bundleID) { return false }
        if defaults.codingBundleIDs.contains(context.bundleID) { return false }
        if context.isSecureField { return false }
        // Browser address bars and combo boxes: they run their own completion UI, so
        // ghost text would sit on top of the app's own inline suggestion or dropdown.
        // This is what actually catches address bars — the role check below never fires
        // on real browsers, which report a plain AXTextField (Safari, Chromium) or
        // AXComboBox (Firefox). Kept anyway for any app that does name its role "url".
        if context.hasNativeCompletionUI { return false }
        if context.axRole.lowercased().contains("url") { return false }
        if isCodeWindowTitle(context.windowTitle) { return false }
        if looksLikeCode(context.textPrefix) { return false }
        if isExcludedByUserRule(context) { return false }
        return true
    }

    private func isCodeWindowTitle(_ title: String?) -> Bool {
        guard let title else { return false }
        let lowercased = title.lowercased()
        return codeFileExtensions.contains(where: { lowercased.contains($0) })
    }

    private func looksLikeCode(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let recent = String(trimmed.suffix(120)).lowercased()
        return codeLikePatterns.contains(where: { recent.contains($0) })
    }

    private func isExcludedByUserRule(_ context: PolicyContext) -> Bool {
        for rule in userRules where rule.enabled {
            if let bundleID = rule.bundleID, bundleID != context.bundleID {
                continue
            }
            if let titlePattern = rule.windowTitleContains,
               !(context.windowTitle?.localizedCaseInsensitiveContains(titlePattern) ?? false) {
                continue
            }
            if let contentPattern = rule.contentPattern,
               !matchesRegex(pattern: contentPattern, in: context.textPrefix) {
                continue
            }
            return true
        }
        return false
    }

    private func matchesRegex(pattern: String, in text: String) -> Bool {
        guard let regex = compiledPatterns[pattern] else {
            return text.localizedCaseInsensitiveContains(pattern)
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
}
