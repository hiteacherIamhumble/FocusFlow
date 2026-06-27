import Foundation

public struct AgentRunLogger: Sendable {
    private let eventBus: AppEventBus

    public init(eventBus: AppEventBus) {
        self.eventBus = eventBus
    }

    @discardableResult
    public func run<T>(
        agentName: String,
        purpose: String,
        sourceModule: SourceModule,
        taskId: String? = nil,
        stageId: String? = nil,
        taskTitle: String? = nil,
        taskType: EducationTaskType? = nil,
        stageTitle: String? = nil,
        stageType: StageType? = nil,
        privacyMode: PrivacyMode,
        outputSummary: @Sendable (T) -> String,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        let runId = FocusFlowID.make("agent_run")
        let startedAt = Date()
        await eventBus.publish(LearningEvent(
            eventType: .agentRunStarted,
            sourceModule: sourceModule,
            taskId: taskId,
            stageId: stageId,
            relatedObjectId: runId,
            taskTitle: taskTitle,
            taskType: taskType,
            stageTitle: stageTitle,
            stageType: stageType,
            status: "started",
            tags: ["agent", agentName],
            metadata: [
                "agent_name": agentName,
                "purpose": purpose,
                "privacy_mode": privacyMode.rawValue
            ]
        ))
        do {
            let result = try await operation()
            let durationMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1000)
            await eventBus.publish(LearningEvent(
                eventType: .agentRunCompleted,
                sourceModule: sourceModule,
                taskId: taskId,
                stageId: stageId,
                relatedObjectId: runId,
                taskTitle: taskTitle,
                taskType: taskType,
                stageTitle: stageTitle,
                stageType: stageType,
                status: "completed",
                tags: ["agent", agentName],
                metadata: [
                    "agent_name": agentName,
                    "purpose": purpose,
                    "privacy_mode": privacyMode.rawValue,
                    "duration_ms": "\(durationMilliseconds)",
                    "output_summary": outputSummary(result).agentLogSummary
                ]
            ))
            return result
        } catch {
            let durationMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1000)
            await eventBus.publish(LearningEvent(
                eventType: .agentRunFailed,
                sourceModule: sourceModule,
                taskId: taskId,
                stageId: stageId,
                relatedObjectId: runId,
                taskTitle: taskTitle,
                taskType: taskType,
                stageTitle: stageTitle,
                stageType: stageType,
                status: "failed",
                tags: ["agent", agentName],
                metadata: [
                    "agent_name": agentName,
                    "purpose": purpose,
                    "privacy_mode": privacyMode.rawValue,
                    "duration_ms": "\(durationMilliseconds)",
                    "error": String(describing: type(of: error)).agentLogSummary
                ]
            ))
            throw error
        }
    }
}

private extension String {
    var agentLogSummary: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 160 else { return trimmed }
        return String(trimmed.prefix(157)) + "..."
    }
}
