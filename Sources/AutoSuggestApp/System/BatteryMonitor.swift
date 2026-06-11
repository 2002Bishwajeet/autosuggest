import Foundation

struct BatteryMonitor {
    func shouldPauseSuggestions(mode: BatteryMode) -> Bool {
        switch mode {
        case .alwaysOn:
            false
        case .pauseOnLowPower:
            ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
}
