import Foundation

protocol InputMonitor {
    /// True when the event tap is installed and currently enabled.
    var isActive: Bool { get }
    func start(onEvent: @escaping (InputEvent) -> Void)
    func stop()
}
