import CryptoKit
import Foundation

actor EncryptedFileStore {
    private let keyStore = KeychainKeyStore()
    private let logger = Logger(scope: "EncryptedFileStore")

    func save<T: Encodable>(_ value: T, to fileName: String) {
        do {
            let key = try keyStore.getOrCreateKeyData()
            let symmetricKey = SymmetricKey(data: key)
            let plain = try JSONEncoder().encode(value)
            let sealed = try AES.GCM.seal(plain, using: symmetricKey)
            guard let combined = sealed.combined else { return }

            let file = try storageDirectory().appendingPathComponent(fileName, isDirectory: false)
            try combined.write(to: file, options: .atomic)
        } catch {
            logger.warn("Encrypted save failed: \(error.localizedDescription)")
        }
    }

    func load<T: Decodable>(_ type: T.Type, from fileName: String) -> T? {
        do {
            let file = try storageDirectory().appendingPathComponent(fileName, isDirectory: false)
            guard let data = try? Data(contentsOf: file) else { return nil }
            let key = try keyStore.getOrCreateKeyData()
            let symmetricKey = SymmetricKey(data: key)
            let box = try AES.GCM.SealedBox(combined: data)
            let plain = try AES.GCM.open(box, using: symmetricKey)
            return try JSONDecoder().decode(type, from: plain)
        } catch {
            logger.warn("Encrypted load failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func storageDirectory() throws -> URL {
        let base = try AppDirectories.applicationSupportURL()
        let dir = base.appendingPathComponent("AutoSuggestApp/Secure", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}
