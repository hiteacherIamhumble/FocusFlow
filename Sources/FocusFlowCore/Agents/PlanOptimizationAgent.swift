import Foundation

public struct PlanOptimizationAgent: Sendable {
    public init() {}

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
        case .distracted:
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
}
