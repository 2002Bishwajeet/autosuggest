import AppKit
import Foundation

extension AppCoordinator {
    func toggleRuleEnabled(_ rule: ExclusionRule, enabled: Bool) {
        guard var currentConfig else { return }
        guard let index = currentConfig.exclusions.userRules.firstIndex(of: rule) else { return }
        currentConfig.exclusions.userRules[index].enabled = enabled
        self.currentConfig = currentConfig

        Task {
            await configStore.updateExclusionRules(currentConfig.exclusions.userRules)
        }
        rebuildRuntimePipelines(using: currentConfig)
        refreshPresentation()
        setPipelineEnabledFromCurrentState()
    }

    func saveExclusionRule(_ draft: ExclusionRuleDraft, originalRule: ExclusionRule?) {
        guard draft.validationMessage() == nil else { return }
        guard var currentConfig else { return }
        let newRule = draft.makeRule()

        if let originalRule, let index = currentConfig.exclusions.userRules.firstIndex(of: originalRule) {
            currentConfig.exclusions.userRules[index] = newRule
        } else {
            currentConfig.exclusions.userRules.append(newRule)
        }

        self.currentConfig = currentConfig
        Task {
            await configStore.updateExclusionRules(currentConfig.exclusions.userRules)
        }
        rebuildRuntimePipelines(using: currentConfig)
        refreshPresentation()
    }

    func deleteExclusionRule(_ rule: ExclusionRule) {
        guard var currentConfig else { return }
        currentConfig.exclusions.userRules.removeAll { $0 == rule }
        self.currentConfig = currentConfig
        Task {
            await configStore.updateExclusionRules(currentConfig.exclusions.userRules)
        }
        rebuildRuntimePipelines(using: currentConfig)
        refreshPresentation()
    }

    func applyExclusionPreset(_ bundleID: String) {
        guard var currentConfig else { return }
        let rule = ExclusionRule(
            enabled: true,
            bundleID: bundleID,
            windowTitleContains: nil,
            contentPattern: nil
        )
        guard !currentConfig.exclusions.userRules.contains(rule) else { return }

        currentConfig.exclusions.userRules.append(rule)
        self.currentConfig = currentConfig
        Task {
            await configStore.updateExclusionRules(currentConfig.exclusions.userRules)
        }
        rebuildRuntimePipelines(using: currentConfig)
        refreshPresentation()
    }

    func excludeFrontmostApp() {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return }
        applyExclusionPreset(bundleID)
        uiModel?.showBanner(
            kind: .success,
            title: "App excluded",
            message: "\(bundleID) will no longer receive suggestions."
        )
    }
}
