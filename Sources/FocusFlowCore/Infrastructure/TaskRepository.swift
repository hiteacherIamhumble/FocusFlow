import Foundation

public actor LocalTaskRepository: TaskRepositoryProtocol {
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

    public func save(_ task: TaskPlan) async throws {
        try directory.prepare()
        try await write(task, to: fileURL(for: task.id))
    }

    public func getTask(_ taskId: String) async throws -> TaskPlan {
        let url = fileURL(for: taskId)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FocusFlowError.taskNotFound(taskId)
        }
        guard let task = try await decodeLocalFile(TaskPlan.self, from: url) else {
            throw FocusFlowError.taskNotFound(taskId)
        }
        return task
    }

    public func update(_ task: TaskPlan) async throws {
        var updated = task
        updated.updatedAt = Date()
        try await save(updated)
    }

    public func apply(_ update: StageUpdate) async throws -> TaskPlan {
        var task = try await getTask(update.taskId)
        let removed = Set(update.removedStageIds)
        var stages = task.stages.filter { !removed.contains($0.id) }

        switch update.updateScope {
        case .currentStageOnly:
            for updatedStage in update.updatedStages {
                if let index = stages.firstIndex(where: { $0.id == updatedStage.id }) {
                    stages[index] = updatedStage
                } else {
                    stages.append(updatedStage)
                }
            }
        case .remainingStages:
            if let sourceStageId = update.sourceStageId,
               let source = stages.first(where: { $0.id == sourceStageId }) {
                stages.removeAll { $0.order > source.order && ($0.status == .idle || $0.status == .adjusted) }
                stages.append(contentsOf: update.updatedStages)
            } else {
                stages.append(contentsOf: update.updatedStages)
            }
        case .entireTask:
            stages = update.updatedStages
        }

        task.stages = stages
            .sorted { $0.order < $1.order }
            .enumerated()
            .map { index, stage in
                var copy = stage
                copy.order = index + 1
                return copy
            }
        task.estimatedTotalSeconds = task.stages.reduce(0) { $0 + $1.estimatedSeconds }
        task.updatedAt = Date()
        try await save(task)
        return task
    }

    public func listTasks() async throws -> [TaskPlan] {
        try directory.prepare()
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory.tasks,
            includingPropertiesForKeys: nil
        )
        var tasks: [TaskPlan] = []
        for url in urls where url.pathExtension == "json" {
            if let task = try? await decodeLocalFile(TaskPlan.self, from: url) {
                tasks.append(task)
            }
        }
        return tasks.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func deleteTask(_ taskId: String) async throws {
        let url = fileURL(for: taskId)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func fileURL(for taskId: String) -> URL {
        directory.tasks.appendingPathComponent("\(taskId).json")
    }

    private func write<T: Encodable>(_ value: T, to url: URL) async throws {
        let data = try FocusFlowJSON.encoder.encode(value)
        let output = localEncryptionEnabled ? try await encryptionService.encrypt(data) : data
        try output.write(to: url, options: [.atomic])
    }

    private func decodeLocalFile<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T? {
        let rawData = try Data(contentsOf: url)
        if LocalEncryptionService.isEncrypted(rawData) {
            let data = try await encryptionService.decryptIfNeeded(rawData)
            return try FocusFlowJSON.decoder.decode(T.self, from: data)
        }
        return try CorruptFileRecovery.decodeOrQuarantine(T.self, from: url, root: directory.root)
    }
}
