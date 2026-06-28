import Foundation

public actor ExecutionService: ExecutionServiceProtocol {
    private let repository: any TaskRepositoryProtocol
    private let runtimeStore: any RuntimeStoreProtocol
    private let eventBus: AppEventBus

    public init(
        repository: any TaskRepositoryProtocol,
        runtimeStore: any RuntimeStoreProtocol,
        eventBus: AppEventBus
    ) {
        self.repository = repository
        self.runtimeStore = runtimeStore
        self.eventBus = eventBus
    }

    public func startTask(_ taskId: String) async throws {
        var task = try await repository.getTask(taskId)
        task.status = .active
        if let firstIdle = task.stages.sorted(by: { $0.order < $1.order }).first(where: { $0.status == .idle || $0.status == .adjusted }) {
            try await repository.update(task)
            try await startStage(taskId: taskId, stageId: firstIdle.id)
        } else {
            try await repository.update(task)
        }
    }

    public func startStage(taskId: String, stageId: String) async throws {
        if let current = try await runtimeStore.loadActiveRuntime(),
           current.status == .running || current.status == .overtime {
            try await pauseCurrentStage(trigger: .system)
        }
        var task = try await repository.getTask(taskId)
        guard let index = task.stages.firstIndex(where: { $0.id == stageId }) else {
            throw FocusFlowError.stageNotFound(stageId)
        }
        task.status = .active
        task.stages[index].status = .running
        try await repository.update(task)

        let stage = task.stages[index]
        let runtime = StageRuntime(
            taskId: taskId,
            stageId: stageId,
            status: .running,
            startedAt: Date(),
            pauseStartedAt: nil,
            pauseTotalSeconds: 0,
            plannedSeconds: stage.estimatedSeconds,
            lastTickAt: Date(),
            monotonicAnchor: ProcessInfo.processInfo.systemUptime
        )
        try await runtimeStore.save(runtime)
        await eventBus.publish(stageEvent(.stageStarted, task: task, stage: stage, status: .running))
    }

    public func pauseCurrentStage(trigger: EventTrigger) async throws {
        var runtime = try await requireRuntime()
        guard runtime.status == .running || runtime.status == .overtime else { return }
        runtime.status = .paused
        runtime.pauseStartedAt = Date()
        runtime.pauseCount += 1
        runtime.lastTickAt = Date()
        try await runtimeStore.save(runtime)
        try await updateStageStatus(taskId: runtime.taskId, stageId: runtime.stageId, status: .paused, eventType: .stagePaused)
    }

    public func resumeCurrentStage(trigger: EventTrigger) async throws {
        var runtime = try await requireRuntime()
        guard runtime.status == .paused else { return }
        if let pauseStartedAt = runtime.pauseStartedAt {
            runtime.pauseTotalSeconds += max(0, Int(Date().timeIntervalSince(pauseStartedAt)))
        }
        runtime.status = .running
        runtime.pauseStartedAt = nil
        runtime.lastTickAt = Date()
        try await runtimeStore.save(runtime)
        try await updateStageStatus(taskId: runtime.taskId, stageId: runtime.stageId, status: .running, eventType: .stageResumed)
    }

    public func completeCurrentStage(trigger: EventTrigger) async throws -> StageExecutionResult {
        try await finishCurrentStage(status: .completed, eventType: .stageCompleted, trigger: trigger)
    }

    public func skipCurrentStage(trigger: EventTrigger) async throws -> StageExecutionResult {
        try await finishCurrentStage(status: .skipped, eventType: .stageSkipped, trigger: trigger)
    }

    public func abandonCurrentStage(trigger: EventTrigger) async throws -> StageExecutionResult {
        try await finishCurrentStage(status: .abandoned, eventType: .stageAbandoned, trigger: trigger)
    }

    public func extendCurrentStage(seconds: Int, trigger: EventTrigger) async throws -> StageRuntime {
        var runtime = try await requireRuntime()
        let addedSeconds = max(60, seconds)
        runtime.plannedSeconds += addedSeconds
        runtime.lastTickAt = Date()
        if runtime.status == .overtime {
            runtime.status = .running
        }
        try await runtimeStore.save(runtime)

        var task = try await repository.getTask(runtime.taskId)
        guard let index = task.stages.firstIndex(where: { $0.id == runtime.stageId }) else {
            throw FocusFlowError.stageNotFound(runtime.stageId)
        }
        task.stages[index].estimatedSeconds = runtime.plannedSeconds
        if task.stages[index].status == .overtime {
            task.stages[index].status = .running
        }
        task.estimatedTotalSeconds = task.stages.reduce(0) { $0 + $1.estimatedSeconds }
        try await repository.update(task)

        await eventBus.publish(stageEvent(
            .runtimeExtended,
            task: task,
            stage: task.stages[index],
            status: runtime.status,
            metadata: [
                "added_seconds": "\(addedSeconds)",
                "new_planned_seconds": "\(runtime.plannedSeconds)",
                "trigger": trigger.rawValue
            ]
        ))
        return runtime
    }

    public func enterOvertimeIfNeeded() async throws -> Bool {
        var runtime = try await requireRuntime()
        guard runtime.status == .running else { return runtime.status == .overtime }
        guard let remaining = try await remainingSeconds(), remaining <= 0 else { return false }
        runtime.status = .overtime
        runtime.lastTickAt = Date()
        try await runtimeStore.save(runtime)
        try await updateStageStatus(taskId: runtime.taskId, stageId: runtime.stageId, status: .overtime, eventType: .stageTimeoutPrompted)
        return true
    }

    public func applyStageUpdate(_ update: StageUpdate) async throws {
        let task = try await repository.apply(update)
        await eventBus.publish(LearningEvent(
            eventType: .stageAdjusted,
            sourceModule: .module3FeedbackOptimization,
            taskId: update.taskId,
            stageId: update.sourceStageId,
            relatedObjectId: update.id,
            taskTitle: task.title,
            taskType: task.taskType,
            status: "adjusted",
            plannedDurationSeconds: task.estimatedTotalSeconds,
            tags: ["adjustment"],
            metadata: [
                "reason": update.reason,
                "scope": update.updateScope.rawValue,
                "requires_user_confirmation": "\(update.requiresUserConfirmation)"
            ]
        ))
    }

    public func revertStageUpdate(previousTask: TaskPlan, update: StageUpdate) async throws {
        guard previousTask.id == update.taskId else {
            throw FocusFlowError.invalidState("Cannot undo an adjustment for a different task.")
        }
        try await repository.update(previousTask)
        await eventBus.publish(LearningEvent(
            eventType: .taskPlanUpdated,
            sourceModule: .module3FeedbackOptimization,
            taskId: previousTask.id,
            stageId: update.sourceStageId,
            relatedObjectId: update.id,
            taskTitle: previousTask.title,
            taskType: previousTask.taskType,
            status: previousTask.status.rawValue,
            plannedDurationSeconds: previousTask.estimatedTotalSeconds,
            tags: ["adjustment", "undo"],
            metadata: [
                "instruction": "undo_stage_update",
                "undone_update_id": update.id,
                "reason": update.reason
            ]
        ))
    }

    public func activeRuntime() async throws -> StageRuntime? {
        try await runtimeStore.loadActiveRuntime()
    }

    public func remainingSeconds(
        now: Date = Date(),
        monotonicNow: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) async throws -> Int? {
        guard let runtime = try await runtimeStore.loadActiveRuntime(),
              let startedAt = runtime.startedAt else {
            return nil
        }
        let pauseElapsed: Int
        if runtime.status == .paused, let pauseStartedAt = runtime.pauseStartedAt {
            pauseElapsed = max(0, Int(now.timeIntervalSince(pauseStartedAt)))
        } else {
            pauseElapsed = 0
        }
        let wallElapsed = max(0, Int(now.timeIntervalSince(startedAt)))
        let rawElapsed: Int
        if let monotonicAnchor = runtime.monotonicAnchor,
           monotonicNow >= monotonicAnchor {
            let monotonicElapsed = max(0, Int(monotonicNow - monotonicAnchor))
            rawElapsed = abs(wallElapsed - monotonicElapsed) > 2 ? monotonicElapsed : wallElapsed
        } else {
            rawElapsed = wallElapsed
        }
        let elapsed = rawElapsed - runtime.pauseTotalSeconds - pauseElapsed
        return runtime.plannedSeconds - elapsed
    }

    public func requestDifficulty(trigger: StuckTrigger) async throws -> StuckHelpRequest {
        var runtime = try await requireRuntime()
        runtime.difficultyHitCount += 1
        runtime.timeoutPrompted = runtime.timeoutPrompted || trigger == .timeoutNoAction
        try await runtimeStore.save(runtime)
        let task = try await repository.getTask(runtime.taskId)
        guard let stage = task.stages.first(where: { $0.id == runtime.stageId }) else {
            throw FocusFlowError.stageNotFound(runtime.stageId)
        }
        await eventBus.publish(stageEvent(
            trigger == .timeoutNoAction ? .stageTimeoutPrompted : .stageDifficultyRequested,
            task: task,
            stage: stage,
            status: runtime.status,
            metadata: ["trigger": trigger.rawValue]
        ))
        let remaining = try await remainingSeconds() ?? runtime.plannedSeconds
        return StuckHelpRequest(
            taskId: task.id,
            stageId: stage.id,
            taskTitle: task.title,
            stageTitle: stage.title,
            instruction: stage.instruction,
            stageType: stage.stageType,
            plannedSeconds: runtime.plannedSeconds,
            elapsedSeconds: max(0, runtime.plannedSeconds - remaining),
            trigger: trigger
        )
    }

    private func finishCurrentStage(status: StageStatus, eventType: LearningEventType, trigger: EventTrigger) async throws -> StageExecutionResult {
        let runtime = try await requireRuntime()
        guard let startedAt = runtime.startedAt else {
            throw FocusFlowError.invalidState("The current stage has no start time.")
        }
        var task = try await repository.getTask(runtime.taskId)
        guard let index = task.stages.firstIndex(where: { $0.id == runtime.stageId }) else {
            throw FocusFlowError.stageNotFound(runtime.stageId)
        }
        let endedAt = Date()
        let pauseTotal = runtime.pauseTotalSeconds + (runtime.status == .paused && runtime.pauseStartedAt != nil ? max(0, Int(endedAt.timeIntervalSince(runtime.pauseStartedAt!))) : 0)
        let actual = max(0, Int(endedAt.timeIntervalSince(startedAt)) - pauseTotal)
        let overtime = max(0, actual - runtime.plannedSeconds)
        task.stages[index].status = status
        if task.stages.allSatisfy({ [.completed, .skipped, .abandoned].contains($0.status) }) {
            task.status = status == .completed ? .completed : .paused
        }
        try await repository.update(task)
        try await runtimeStore.clearActiveRuntime()

        let reason: EndReason
        switch status {
        case .completed:
            if overtime > 0 {
                reason = .completedAfterOvertime
            } else if actual < runtime.plannedSeconds {
                reason = .completedEarly
            } else {
                reason = .completedOnTime
            }
        case .skipped:
            reason = .userSkipped
        case .abandoned:
            reason = .userAbandoned
        default:
            reason = .userPaused
        }

        let result = StageExecutionResult(
            taskId: runtime.taskId,
            stageId: runtime.stageId,
            startedAt: startedAt,
            endedAt: endedAt,
            plannedSeconds: runtime.plannedSeconds,
            actualFocusSeconds: min(actual, 10_800),
            pauseCount: runtime.pauseCount,
            pauseTotalSeconds: pauseTotal,
            overtimeSeconds: overtime,
            difficultyHitCount: runtime.difficultyHitCount,
            timeoutPrompted: runtime.timeoutPrompted,
            endReason: reason,
            endTrigger: trigger
        )
        let stage = task.stages[index]
        await eventBus.publish(stageEvent(
            eventType,
            task: task,
            stage: stage,
            status: status,
            actualFocusSeconds: result.actualFocusSeconds,
            pauseCount: result.pauseCount,
            metadata: [
                "result_id": result.id,
                "end_reason": reason.rawValue,
                "timeout_prompted": "\(runtime.timeoutPrompted)",
                "needs_review": "\(actual > 10_800)"
            ]
        ))
        return result
    }

    private func requireRuntime() async throws -> StageRuntime {
        guard let runtime = try await runtimeStore.loadActiveRuntime() else {
            throw FocusFlowError.noActiveRuntime
        }
        return runtime
    }

    private func updateStageStatus(taskId: String, stageId: String, status: StageStatus, eventType: LearningEventType) async throws {
        var task = try await repository.getTask(taskId)
        guard let index = task.stages.firstIndex(where: { $0.id == stageId }) else {
            throw FocusFlowError.stageNotFound(stageId)
        }
        task.stages[index].status = status
        task.status = status == .paused ? .paused : .active
        try await repository.update(task)
        await eventBus.publish(stageEvent(eventType, task: task, stage: task.stages[index], status: status))
    }

    private func stageEvent(
        _ eventType: LearningEventType,
        task: TaskPlan,
        stage: StagePlan,
        status: StageStatus,
        actualFocusSeconds: Int? = nil,
        pauseCount: Int? = nil,
        metadata: [String: String] = [:]
    ) -> LearningEvent {
        LearningEvent(
            eventType: eventType,
            sourceModule: .module2Execution,
            taskId: task.id,
            stageId: stage.id,
            taskTitle: task.title,
            taskType: task.taskType,
            stageTitle: stage.title,
            stageType: stage.stageType,
            status: status.rawValue,
            plannedDurationSeconds: stage.estimatedSeconds,
            actualFocusSeconds: actualFocusSeconds,
            pauseCount: pauseCount,
            tags: [task.taskType.rawValue, stage.stageType.rawValue],
            metadata: metadata
        )
    }
}
