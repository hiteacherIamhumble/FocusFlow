import Foundation

public struct FeedbackOptimizationService: FeedbackOptimizationServiceProtocol {
    private let repository: any TaskRepositoryProtocol
    private let eventBus: AppEventBus
    private let feedbackAgent: FeedbackAgent
    private let optimizationAgent: PlanOptimizationAgent
    private let agentRunLogger: AgentRunLogger
    private let optionsCache: FeedbackOptionsCache

    public init(
        repository: any TaskRepositoryProtocol,
        eventBus: AppEventBus,
        feedbackAgent: FeedbackAgent = FeedbackAgent(),
        optimizationAgent: PlanOptimizationAgent = PlanOptimizationAgent()
    ) {
        self.repository = repository
        self.eventBus = eventBus
        self.feedbackAgent = feedbackAgent
        self.optimizationAgent = optimizationAgent
        self.agentRunLogger = AgentRunLogger(eventBus: eventBus)
        self.optionsCache = FeedbackOptionsCache()
    }

    public func prewarmFeedbackOptions(taskId: String, stageId: String) async throws {
        _ = try await prepareFeedbackOptions(taskId: taskId, stageId: stageId)
    }

    public func prepareFeedbackOptions(taskId: String, stageId: String) async throws -> [FeedbackOption] {
        if let cached = await optionsCache.options(taskId: taskId, stageId: stageId) {
            return cached
        }
        let task = try await repository.getTask(taskId)
        guard let stage = task.stages.first(where: { $0.id == stageId }) else {
            throw FocusFlowError.stageNotFound(stageId)
        }
        let options = try await agentRunLogger.run(
            agentName: "FeedbackAgent",
            purpose: "prepare_feedback_options",
            sourceModule: .module3FeedbackOptimization,
            taskId: task.id,
            stageId: stage.id,
            taskTitle: task.title,
            taskType: task.taskType,
            stageTitle: stage.title,
            stageType: stage.stageType,
            privacyMode: .remoteLLMAllowedForCurrentContext,
            outputSummary: { "options=\($0.map(\.intent.rawValue).joined(separator: ","))" },
            operation: {
                await feedbackAgent.optionsUsingLLM(for: task, stage: stage)
            }
        )
        await optionsCache.store(options, taskId: taskId, stageId: stageId)
        return options
    }

    public func submitFeedback(_ feedback: StageFeedback) async throws -> FeedbackOptimizationResult {
        var task = try await repository.getTask(feedback.taskId)
        let stage = task.stages.first(where: { $0.id == feedback.stageId })
        let counterIntervention = try await updateSevereInterruptionCounters(task: &task, feedback: feedback)
        let taskSnapshot = task
        let optimization = try await agentRunLogger.run(
            agentName: "PlanOptimizationAgent",
            purpose: "optimize_after_stage_feedback",
            sourceModule: .module3FeedbackOptimization,
            taskId: task.id,
            stageId: feedback.stageId,
            taskTitle: task.title,
            taskType: task.taskType,
            stageTitle: stage?.title,
            stageType: stage?.stageType,
            privacyMode: .localOnly,
            outputSummary: { (result: PlanOptimizationRunResult) in
                "stage_update=\(result.update != nil); intervention=\(result.intervention?.interruptionType.rawValue ?? "none")"
            },
            operation: {
                let update = optimizationAgent.optimize(task: taskSnapshot, feedback: feedback)
                let intervention = counterIntervention ?? optimizationAgent.interventionIfNeeded(task: taskSnapshot, feedback: feedback)
                return PlanOptimizationRunResult(update: update, intervention: intervention)
            }
        )
        let update = optimization.update
        let intervention = optimization.intervention
        await eventBus.publish(LearningEvent(
            eventType: .stageFeedbackSubmitted,
            sourceModule: .module3FeedbackOptimization,
            taskId: feedback.taskId,
            stageId: feedback.stageId,
            relatedObjectId: feedback.id,
            taskTitle: task.title,
            taskType: task.taskType,
            stageTitle: stage?.title,
            stageType: stage?.stageType,
            status: feedback.skipped ? "skipped_feedback" : feedback.intent.rawValue,
            tags: ["feedback"],
            metadata: [
                "intent": feedback.intent.rawValue,
                "difficulty": feedback.difficulty?.rawValue ?? "",
                "emotion": feedback.emotionTag?.rawValue ?? "",
                "skipped": "\(feedback.skipped)",
                "has_voice_transcript": "\(feedback.voiceTranscript?.isEmpty == false)",
                "voice_transcript": feedback.voiceTranscript ?? "",
                "other_text": feedback.otherText ?? ""
            ]
        ))
        if let intervention {
            await eventBus.publish(LearningEvent(
                eventType: .interventionTriggered,
                sourceModule: .module3FeedbackOptimization,
                taskId: intervention.taskId,
                stageId: intervention.stageId,
                relatedObjectId: feedback.id,
                taskTitle: task.title,
                taskType: task.taskType,
                status: intervention.urgency.rawValue,
                tags: ["intervention"],
                metadata: ["type": intervention.interruptionType.rawValue]
            ))
        }
        return FeedbackOptimizationResult(
            feedback: feedback,
            stageUpdate: update,
            interventionRequest: intervention,
            lightweightMessage: update == nil ? "Saved. You can keep the next step as-is." : update?.reason
        )
    }

    private func updateSevereInterruptionCounters(task: inout TaskPlan, feedback: StageFeedback) async throws -> InterventionRequest? {
        var metadataChanged = false
        func increment(_ key: String) -> Int {
            let next = (Int(task.metadata[key] ?? "0") ?? 0) + 1
            task.metadata[key] = "\(next)"
            metadataChanged = true
            return next
        }

        let incompleteStageCount: Int
        if feedback.intent == .wantToQuit || feedback.skipped || feedback.difficulty == .tooHard {
            incompleteStageCount = increment("severe_incomplete_stage_count")
        } else {
            incompleteStageCount = Int(task.metadata["severe_incomplete_stage_count"] ?? "0") ?? 0
        }
        let wantQuitCount = feedback.intent == .wantToQuit
            ? increment("want_to_quit_stage_\(feedback.stageId)")
            : (Int(task.metadata["want_to_quit_stage_\(feedback.stageId)"] ?? "0") ?? 0)
        let overloadCount = (feedback.emotionTag == .overwhelmed || feedback.emotionTag == .frustrated)
            ? increment("emotional_overload_count")
            : (Int(task.metadata["emotional_overload_count"] ?? "0") ?? 0)

        if metadataChanged {
            try await repository.update(task)
        }

        guard incompleteStageCount >= 2 || wantQuitCount >= 2 || overloadCount >= 2 else {
            return nil
        }
        let type: InterruptionType = wantQuitCount >= 2 ? .activeQuit : .emotionalOverload
        return InterventionRequest(
            taskId: task.id,
            stageId: feedback.stageId,
            interruptionType: type,
            urgency: .high,
            lastFeedback: feedback,
            suggestedTone: .gentleDirect
        )
    }

    public func handleTimeoutDifficulty(taskId: String, stageId: String, runtime: StageRuntime) async throws -> DifficultyPrompt {
        let task = try await repository.getTask(taskId)
        guard let stage = task.stages.first(where: { $0.id == stageId }) else {
            throw FocusFlowError.stageNotFound(stageId)
        }
        return feedbackAgent.difficultyPrompt(for: stage)
    }

    public func generateStuckHelp(_ request: StuckHelpRequest) async throws -> StuckHelpResponse {
        await eventBus.publish(LearningEvent(
            eventType: .stuckHelpRequested,
            sourceModule: .module3FeedbackOptimization,
            taskId: request.taskId,
            stageId: request.stageId,
            taskTitle: request.taskTitle,
            stageTitle: request.stageTitle,
            status: "stuck_help_requested",
            plannedDurationSeconds: request.plannedSeconds,
            tags: ["stuck_help"],
            metadata: [
                "trigger": request.trigger.rawValue,
                "elapsed_seconds": "\(request.elapsedSeconds)"
            ]
        ))
        return try await agentRunLogger.run(
            agentName: "FeedbackAgent",
            purpose: "generate_stuck_help",
            sourceModule: .module3FeedbackOptimization,
            taskId: request.taskId,
            stageId: request.stageId,
            taskTitle: request.taskTitle,
            stageTitle: request.stageTitle,
            privacyMode: .remoteLLMAllowedForCurrentContext,
            outputSummary: { "actions=\($0.actions.map(\.actionType.rawValue).joined(separator: ","))" },
            operation: {
                await feedbackAgent.stuckHelpUsingLLM(for: request)
            }
        )
    }
}

private struct PlanOptimizationRunResult: Sendable {
    let update: StageUpdate?
    let intervention: InterventionRequest?
}

private actor FeedbackOptionsCache {
    private var values: [String: [FeedbackOption]] = [:]

    func options(taskId: String, stageId: String) -> [FeedbackOption]? {
        values[key(taskId: taskId, stageId: stageId)]
    }

    func store(_ options: [FeedbackOption], taskId: String, stageId: String) {
        values[key(taskId: taskId, stageId: stageId)] = options
    }

    private func key(taskId: String, stageId: String) -> String {
        "\(taskId)|\(stageId)"
    }
}
