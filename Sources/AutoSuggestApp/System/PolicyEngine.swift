import Foundation

struct PolicyRules {
    let blacklistedBundleIDs: Set<String>
    let codingBundleIDs: Set<String>
}

extension PolicyRules {
    static let `default` = PolicyRules(
        blacklistedBundleIDs: [
            "com.apple.loginwindow",
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
    let windowTitle: String?
    let textPrefix: String
}

struct PolicyEngine {
    private let defaults: PolicyRules
    private let userRules: [ExclusionRule]
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
    }

    func shouldSuggest(in context: PolicyContext) -> Bool {
        if defaults.blacklistedBundleIDs.contains(context.bundleID) { return false }
        if defaults.codingBundleIDs.contains(context.bundleID) { return false }
        if context.isSecureField { return false }
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
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text.localizedCaseInsensitiveContains(pattern)
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
}
