import Foundation

public actor LocalRuntimeStore: RuntimeStoreProtocol {
    private let directory: LocalDataDirectory
    private let encryptionService: LocalEncryptionService
    private var localEncryptionEnabled = false

    public init(
        directory: LocalDataDirectory,
        encryptionService: LocalEncryptionService = LocalEncryptionService()
    ) {
        self.directory = directory
        self.encryptionService = encryptionService
    }

    public func setLocalEncryptionEnabled(_ enabled: Bool) async {
        localEncryptionEnabled = enabled
    }

    public func save(_ runtime: StageRuntime) async throws {
        try directory.prepare()
        let data = try FocusFlowJSON.encoder.encode(runtime)
        let output = localEncryptionEnabled ? try await encryptionService.encrypt(data) : data
        try output.write(to: activeRuntimeURL, options: [.atomic])
    }

    public func loadActiveRuntime() async throws -> StageRuntime? {
        guard FileManager.default.fileExists(atPath: activeRuntimeURL.path) else {
            return nil
        }
        let rawData = try Data(contentsOf: activeRuntimeURL)
        if LocalEncryptionService.isEncrypted(rawData) {
            let data = try await encryptionService.decryptIfNeeded(rawData)
            return try FocusFlowJSON.decoder.decode(StageRuntime.self, from: data)
        }
        return try CorruptFileRecovery.decodeOrQuarantine(
            StageRuntime.self,
            from: activeRuntimeURL,
            root: directory.root
        )
    }

    public func clearActiveRuntime() async throws {
        if FileManager.default.fileExists(atPath: activeRuntimeURL.path) {
            try FileManager.default.removeItem(at: activeRuntimeURL)
        }
    }

    private var activeRuntimeURL: URL {
        directory.runtime.appendingPathComponent("active_stage.json")
    }
}
