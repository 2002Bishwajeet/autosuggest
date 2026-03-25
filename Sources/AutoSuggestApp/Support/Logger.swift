import Foundation
import OSLog

struct Logger {
    private let logger: os.Logger

    init(scope: String) {
        logger = os.Logger(subsystem: "com.autosuggest.app", category: scope)
    }

    func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    func warn(_ message: String) {
        logger.warning("\(message, privacy: .public)")
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
