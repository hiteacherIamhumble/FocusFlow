import Foundation

public struct TaskPlanningService: TaskPlanningServiceProtocol {
    private let agent: TaskBreakdownAgent
    private let repository: any TaskRepositoryProtocol
    private let eventBus: AppEventBus
    private let agentRunLogger: AgentRunLogger

    public init(
        agent: TaskBreakdownAgent = TaskBreakdownAgent(),
        repository: any TaskRepositoryProtocol,
        eventBus: AppEventBus
    ) {
        self.agent = agent
        self.repository = repository
        self.eventBus = eventBus
        self.agentRunLogger = AgentRunLogger(eventBus: eventBus)
    }

    public func createDraft(from input: String, agentContext: AgentContext?) async throws -> TaskPlanDraft {
        let privacyMode: PrivacyMode = agentContext?.privacyMode == .profileDisabled ? .profileDisabled : .remoteLLMAllowedForCurrentContext
        let draft = try await agentRunLogger.run(
            agentName: "TaskBreakdownAgent",
            purpose: "create_task_plan_draft",
            sourceModule: .module1TaskPlanning,
            privacyMode: privacyMode,
            outputSummary: { draft in
                "stages=\(draft.task.stages.count); confidence=\(String(format: "%.2f", draft.confidence)); mode=\(draft.task.metadata["planning_mode"] ?? "unknown")"
            },
            operation: {
                await agent.makeDraftUsingLLM(
                    from: TaskInputRequest(
                        rawInput: input,
                        userProfileSnapshot: agentContext?.userProfileSnapshot,
                        agentContext: agentContext
                    ),
                    privacyMode: privacyMode
                )
            }
        )
        guard !draft.task.stages.isEmpty else {
            throw FocusFlowError.nonEducationalTask
        }
        return draft
    }

    public func acceptDraft(_ draft: TaskPlanDraft, clarificationAnswer: String? = nil) async throws -> TaskPlan {
        var task = draft.task
        if let clarificationAnswer, !clarificationAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            task.metadata["clarification_answer"] = clarificationAnswer
        }
        try await repository.save(task)
        await eventBus.publish(LearningEvent(
            eventType: .taskCreated,
            sourceModule: .module1TaskPlanning,
            taskId: task.id,
            taskTitle: task.title,
            taskType: task.taskType,
            status: task.status.rawValue,
            plannedDurationSeconds: task.estimatedTotalSeconds,
            tags: [task.taskType.rawValue],
            metadata: [
                "confidence": String(format: "%.2f", draft.confidence),
                "clarification_count": "\(draft.clarificationQuestions.count)",
                "clarification_answer": clarificationAnswer ?? ""
            ]
        ))
        return task
    }

    public func createPlan(from input: String, context: UserProfileSnapshot?) async throws -> TaskPlan {
        try await createPlan(
            from: input,
            agentContext: context.map {
                AgentContext(
                    userProfileSnapshot: $0,
                    recentStatsSummary: nil,
                    recentSimilarTaskNotes: [],
                    privacyMode: .localOnly
                )
            }
        )
    }

    public func createPlan(from input: String, agentContext: AgentContext?) async throws -> TaskPlan {
        let draft = try await createDraft(from: input, agentContext: agentContext)
        return try await acceptDraft(draft, clarificationAnswer: nil)
    }

    public func refinePlan(_ task: TaskPlan, userInstruction: String) async throws -> TaskPlan {
        let refined = agent.refine(task, instruction: userInstruction)
        try await repository.update(refined)
        await eventBus.publish(LearningEvent(
            eventType: .taskPlanUpdated,
            sourceModule: .module1TaskPlanning,
            taskId: refined.id,
            taskTitle: refined.title,
            taskType: refined.taskType,
            status: refined.status.rawValue,
            plannedDurationSeconds: refined.estimatedTotalSeconds,
            tags: [refined.taskType.rawValue],
            metadata: ["instruction": userInstruction]
        ))
        return refined
    }

    public func regeneratePlan(_ task: TaskPlan, agentContext: AgentContext?) async throws -> TaskPlan {
        let draft = try await createDraft(from: task.originalInput, agentContext: agentContext)
        var regenerated = TaskPlan(
            id: task.id,
            originalInput: task.originalInput,
            title: draft.task.title,
            taskType: draft.task.taskType,
            status: task.status,
            createdAt: task.createdAt,
            updatedAt: Date(),
            deadline: task.deadline,
            estimatedTotalSeconds: draft.task.estimatedTotalSeconds,
            stages: draft.task.stages.enumerated().map { offset, stage in
                StagePlan(
                    taskId: task.id,
                    order: offset + 1,
                    title: stage.title,
                    instruction: stage.instruction,
                    completionCriteria: stage.completionCriteria,
                    stageType: stage.stageType,
                    estimatedSeconds: stage.estimatedSeconds,
                    status: .idle,
                    createdBy: .module1TaskPlanning,
                    metadata: ["regenerated_from": stage.id]
                )
            },
            metadata: task.metadata.merging([
                "last_refinement": "regenerate",
                "regenerated_at": ISO8601DateFormatter().string(from: Date()),
                "planning_mode": draft.task.metadata["planning_mode"] ?? task.metadata["planning_mode"] ?? "local_rules"
            ]) { _, new in new }
        )
        regenerated.estimatedTotalSeconds = regenerated.stages.reduce(0) { $0 + $1.estimatedSeconds }
        try await repository.update(regenerated)
        await eventBus.publish(LearningEvent(
            eventType: .taskPlanUpdated,
            sourceModule: .module1TaskPlanning,
            taskId: regenerated.id,
            taskTitle: regenerated.title,
            taskType: regenerated.taskType,
            status: regenerated.status.rawValue,
            plannedDurationSeconds: regenerated.estimatedTotalSeconds,
            tags: [regenerated.taskType.rawValue],
            metadata: [
                "instruction": "regenerate",
                "confidence": String(format: "%.2f", draft.confidence),
                "clarification_count": "\(draft.clarificationQuestions.count)"
            ]
        ))
        return regenerated
    }

    public func updateStage(taskId: String, stageId: String, patch: StagePlanPatch) async throws -> TaskPlan {
        var task = try await repository.getTask(taskId)
        guard let index = task.stages.firstIndex(where: { $0.id == stageId }) else {
            throw FocusFlowError.stageNotFound(stageId)
        }
        let changedFields = patch.changedFields
        guard !changedFields.isEmpty else { return task }

        if let title = trimmedNonEmpty(patch.title) {
            task.stages[index].title = title
        }
        if let instruction = trimmedNonEmpty(patch.instruction) {
            task.stages[index].instruction = instruction
        }
        if let completionCriteria = trimmedNonEmpty(patch.completionCriteria) {
            task.stages[index].completionCriteria = completionCriteria
        }
        if let stageType = patch.stageType {
            task.stages[index].stageType = stageType
        }
        if let estimatedSeconds = patch.estimatedSeconds {
            let lowerBound = task.stages[index].order == 1 ? 120 : 60
            task.stages[index].estimatedSeconds = min(1_500, max(lowerBound, estimatedSeconds))
        }

        task.estimatedTotalSeconds = task.stages.reduce(0) { $0 + $1.estimatedSeconds }
        task.metadata["last_stage_edit_at"] = ISO8601DateFormatter().string(from: Date())
        if task.stages.count > 15 {
            task.metadata["stage_count_warning"] = "true"
        } else {
            task.metadata.removeValue(forKey: "stage_count_warning")
        }
        try await repository.update(task)
        await eventBus.publish(LearningEvent(
            eventType: .taskPlanUpdated,
            sourceModule: .module1TaskPlanning,
            taskId: task.id,
            stageId: stageId,
            taskTitle: task.title,
            taskType: task.taskType,
            stageTitle: task.stages[index].title,
            stageType: task.stages[index].stageType,
            status: task.status.rawValue,
            plannedDurationSeconds: task.estimatedTotalSeconds,
            tags: ["plan_edit"],
            metadata: [
                "instruction": "manual_stage_edit",
                "changed_fields": changedFields.joined(separator: ","),
                "stage_seconds": "\(task.stages[index].estimatedSeconds)",
                "stage_count_warning": task.metadata["stage_count_warning"] ?? "false"
            ]
        ))
        return task
    }

    public func confirmPlan(_ task: TaskPlan) async throws {
        var confirmed = task
        confirmed.status = .planned
        confirmed.updatedAt = Date()
        try await repository.update(confirmed)
        await eventBus.publish(LearningEvent(
            eventType: .taskPlanConfirmed,
            sourceModule: .module1TaskPlanning,
            taskId: confirmed.id,
            taskTitle: confirmed.title,
            taskType: confirmed.taskType,
            status: confirmed.status.rawValue,
            plannedDurationSeconds: confirmed.estimatedTotalSeconds,
            tags: [confirmed.taskType.rawValue]
        ))
    }

    private func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
