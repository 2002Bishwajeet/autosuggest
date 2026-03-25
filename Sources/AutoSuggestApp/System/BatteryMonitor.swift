import Foundation

struct BatteryMonitor {
    func shouldPauseSuggestions(mode: BatteryMode) -> Bool {
        switch mode {
        case .alwaysOn:
            return false
        case .pauseOnLowPower:
            return ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
}
