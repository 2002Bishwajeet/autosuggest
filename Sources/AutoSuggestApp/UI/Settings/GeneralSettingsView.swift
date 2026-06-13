import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var uiModel: AutoSuggestUIModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SimplePanel {
                Toggle("AutoSuggest", isOn: Binding(
                    get: { uiModel.config.enabled },
                    set: { uiModel.toggleEnabled($0) }
                ))

                Divider()

                Picker("Battery behavior", selection: Binding(
                    get: { uiModel.config.battery.mode },
                    set: { uiModel.updateBatteryMode($0) }
                )) {
                    Text("Always On").tag(BatteryMode.alwaysOn)
                    Text("Pause on Low Power").tag(BatteryMode.pauseOnLowPower)
                }
                .pickerStyle(.segmented)

                Divider()

                Toggle("Strict undo semantics", isOn: Binding(
                    get: { uiModel.config.insertion.strictUndoSemantics },
                    set: { uiModel.updateStrictUndo($0) }
                ))
                Text("When enabled, only clipboard-paste insertion is used, giving a cleaner Cmd+Z experience.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SimplePanel {
                SectionHeader("Shortcuts", systemImage: "keyboard")
                Text(
                    "Accept suggestions with Tab or Enter. Dismiss with Esc. Left-click the status item for quick controls and right-click for overflow actions."
                )
                .foregroundStyle(.secondary)
            }
        }
    }
}
