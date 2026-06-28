import Foundation

public struct PlanOptimizationAgent: Sendable {
    private let llmClient: (any LLMClient)?

    public init(llmClient: (any LLMClient)? = nil) {
        self.llmClient = llmClient
    }

    public func optimizeUsingLLM(task: TaskPlan, feedback: StageFeedback) async -> StageUpdate? {
        guard shouldAttemptOptimization(for: feedback) else { return nil }
        if let llmClient {
            do {
                if let update = try await optimizeWithLLM(task: task, feedback: feedback, llmClient: llmClient) {
                    return update
                }
            } catch {
                // Fall back to local rules below.
            }
        }
        return optimize(task: task, feedback: feedback)
    }

    public func optimize(task: TaskPlan, feedback: StageFeedback) -> StageUpdate? {
        guard let source = task.stages.first(where: { $0.id == feedback.stageId }) else { return nil }
        let remaining = task.stages.filter { $0.order > source.order && $0.status == .idle }
        guard !remaining.isEmpty || feedback.intent == .tooHard else { return nil }

        switch feedback.intent {
        case .tooHard, .unclearInstruction:
            let split = split(stage: source, taskId: task.id)
            return StageUpdate(
                taskId: task.id,
                sourceStageId: source.id,
                updateScope: .currentStageOnly,
                updatedStages: split,
                removedStageIds: [source.id],
                reason: "The current step felt too large, so it was split into smaller actions.",
                requiresUserConfirmation: true
            )
        case .needMoreTime:
            let updated = remaining.prefix(3).map { stage in
                var copy = stage
                copy.estimatedSeconds = min(1_500, copy.estimatedSeconds + 300)
                copy.createdBy = .module3FeedbackOptimization
                return copy
            }
            guard !updated.isEmpty else { return nil }
            return StageUpdate(
                taskId: task.id,
                sourceStageId: source.id,
                updateScope: .remainingStages,
                updatedStages: Array(updated),
                reason: "Similar upcoming steps now have a little more room.",
                requiresUserConfirmation: true
            )
        case .distracted, .needBreak:
            let breakStage = StagePlan(
                taskId: task.id,
                order: source.order + 1,
                title: "Reset for three minutes",
                instruction: "Take a short reset: stand up, drink water, or breathe. Come back gently.",
                completionCriteria: "Three minutes pass and you choose the next step.",
                stageType: .breakTime,
                estimatedSeconds: 180,
                createdBy: .module3FeedbackOptimization,
                parentStageId: source.id
            )
            return StageUpdate(
                taskId: task.id,
                sourceStageId: source.id,
                updateScope: .remainingStages,
                updatedStages: [breakStage] + remaining,
                reason: "A short reset was added before continuing.",
                requiresUserConfirmation: true
            )
        case .wantToQuit:
            return nil
        default:
            return nil
        }
    }

    public func interventionIfNeeded(task: TaskPlan, feedback: StageFeedback) -> InterventionRequest? {
        guard feedback.intent == .wantToQuit || feedback.emotionTag == .overwhelmed || feedback.emotionTag == .frustrated else {
            return nil
        }
        return InterventionRequest(
            taskId: task.id,
            stageId: feedback.stageId,
            interruptionType: feedback.intent == .wantToQuit ? .activeQuit : .emotionalOverload,
            urgency: .high,
            lastFeedback: feedback,
            suggestedTone: .gentleDirect
        )
    }

    private func shouldAttemptOptimization(for feedback: StageFeedback) -> Bool {
        if feedback.skipped || feedback.intent == .skippedFeedback || feedback.intent == .completed {
            return false
        }
        switch feedback.intent {
        case .tooHard, .unclearInstruction, .needMoreTime, .distracted, .needBreak, .other:
            return true
        default:
            return false
        }
    }

    private func optimizeWithLLM(
        task: TaskPlan,
        feedback: StageFeedback,
        llmClient: any LLMClient
    ) async throws -> StageUpdate? {
        guard let source = task.stages.first(where: { $0.id == feedback.stageId }) else { return nil }
        let remaining = task.stages.filter { $0.order > source.order && $0.status == .idle }
        let content = try await llmClient.complete(
            messages: [
                LLMMessage(role: "system", content: planOptimizationSystemPrompt),
                LLMMessage(role: "user", content: planOptimizationUserPrompt(
                    task: task,
                    source: source,
                    remaining: remaining,
                    feedback: feedback
                ))
            ],
            privacyMode: .remoteLLMAllowedForCurrentContext,
            responseFormat: .jsonObject
        )
        return try decodeLLMStageUpdate(content, task: task, source: source, remaining: remaining, feedback: feedback)
    }

    private func split(stage: StagePlan, taskId: String) -> [StagePlan] {
        let firstSeconds = min(300, max(120, stage.estimatedSeconds / 2))
        return [
            StagePlan(
                taskId: taskId,
                order: stage.order,
                title: "Open: \(stage.title)",
                instruction: "Start only the first visible piece: \(stage.instruction)",
                completionCriteria: "The first piece is visible or started.",
                stageType: stage.stageType,
                estimatedSeconds: firstSeconds,
                status: .adjusted,
                createdBy: .module3FeedbackOptimization,
                parentStageId: stage.id
            ),
            StagePlan(
                taskId: taskId,
                order: stage.order + 1,
                title: "Continue: \(stage.title)",
                instruction: stage.instruction,
                completionCriteria: stage.completionCriteria,
                stageType: stage.stageType,
                estimatedSeconds: max(180, stage.estimatedSeconds - firstSeconds),
                status: .adjusted,
                createdBy: .module3FeedbackOptimization,
                parentStageId: stage.id
            )
        ]
    }

    private func decodeLLMStageUpdate(
        _ content: String,
        task: TaskPlan,
        source: StagePlan,
        remaining: [StagePlan],
        feedback: StageFeedback
    ) throws -> StageUpdate? {
        let decoded = try FocusFlowJSON.decoder.decode(LLMStageOptimization.self, from: Data(content.utf8))
        guard decoded.shouldUpdate, !decoded.updatedStages.isEmpty else { return nil }

        let scope = StageUpdateScope(rawValue: decoded.updateScope) ?? inferredScope(for: feedback)
        let mappedStages = decoded.updatedStages.enumerated().map { index, stage in
            let order: Int
            switch scope {
            case .currentStageOnly:
                order = source.order + index
            case .remainingStages, .entireTask:
                order = source.order + 1 + index
            }
            return StagePlan(
                taskId: task.id,
                order: order,
                title: stage.title.cleanOptimizationText(fallback: "Smaller next step"),
                instruction: stage.instruction.cleanOptimizationText(fallback: "Do one visible part of this step."),
                completionCriteria: stage.completionCriteria.cleanOptimizationText(fallback: "One visible part is done."),
                stageType: StageType(rawValue: stage.stageType) ?? source.stageType,
                estimatedSeconds: min(1_500, max(60, stage.estimatedSeconds)),
                status: .adjusted,
                createdBy: .module3FeedbackOptimization,
                parentStageId: source.id
            )
        }

        let removedStageIds: [String]
        switch scope {
        case .currentStageOnly:
            removedStageIds = [source.id]
        case .remainingStages:
            removedStageIds = remaining.map(\.id)
        case .entireTask:
            removedStageIds = task.stages.filter { $0.status == .idle }.map(\.id)
        }

        let reason = decoded.reason.cleanOptimizationText(
            fallback: defaultReason(for: feedback)
        )
        return StageUpdate(
            taskId: task.id,
            sourceStageId: source.id,
            updateScope: scope,
            updatedStages: mappedStages,
            removedStageIds: removedStageIds,
            reason: reason,
            requiresUserConfirmation: true
        )
    }

    private func inferredScope(for feedback: StageFeedback) -> StageUpdateScope {
        switch feedback.intent {
        case .tooHard, .unclearInstruction:
            return .currentStageOnly
        case .needMoreTime, .distracted, .needBreak:
            return .remainingStages
        default:
            return .remainingStages
        }
    }

    private func defaultReason(for feedback: StageFeedback) -> String {
        switch feedback.intent {
        case .tooHard, .unclearInstruction:
            return "The current step felt too large, so it was split into smaller actions."
        case .needMoreTime:
            return "Similar upcoming steps now have a little more room."
        case .distracted, .needBreak:
            return "A short reset was added before continuing."
        default:
            return "The next steps were adjusted to match how this step felt."
        }
    }
}

private let planOptimizationSystemPrompt = """
You adjust upcoming learning steps after stage feedback for an ADHD-friendly app.
Return JSON only with keys:
- shouldUpdate (boolean)
- updateScope ("currentStageOnly" | "remainingStages")
- reason (one gentle sentence, no blame)
- updatedStages (array of { title, instruction, completionCriteria, stageType, estimatedSeconds })

Rules:
- Use shouldUpdate=false when no change is needed.
- Prefer currentStageOnly when the current step felt too big or unclear; split into 2-3 smaller steps.
- Prefer remainingStages when the user needs more time, a break, or upcoming steps should change.
- Keep each step concrete, visible, and completable in under 25 minutes.
- Never shame the learner. Avoid words like lazy, failure, must, should.
- stageType must be one of: reading, writing, thinking, practice, breakTime, review, other.
"""

private struct LLMStageOptimization: Decodable {
    let shouldUpdate: Bool
    let updateScope: String
    let reason: String
    let updatedStages: [LLMOptimizationStage]
}

private struct LLMOptimizationStage: Decodable {
    let title: String
    let instruction: String
    let completionCriteria: String
    let stageType: String
    let estimatedSeconds: Int
}

private func planOptimizationUserPrompt(
    task: TaskPlan,
    source: StagePlan,
    remaining: [StagePlan],
    feedback: StageFeedback
) -> String {
    let remainingSummary = remaining.map {
        "- \($0.title): \($0.instruction) (\($0.estimatedSeconds)s)"
    }.joined(separator: "\n")
    let extraNotes = [
        feedback.otherText.map { "Other note: \($0)" },
        feedback.voiceTranscript.map { "Voice note: \($0)" }
    ].compactMap { $0 }.joined(separator: "\n")

    return """
    Task title: \(task.title)
    Task type: \(task.taskType.rawValue)
    Completed stage title: \(source.title)
    Completed stage instruction: \(source.instruction)
    Completed stage type: \(source.stageType.rawValue)
    Feedback label: \(feedback.selectedLabel ?? "unknown")
    Feedback intent: \(feedback.intent.rawValue)
    Difficulty: \(feedback.difficulty?.rawValue ?? "unknown")
    Granularity: \(feedback.granularity?.rawValue ?? "unknown")
    Emotion: \(feedback.emotionTag?.rawValue ?? "unknown")
    \(extraNotes.isEmpty ? "" : extraNotes + "\n")
    Remaining idle stages:
    \(remainingSummary.isEmpty ? "- none" : remainingSummary)

    Suggest a minimal plan adjustment that helps the learner continue gently.
    """
}

private extension String {
    func cleanOptimizationText(fallback: String) -> String {
        let banned = ["lazy", "failure", "you should", "you must", "failed"]
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        guard !banned.contains(where: { trimmed.lowercased().contains($0) }) else { return fallback }
        return trimmed
    }
}
