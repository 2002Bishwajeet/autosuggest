import Carbon
import Foundation

struct InputMethodMonitor {
    func isIMEActive() -> Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return false
        }
        guard let sourceIDPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return false
        }
        let sourceID = Unmanaged<CFString>.fromOpaque(sourceIDPtr).takeUnretainedValue() as String
        return sourceID.contains("inputmethod")
    }
}
