import Foundation

public struct TaskClosureService: TaskClosureServiceProtocol {
    private let repository: any TaskRepositoryProtocol
    private let dataCenter: any DataCenterServiceProtocol
    private let eventBus: AppEventBus
    private let emotionAgent: EmotionSupportAgent
    private let agentRunLogger: AgentRunLogger

    public init(
        repository: any TaskRepositoryProtocol,
        dataCenter: any DataCenterServiceProtocol,
        eventBus: AppEventBus,
        emotionAgent: EmotionSupportAgent = EmotionSupportAgent()
    ) {
        self.repository = repository
        self.dataCenter = dataCenter
        self.eventBus = eventBus
        self.emotionAgent = emotionAgent
        self.agentRunLogger = AgentRunLogger(eventBus: eventBus)
    }

    public func presentCompletion(taskId: String) async throws -> TaskClosureSummary {
        var task = try await repository.getTask(taskId)
        task.status = .completed
        try await repository.update(task)
        let events = try await dataCenter.queryHistory(HistoryQuery(keyword: task.title))
        let focusSeconds = events.filter { $0.taskId == taskId }.reduce(0) { $0 + $1.totalFocusSeconds }
        let summary = await makeSummary(task: task, type: .completed, focusSeconds: focusSeconds, reason: nil)
        try await dataCenter.saveClosureSummary(summary)
        await publishClosure(summary, task: task, eventType: .taskCompleted)
        return summary
    }

    public func presentGracefulPause(taskId: String, reason: String?) async throws -> TaskClosureSummary {
        var task = try await repository.getTask(taskId)
        task.status = .gracefullyPaused
        try await repository.update(task)
        let summary = await makeSummary(task: task, type: .gracefullyPaused, focusSeconds: 0, reason: reason)
        try await dataCenter.saveClosureSummary(summary)
        await publishClosure(summary, task: task, eventType: .taskGracefullyPaused)
        return summary
    }

    public func presentAbandonment(taskId: String, reason: String?) async throws -> TaskClosureSummary {
        var task = try await repository.getTask(taskId)
        task.status = .abandoned
        task.stages = task.stages.map { stage in
            guard stage.status == .idle || stage.status == .running || stage.status == .paused || stage.status == .overtime || stage.status == .adjusted else {
                return stage
            }
            var copy = stage
            copy.status = .abandoned
            return copy
        }
        try await repository.update(task)
        let events = try await dataCenter.queryHistory(HistoryQuery(keyword: task.title))
        let focusSeconds = events.filter { $0.taskId == taskId }.reduce(0) { $0 + $1.totalFocusSeconds }
        let summary = await makeSummary(task: task, type: .abandoned, focusSeconds: focusSeconds, reason: reason)
        try await dataCenter.saveClosureSummary(summary)
        await publishClosure(summary, task: task, eventType: .taskAbandoned, reason: reason)
        return summary
    }

    public func markEmotion(summary: TaskClosureSummary, emotion: EmotionTag) async throws {
        let task = try await repository.getTask(summary.taskId)
        await eventBus.publish(LearningEvent(
            eventType: .emotionMarked,
            sourceModule: .module4ClosureEmotion,
            taskId: task.id,
            relatedObjectId: summary.id,
            taskTitle: task.title,
            taskType: task.taskType,
            status: emotion.rawValue,
            tags: ["closure", "emotion"],
            metadata: [
                "closure_id": summary.id,
                "emotion": emotion.rawValue,
                "closure_type": summary.closureType.rawValue
            ]
        ))
    }

    public func submitReview(summary: TaskClosureSummary, item: ReviewItem, confirmed: Bool) async throws {
        let task = try await repository.getTask(summary.taskId)
        await eventBus.publish(LearningEvent(
            eventType: .reviewSubmitted,
            sourceModule: .module4ClosureEmotion,
            taskId: task.id,
            relatedObjectId: summary.id,
            taskTitle: task.title,
            taskType: task.taskType,
            status: confirmed ? "agreed" : "not_quite",
            tags: ["closure", "review"],
            metadata: [
                "closure_id": summary.id,
                "review_item_id": item.id,
                "review_type": item.type.rawValue,
                "confirmed": "\(confirmed)",
                "text": item.text
            ]
        ))
    }

    public func skipReview(summary: TaskClosureSummary) async throws {
        let task = try await repository.getTask(summary.taskId)
        await eventBus.publish(LearningEvent(
            eventType: .reviewSubmitted,
            sourceModule: .module4ClosureEmotion,
            taskId: task.id,
            relatedObjectId: summary.id,
            taskTitle: task.title,
            taskType: task.taskType,
            status: "skipped",
            tags: ["closure", "review"],
            metadata: [
                "closure_id": summary.id,
                "skipped": "true"
            ]
        ))
    }

    public func archiveTask(_ summary: TaskClosureSummary) async throws {
        var task = try await repository.getTask(summary.taskId)
        task.status = .archived
        try await repository.update(task)
        await eventBus.publish(LearningEvent(
            eventType: .taskArchived,
            sourceModule: .module4ClosureEmotion,
            taskId: task.id,
            relatedObjectId: summary.id,
            taskTitle: task.title,
            taskType: task.taskType,
            status: task.status.rawValue,
            plannedDurationSeconds: task.estimatedTotalSeconds,
            tags: ["archive"]
        ))
    }

    private func makeSummary(task: TaskPlan, type: TaskClosureType, focusSeconds: Int, reason: String?) async -> TaskClosureSummary {
        let loggedCopy = try? await agentRunLogger.run(
            agentName: "EmotionSupportAgent",
            purpose: "generate_closure_copy",
            sourceModule: .module4ClosureEmotion,
            taskId: task.id,
            taskTitle: task.title,
            taskType: task.taskType,
            privacyMode: .remoteLLMAllowedForCurrentContext,
            outputSummary: { "review_items=\($0.reviewItems.count); has_encouragement=\($0.encouragementText?.isEmpty == false)" },
            operation: {
                await emotionAgent.closureCopy(for: task, focusSeconds: focusSeconds, closureType: type, reason: reason)
            }
        )
        let copy: EmotionClosureCopy
        if let loggedCopy {
            copy = loggedCopy
        } else {
            copy = await emotionAgent.closureCopy(for: task, focusSeconds: focusSeconds, closureType: type, reason: reason)
        }
        return TaskClosureSummary(
            taskId: task.id,
            closureType: type,
            totalPlannedSeconds: task.estimatedTotalSeconds,
            totalFocusSeconds: focusSeconds,
            completedStageCount: task.stages.filter { $0.status == .completed }.count,
            skippedStageCount: task.stages.filter { $0.status == .skipped }.count,
            abandonedStageCount: task.stages.filter { $0.status == .abandoned }.count,
            keyBreakthroughs: task.stages.filter { $0.status == .completed }.prefix(3).map { $0.title },
            encouragementText: copy.encouragementText,
            soothingText: copy.soothingText,
            reviewItems: copy.reviewItems,
            emotionTag: nil
        )
    }

    private func publishClosure(_ summary: TaskClosureSummary, task: TaskPlan, eventType: LearningEventType, reason: String? = nil) async {
        var metadata = [
            "completed_stage_count": "\(summary.completedStageCount)",
            "skipped_stage_count": "\(summary.skippedStageCount)",
            "abandoned_stage_count": "\(summary.abandonedStageCount)"
        ]
        if let reason, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metadata["reason"] = reason
        }
        await eventBus.publish(LearningEvent(
            eventType: eventType,
            sourceModule: .module4ClosureEmotion,
            taskId: task.id,
            relatedObjectId: summary.id,
            taskTitle: task.title,
            taskType: task.taskType,
            status: summary.closureType.rawValue,
            plannedDurationSeconds: summary.totalPlannedSeconds,
            actualFocusSeconds: summary.totalFocusSeconds,
            tags: ["closure"],
            metadata: metadata
        ))
    }
}
