import Foundation

enum AppDirectories {
    static func applicationSupportURL() throws -> URL {
        guard let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw AppDirectoryError.missingApplicationSupportDirectory
        }
        return url
    }

    static func appSupportDirectory() throws -> URL {
        try applicationSupportURL().appendingPathComponent("AutoSuggestApp")
    }
}

enum AppDirectoryError: Error, CustomStringConvertible {
    case missingApplicationSupportDirectory

    var description: String {
        switch self {
        case .missingApplicationSupportDirectory:
            return "Could not locate Application Support directory"
        }
    }
}
