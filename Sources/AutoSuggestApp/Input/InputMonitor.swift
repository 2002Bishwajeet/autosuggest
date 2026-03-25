import Foundation

protocol InputMonitor {
    func start(onEvent: @escaping (InputEvent) -> Void)
    func stop()
}
