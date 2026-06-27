import Foundation
import Security

public protocol SettingsServiceProtocol: Sendable {
    func loadSettings() async throws -> FocusFlowSettings
    func saveSettings(_ settings: FocusFlowSettings) async throws
}

public actor LocalSettingsService: SettingsServiceProtocol {
    private let directory: LocalDataDirectory

    public init(directory: LocalDataDirectory) {
        self.directory = directory
    }

    public func loadSettings() async throws -> FocusFlowSettings {
        try directory.prepare()
        let url = settingsURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .defaults
        }
        return try CorruptFileRecovery.decodeOrQuarantine(
            FocusFlowSettings.self,
            from: url,
            root: directory.root
        ) ?? .defaults
    }

    public func saveSettings(_ settings: FocusFlowSettings) async throws {
        try directory.prepare()
        let data = try FocusFlowJSON.encoder.encode(settings)
        try data.write(to: settingsURL, options: [.atomic])
    }

    private var settingsURL: URL {
        directory.settings.appendingPathComponent("privacy.json")
    }
}

public protocol CredentialStoreProtocol: Sendable {
    func readDeepSeekAPIKey() async -> String?
    func saveDeepSeekAPIKey(_ apiKey: String) async throws
    func deleteDeepSeekAPIKey() async throws
}

public actor KeychainCredentialStore: CredentialStoreProtocol {
    private let service = "com.focusflow.education-agent"
    private let deepSeekAccount = "deepseek_api_key"

    public init() {}

    public func readDeepSeekAPIKey() async -> String? {
        var query = baseQuery(account: deepSeekAccount)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func saveDeepSeekAPIKey(_ apiKey: String) async throws {
        let cleaned = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            try await deleteDeepSeekAPIKey()
            return
        }
        let data = Data(cleaned.utf8)
        var query = baseQuery(account: deepSeekAccount)
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw FocusFlowError.storageFailure("Could not save DeepSeek API key to Keychain: \(addStatus)")
            }
        } else if status != errSecSuccess {
            throw FocusFlowError.storageFailure("Could not update DeepSeek API key in Keychain: \(status)")
        }
    }

    public func deleteDeepSeekAPIKey() async throws {
        let status = SecItemDelete(baseQuery(account: deepSeekAccount) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw FocusFlowError.storageFailure("Could not delete DeepSeek API key from Keychain: \(status)")
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
