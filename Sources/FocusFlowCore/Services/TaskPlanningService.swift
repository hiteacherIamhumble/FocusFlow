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
        guard !draft.clarificationQuestions.isEmpty || !draft.task.stages.isEmpty else {
            throw FocusFlowError.nonEducationalTask
        }
        return draft
    }

    public func continuePlanning(context: TaskPlanningContext, agentContext: AgentContext?) async throws -> TaskPlanDraft {
        let privacyMode: PrivacyMode = agentContext?.privacyMode == .profileDisabled ? .profileDisabled : .remoteLLMAllowedForCurrentContext
        let draft = try await agentRunLogger.run(
            agentName: "TaskBreakdownAgent",
            purpose: "continue_task_planning",
            sourceModule: .module1TaskPlanning,
            privacyMode: privacyMode,
            outputSummary: { draft in
                "stages=\(draft.task.stages.count); questions=\(draft.clarificationQuestions.count); mode=\(draft.task.metadata["planning_mode"] ?? "unknown")"
            },
            operation: {
                await agent.continuePlanningUsingLLM(
                    context: context,
                    agentContext: agentContext,
                    privacyMode: privacyMode
                )
            }
        )
        guard !draft.clarificationQuestions.isEmpty || !draft.task.stages.isEmpty else {
            throw FocusFlowError.invalidState("Planning did not produce a usable plan or follow-up question.")
        }
        return draft
    }

    public func acceptDraft(_ draft: TaskPlanDraft, clarificationAnswer: String? = nil) async throws -> TaskPlan {
        guard !draft.task.stages.isEmpty else {
            throw FocusFlowError.invalidState("The plan is not ready yet. Answer the follow-up question first.")
        }
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
        try await refinePlan(task, userInstruction: userInstruction, agentContext: nil)
    }

    public func refinePlan(_ task: TaskPlan, userInstruction: String, agentContext: AgentContext?) async throws -> TaskPlan {
        let privacyMode: PrivacyMode = agentContext?.privacyMode == .profileDisabled ? .profileDisabled : .remoteLLMAllowedForCurrentContext
        let refined = try await agentRunLogger.run(
            agentName: "TaskBreakdownAgent",
            purpose: "refine_task_plan",
            sourceModule: .module1TaskPlanning,
            privacyMode: privacyMode,
            outputSummary: { task in
                "stages=\(task.stages.count); mode=\(task.metadata["planning_mode"] ?? "unknown"); refinement=\(task.metadata["last_refinement"] ?? "unknown")"
            },
            operation: {
                await agent.refineUsingLLM(
                    task,
                    instruction: userInstruction,
                    agentContext: agentContext,
                    privacyMode: privacyMode
                )
            }
        )
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
            metadata: [
                "instruction": userInstruction,
                "planning_mode": refined.metadata["planning_mode"] ?? "unknown",
                "agent_response": refined.metadata["agent_response"] ?? "",
                "fallback_reason": refined.metadata["agent_fallback_reason"] ?? ""
            ]
        ))
        return refined
    }

    public func regeneratePlan(_ task: TaskPlan, agentContext: AgentContext?) async throws -> TaskPlan {
        let regenerated = try await agentRunLogger.run(
            agentName: "TaskBreakdownAgent",
            purpose: "regenerate_task_plan",
            sourceModule: .module1TaskPlanning,
            privacyMode: agentContext?.privacyMode == .profileDisabled ? .profileDisabled : .remoteLLMAllowedForCurrentContext,
            outputSummary: { task in
                "stages=\(task.stages.count); mode=\(task.metadata["planning_mode"] ?? "unknown")"
            },
            operation: {
                await agent.refineUsingLLM(
                    task,
                    instruction: "regenerate",
                    agentContext: agentContext,
                    privacyMode: agentContext?.privacyMode == .profileDisabled ? .profileDisabled : .remoteLLMAllowedForCurrentContext
                )
            }
        )
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
                "planning_mode": regenerated.metadata["planning_mode"] ?? "unknown",
                "agent_response": regenerated.metadata["agent_response"] ?? "",
                "fallback_reason": regenerated.metadata["agent_fallback_reason"] ?? ""
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
        task.metadata["last_manual_edit"] = "edit_stage"
        task.metadata.removeValue(forKey: "agent_response")
        task.metadata.removeValue(forKey: "agent_fallback_reason")
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

    public func insertStage(taskId: String, beforeStageId: String?, patch: StagePlanPatch) async throws -> TaskPlan {
        var task = try await repository.getTask(taskId)
        let insertIndex: Int
        if let beforeStageId, let index = task.stages.firstIndex(where: { $0.id == beforeStageId }) {
            insertIndex = index
        } else {
            insertIndex = task.stages.count
        }
        let title = trimmedNonEmpty(patch.title) ?? "New learning step"
        let instruction = trimmedNonEmpty(patch.instruction) ?? "Describe the next visible action."
        let criteria = trimmedNonEmpty(patch.completionCriteria) ?? "The visible action is done."
        let inserted = StagePlan(
            taskId: task.id,
            order: insertIndex + 1,
            title: title,
            instruction: instruction,
            completionCriteria: criteria,
            stageType: patch.stageType ?? .other,
            estimatedSeconds: patch.estimatedSeconds ?? 300,
            createdBy: .module1TaskPlanning,
            metadata: ["manual_edit": "insert_stage"]
        )
        task.stages.insert(inserted, at: insertIndex)
        normalizeStageOrderAndDuration(&task)
        task.metadata["last_manual_edit"] = "insert_stage"
        task.metadata.removeValue(forKey: "agent_response")
        task.metadata.removeValue(forKey: "agent_fallback_reason")
        try await repository.update(task)
        await eventBus.publish(LearningEvent(
            eventType: .taskPlanUpdated,
            sourceModule: .module1TaskPlanning,
            taskId: task.id,
            stageId: inserted.id,
            taskTitle: task.title,
            taskType: task.taskType,
            stageTitle: title,
            stageType: inserted.stageType,
            status: task.status.rawValue,
            plannedDurationSeconds: task.estimatedTotalSeconds,
            tags: ["plan_edit"],
            metadata: [
                "instruction": "manual_insert_stage",
                "insert_before_stage_id": beforeStageId ?? ""
            ]
        ))
        return task
    }

    public func deleteStage(taskId: String, stageId: String) async throws -> TaskPlan {
        var task = try await repository.getTask(taskId)
        guard task.stages.count > 1 else {
            throw FocusFlowError.invalidState("Keep at least one stage in the plan.")
        }
        guard let index = task.stages.firstIndex(where: { $0.id == stageId }) else {
            throw FocusFlowError.stageNotFound(stageId)
        }
        let removed = task.stages.remove(at: index)
        normalizeStageOrderAndDuration(&task)
        task.metadata["last_manual_edit"] = "delete_stage"
        task.metadata.removeValue(forKey: "agent_response")
        task.metadata.removeValue(forKey: "agent_fallback_reason")
        try await repository.update(task)
        await eventBus.publish(LearningEvent(
            eventType: .taskPlanUpdated,
            sourceModule: .module1TaskPlanning,
            taskId: task.id,
            stageId: removed.id,
            taskTitle: task.title,
            taskType: task.taskType,
            stageTitle: removed.title,
            stageType: removed.stageType,
            status: task.status.rawValue,
            plannedDurationSeconds: task.estimatedTotalSeconds,
            tags: ["plan_edit"],
            metadata: [
                "instruction": "manual_delete_stage",
                "deleted_stage_order": "\(removed.order)"
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

    private func normalizeStageOrderAndDuration(_ task: inout TaskPlan) {
        task.stages = task.stages.enumerated().map { offset, stage in
            var copy = stage
            copy.order = offset + 1
            copy.estimatedSeconds = min(1_500, max(offset == 0 ? 120 : 60, copy.estimatedSeconds))
            if offset == 0 {
                copy.estimatedSeconds = min(300, copy.estimatedSeconds)
            }
            return copy
        }
        task.estimatedTotalSeconds = task.stages.reduce(0) { $0 + $1.estimatedSeconds }
        task.updatedAt = Date()
        if task.stages.count > 15 {
            task.metadata["stage_count_warning"] = "true"
        } else {
            task.metadata.removeValue(forKey: "stage_count_warning")
        }
    }
}
