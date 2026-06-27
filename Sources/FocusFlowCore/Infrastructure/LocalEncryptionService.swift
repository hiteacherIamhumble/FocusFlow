import CryptoKit
import Foundation
import Security

public protocol LocalEncryptionKeyProvider: Sendable {
    func loadOrCreateKey() async throws -> SymmetricKey
}

public actor KeychainLocalEncryptionKeyProvider: LocalEncryptionKeyProvider {
    private let service = "com.focusflow.education-agent"
    private let account = "local_encryption_key_v1"

    public init() {}

    public func loadOrCreateKey() async throws -> SymmetricKey {
        if let existing = try readKeyData() {
            return SymmetricKey(data: existing)
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw FocusFlowError.storageFailure("Could not generate local encryption key: \(status)")
        }
        let data = Data(bytes)
        try saveKeyData(data)
        return SymmetricKey(data: data)
    }

    private func readKeyData() throws -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw FocusFlowError.storageFailure("Could not read local encryption key from Keychain: \(status)")
        }
        return data
    }

    private func saveKeyData(_ data: Data) throws {
        var query = baseQuery()
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw FocusFlowError.storageFailure("Could not save local encryption key to Keychain: \(addStatus)")
            }
        } else if status != errSecSuccess {
            throw FocusFlowError.storageFailure("Could not update local encryption key in Keychain: \(status)")
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

public actor StaticLocalEncryptionKeyProvider: LocalEncryptionKeyProvider {
    private let key: SymmetricKey

    public init(seed: String = "focusflow-local-encryption-test-seed-32") {
        let data = Data(seed.utf8.prefix(32))
        self.key = SymmetricKey(data: data)
    }

    public func loadOrCreateKey() async throws -> SymmetricKey {
        key
    }
}

public struct LocalEncryptionService: Sendable {
    private static let envelopePrefix = "FFENC1:"
    private let keyProvider: any LocalEncryptionKeyProvider

    public init(keyProvider: any LocalEncryptionKeyProvider = KeychainLocalEncryptionKeyProvider()) {
        self.keyProvider = keyProvider
    }

    public func encrypt(_ data: Data) async throws -> Data {
        let key = try await keyProvider.loadOrCreateKey()
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw FocusFlowError.storageFailure("Could not produce encrypted local data envelope.")
        }
        return Data((Self.envelopePrefix + combined.base64EncodedString()).utf8)
    }

    public func decryptIfNeeded(_ data: Data) async throws -> Data {
        guard let text = String(data: data, encoding: .utf8),
              text.hasPrefix(Self.envelopePrefix) else {
            return data
        }
        let encoded = String(text.dropFirst(Self.envelopePrefix.count))
        guard let combined = Data(base64Encoded: encoded) else {
            throw FocusFlowError.storageFailure("Encrypted local data envelope is malformed.")
        }
        let key = try await keyProvider.loadOrCreateKey()
        let sealed = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(sealed, using: key)
    }

    public static func isEncrypted(_ data: Data) -> Bool {
        String(data: data.prefix(7), encoding: .utf8) == envelopePrefix
    }
}
