import Combine
import FocusFlowCore
import Foundation
import AppKit
import SwiftUI

@MainActor
final class FocusFlowAppModel: ObservableObject {
    enum Route {
        case input
        case plan
        case execution
        case closure
        case personalCenter
        case settings
    }

    @Published var route: Route = .input
    @Published var taskInput = ""
    @Published var pendingPlanDraft: TaskPlanDraft?
    @Published var clarificationQuestions: [ClarificationQuestion] = []
    @Published var currentTask: TaskPlan?
    @Published var activeResult: StageExecutionResult?
    @Published var feedbackOptions: [FeedbackOption] = []
    @Published var feedbackOtherText = ""
    @Published var pendingStageUpdate: StageUpdate?
    @Published var canUndoLastStageUpdate = false
    @Published var postFeedbackMessage: String?
    @Published var readyToContinueAfterFeedback = false
    @Published var stuckHelp: StuckHelpResponse?
    @Published var interventionPanelVisible = false
    @Published var interventionReason = "This step may be asking for too much right now."
    @Published var closureSummary: TaskClosureSummary?
    @Published var reviewResponses: [String: Bool] = [:]
    @Published var reviewWasSkipped = false
    @Published var stats: StatsSummary?
    @Published var dailyStats: [DailyStatsPoint] = []
    @Published var history: [HistoryTaskCard] = []
    @Published var achievements: [Achievement] = []
    @Published var pendingAchievements: [Achievement] = []
    @Published var historyKeyword = ""
    @Published var historyRange: StatsRange = .last7Days
    @Published var historyTaskType: EducationTaskType = .unknown
    @Published var naturalHistoryQuery = ""
    @Published var selectedHistoryDetail: HistoryTaskDetail?
    @Published var exportFormat = "Markdown"
    @Published var remainingSeconds: Int?
    @Published var breakRemainingSeconds: Int?
    @Published var message: String?
    @Published var isWorking = false
    @Published var notificationFallbackMessage: String?
    @Published var remoteAgentStatus = "DeepSeek v4 flash ready when DEEPSEEK_API_KEY is set."
    @Published var hotKeyStatus = "Global shortcuts are ready."
    @Published var readinessReport = AppReadinessReport.empty
    @Published var settings = FocusFlowSettings.defaults
    @Published var deepSeekAPIKeyDraft = ""
    @Published var isListeningForVoice = false
    @Published var voiceTranscript = ""
    @Published var closureReviewNote = ""
    @Published var agentObservation = AgentObservation(
        text: "I am still learning your study rhythm. We will keep using small, clear starts for now.",
        confidence: 0.2
    )

    var deletableHistoryDay: String? {
        selectedHistoryDetail?.latestLocalDay ?? history.first?.localDay
    }

    var availableVoiceOptions: [SpeechSynthesisService.VoiceOption] {
        SpeechSynthesisService.availableEnglishVoices()
    }

    func originalStages(for update: StageUpdate) -> [StagePlan] {
        guard let task = currentTask else { return [] }
        let sorted = task.stages.sorted { $0.order < $1.order }
        let removedIDs = Set(update.removedStageIds)
        if !removedIDs.isEmpty {
            return sorted.filter { removedIDs.contains($0.id) }
        }
        let updatedIDs = Set(update.updatedStages.map(\.id))
        let matched = sorted.filter { updatedIDs.contains($0.id) }
        if !matched.isEmpty {
            return matched
        }
        guard let sourceStageId = update.sourceStageId,
              let source = sorted.first(where: { $0.id == sourceStageId }) else {
            return Array(sorted.prefix(3))
        }
        switch update.updateScope {
        case .currentStageOnly:
            return [source]
        case .remainingStages:
            let count = max(1, min(4, update.updatedStages.count))
            return Array(sorted.filter { $0.order > source.order && ($0.status == .idle || $0.status == .adjusted) }.prefix(count))
        case .entireTask:
            return Array(sorted.prefix(max(1, min(4, update.updatedStages.count))))
        }
    }

    func proposedStages(for update: StageUpdate) -> [StagePlan] {
        update.updatedStages.sorted { $0.order < $1.order }
    }

    private let directory = LocalDataDirectory()
    private let repository: LocalTaskRepository
    private let runtimeStore: LocalRuntimeStore
    private let dataCenter: LocalDataCenterService
    private let settingsService: LocalSettingsService
    private let credentialStore: KeychainCredentialStore
    private let remoteAgentGate: RemoteAgentGate
    private let eventBus: AppEventBus
    private let planningService: TaskPlanningService
    private let executionService: ExecutionService
    private let feedbackService: FeedbackOptimizationService
    private let closureService: TaskClosureService
    private let profileAgent: ProfileAgent
    private let historyQueryAgent: HistoryQueryAgent
    private let agentRunLogger: AgentRunLogger
    private let agentContextProvider: LocalAgentContextProvider
    private let readinessService = AppReadinessService()
    private let floatingController = FloatingTimerWindowController()
    private let notificationService = LocalNotificationService()
    private let hotKeyManager = HotKeyManager()
    private let speechSynthesizer = SpeechSynthesisService()
    private let speechRecognizer = SpeechRecognitionService()
    private var timer: Timer?
    private var timeoutPromptedStageId: String?
    private var breakEndsAt: Date?
    private var stuckActionCount = 0
    private var stageUpdateUndoSnapshot: TaskPlan?
    private var lastAppliedStageUpdate: StageUpdate?
    private var latestNotificationAuthorized: Bool?

    init() {
        let dataCenter = LocalDataCenterService(directory: directory)
        let settingsService = LocalSettingsService(directory: directory)
        let credentialStore = KeychainCredentialStore()
        let repository = LocalTaskRepository(directory: directory)
        let runtimeStore = LocalRuntimeStore(directory: directory)
        let eventBus = AppEventBus(dataCenter: dataCenter)
        let remoteAgentGate = RemoteAgentGate()
        let deepSeekClient = DeepSeekLLMClient(apiKeyProvider: {
            if let env = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"], !env.isEmpty {
                return env
            }
            return await credentialStore.readDeepSeekAPIKey()
        })
        let llmClient = PrivacyGatedLLMClient(base: deepSeekClient, gate: remoteAgentGate)
        self.repository = repository
        self.runtimeStore = runtimeStore
        self.dataCenter = dataCenter
        self.settingsService = settingsService
        self.credentialStore = credentialStore
        self.remoteAgentGate = remoteAgentGate
        self.eventBus = eventBus
        self.planningService = TaskPlanningService(agent: TaskBreakdownAgent(llmClient: llmClient), repository: repository, eventBus: eventBus)
        self.executionService = ExecutionService(repository: repository, runtimeStore: runtimeStore, eventBus: eventBus)
        self.feedbackService = FeedbackOptimizationService(repository: repository, eventBus: eventBus, feedbackAgent: FeedbackAgent(llmClient: llmClient))
        self.closureService = TaskClosureService(repository: repository, dataCenter: dataCenter, eventBus: eventBus, emotionAgent: EmotionSupportAgent(llmClient: llmClient))
        self.profileAgent = ProfileAgent(llmClient: llmClient)
        self.historyQueryAgent = HistoryQueryAgent(llmClient: llmClient)
        self.agentRunLogger = AgentRunLogger(eventBus: eventBus)
        self.agentContextProvider = LocalAgentContextProvider(dataCenter: dataCenter)
        if ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"]?.isEmpty == false {
            remoteAgentStatus = "DeepSeek v4 flash is enabled."
        }
        startTicker()
        Task {
            await loadSettings()
            await restoreLastSession()
            if settings.notificationsEnabled {
                let authorized = await notificationService.requestAuthorization()
                latestNotificationAuthorized = authorized
                if !authorized {
                    await activateNotificationFallback(reason: "authorization_denied", stage: activeStage)
                }
            }
            await refreshStats()
            await refreshReadiness()
        }
    }

    func createPlan() {
        let input = taskInput
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "Write one learning task first. It can be messy."
            return
        }
        run {
            let canUseRemoteAgent = await self.hasRemoteAgentCredentials()
            self.message = canUseRemoteAgent ? "Planning with DeepSeek v4 flash..." : "No DeepSeek key yet. Using local planning fallback."
            let context = try await self.agentContextForPlanning()
            let draft = try await self.planningService.createDraft(from: input, agentContext: context)
            self.updatePlanningStatus(from: draft.task)
            if !draft.clarificationQuestions.isEmpty {
                self.pendingPlanDraft = draft
                self.clarificationQuestions = draft.clarificationQuestions
                self.message = "One quick choice will make the plan easier to start."
            } else {
                let plan = try await self.planningService.acceptDraft(draft, clarificationAnswer: nil)
                self.pendingPlanDraft = nil
                self.clarificationQuestions = []
                self.currentTask = plan
                self.route = .plan
                self.message = self.planReadyMessage(for: plan)
            }
        }
    }

    func answerClarification(_ answer: String?) {
        guard let draft = pendingPlanDraft else {
            clarificationQuestions = []
            return
        }
        run {
            let plan = try await self.planningService.acceptDraft(draft, clarificationAnswer: answer)
            self.pendingPlanDraft = nil
            self.clarificationQuestions = []
            self.currentTask = plan
            self.route = .plan
            self.updatePlanningStatus(from: plan)
            self.message = answer == nil ? "Skipped. \(self.planReadyMessage(for: plan))" : "Got it. \(self.planReadyMessage(for: plan))"
        }
    }

    func refinePlan(_ instruction: String) {
        guard let task = currentTask else { return }
        run {
            let canUseRemoteAgent = await self.hasRemoteAgentCredentials()
            self.message = canUseRemoteAgent ? "DeepSeek is revising the plan..." : "Revising with local fallback."
            let context = try await self.agentContextForPlanning()
            self.currentTask = try await self.planningService.refinePlan(task, userInstruction: instruction, agentContext: context)
            if let currentTask = self.currentTask {
                self.updatePlanningStatus(from: currentTask)
                self.message = self.planUpdatedMessage(for: currentTask)
            } else {
                self.message = "Plan updated."
            }
        }
    }

    func regeneratePlan() {
        guard let task = currentTask else { return }
        run {
            let canUseRemoteAgent = await self.hasRemoteAgentCredentials()
            self.message = canUseRemoteAgent ? "DeepSeek is regenerating the plan..." : "Regenerating with local fallback."
            let context = try await self.agentContextForPlanning()
            self.currentTask = try await self.planningService.regeneratePlan(task, agentContext: context)
            if let currentTask = self.currentTask {
                self.updatePlanningStatus(from: currentTask)
                self.message = "Plan regenerated. \(self.planReadyMessage(for: currentTask))"
            } else {
                self.message = "Plan regenerated with a fresh set of steps."
            }
        }
    }

    func updateStage(_ stage: StagePlan, patch: StagePlanPatch) {
        guard let task = currentTask else { return }
        run {
            self.currentTask = try await self.planningService.updateStage(taskId: task.id, stageId: stage.id, patch: patch)
            self.message = "Stage updated."
        }
    }

    func insertStage(before stage: StagePlan?, patch: StagePlanPatch) {
        guard let task = currentTask else { return }
        run {
            self.currentTask = try await self.planningService.insertStage(taskId: task.id, beforeStageId: stage?.id, patch: patch)
            self.message = stage == nil ? "Stage added at the end." : "Stage added before step \(stage?.order ?? 1)."
        }
    }

    func deleteStage(_ stage: StagePlan) {
        guard let task = currentTask else { return }
        run {
            self.currentTask = try await self.planningService.deleteStage(taskId: task.id, stageId: stage.id)
            self.message = "Stage deleted."
        }
    }

    func confirmAndStart() {
        guard let task = currentTask else { return }
        run {
            try await self.planningService.confirmPlan(task)
            try await self.executionService.startTask(task.id)
            self.currentTask = try await self.repository.getTask(task.id)
            self.startFeedbackPrewarmForActiveStage()
            await self.scheduleReminderForActiveStage()
            self.route = .execution
            self.message = "Start with only the current step."
        }
    }

    func pauseOrResume() {
        run {
            if let runtime = try await self.executionService.activeRuntime(), runtime.status == .paused {
                try await self.executionService.resumeCurrentStage(trigger: .user)
                self.message = "Welcome back. Continuing counts."
            } else {
                try await self.executionService.pauseCurrentStage(trigger: .user)
                self.message = "Paused. Your place is saved."
            }
            await self.reloadCurrentTask()
        }
    }

    func completeStage() {
        run {
            let result = try await self.executionService.completeCurrentStage(trigger: .user)
            self.activeResult = result
            await self.reloadCurrentTask()
            self.feedbackOptions = try await self.feedbackService.prepareFeedbackOptions(taskId: result.taskId, stageId: result.stageId)
            self.pendingStageUpdate = nil
            self.clearStageUpdateUndo()
            self.postFeedbackMessage = nil
            self.readyToContinueAfterFeedback = false
            self.message = "Step saved. One quick check-in, then we continue."
        }
    }

    func extendCurrentStageByFiveMinutes() {
        run {
            let runtime = try await self.executionService.extendCurrentStage(seconds: 300, trigger: .user)
            await self.reloadCurrentTask()
            await self.scheduleReminderForActiveStage()
            self.remainingSeconds = try? await self.executionService.remainingSeconds()
            self.message = "Added 5 minutes. New stage time: \(runtime.plannedSeconds / 60) min."
        }
    }

    func completeTaskNow() {
        guard let taskId = currentTask?.id else { return }
        run {
            if try await self.executionService.activeRuntime() != nil {
                _ = try await self.executionService.completeCurrentStage(trigger: .user)
            }
            self.feedbackOptions = []
            self.activeResult = nil
            self.pendingStageUpdate = nil
            self.clearStageUpdateUndo()
            self.postFeedbackMessage = nil
            self.readyToContinueAfterFeedback = false
            self.closureSummary = try await self.closureService.presentCompletion(taskId: taskId)
            self.reviewResponses = [:]
            self.reviewWasSkipped = false
            self.speakClosureIfNeeded()
            await self.reloadCurrentTask()
            self.route = .closure
            self.message = "Task completed now."
        }
    }

    func skipStage() {
        run {
            let result = try await self.executionService.skipCurrentStage(trigger: .user)
            self.activeResult = result
            await self.reloadCurrentTask()
            self.feedbackOptions = try await self.feedbackService.prepareFeedbackOptions(taskId: result.taskId, stageId: result.stageId)
            self.pendingStageUpdate = nil
            self.clearStageUpdateUndo()
            self.postFeedbackMessage = nil
            self.readyToContinueAfterFeedback = false
            self.message = "Skipped for now. That is a valid choice."
        }
    }

    func abandonTaskGracefully() {
        guard let taskId = currentTask?.id else { return }
        run {
            self.closureSummary = try await self.closureService.presentGracefulPause(taskId: taskId, reason: nil)
            self.reviewResponses = [:]
            self.reviewWasSkipped = false
            self.speakClosureIfNeeded()
            await self.reloadCurrentTask()
            self.route = .closure
        }
    }

    func abandonCurrentTask(reason: String = "You chose to stop this task for now.") {
        guard let taskId = currentTask?.id else { return }
        run {
            self.closureSummary = try await self.closureService.presentAbandonment(taskId: taskId, reason: reason)
            self.reviewResponses = [:]
            self.reviewWasSkipped = false
            self.pendingStageUpdate = nil
            self.clearStageUpdateUndo()
            self.postFeedbackMessage = nil
            self.readyToContinueAfterFeedback = false
            self.stuckHelp = nil
            self.interventionPanelVisible = false
            self.speakClosureIfNeeded()
            await self.reloadCurrentTask()
            self.route = .closure
            self.message = "Task closed. Your history reflects that this one was stopped."
        }
    }

    func startNextStage() {
        clearStageUpdateUndo()
        pendingStageUpdate = nil
        postFeedbackMessage = nil
        readyToContinueAfterFeedback = false
        guard let task = currentTask,
              let next = task.stages.sorted(by: { $0.order < $1.order }).first(where: { $0.status == .idle || $0.status == .adjusted }) else {
            guard let taskId = currentTask?.id else { return }
            run {
                self.closureSummary = try await self.closureService.presentCompletion(taskId: taskId)
                self.reviewResponses = [:]
                self.reviewWasSkipped = false
                self.speakClosureIfNeeded()
                self.route = .closure
            }
            return
        }
        run {
            try await self.executionService.startStage(taskId: task.id, stageId: next.id)
            await self.reloadCurrentTask()
            self.startFeedbackPrewarmForActiveStage()
            await self.scheduleReminderForActiveStage()
            self.activeResult = nil
            self.feedbackOptions = []
            self.pendingStageUpdate = nil
            self.clearStageUpdateUndo()
            self.stuckHelp = nil
            self.timeoutPromptedStageId = nil
        }
    }

    func submitFeedback(_ option: FeedbackOption) {
        guard let result = activeResult else { return }
        run {
            let feedback = StageFeedback(
                taskId: result.taskId,
                stageId: result.stageId,
                executionResultId: result.id,
                selectedLabel: option.label,
                voiceTranscript: self.voiceTranscript.isEmpty ? nil : self.voiceTranscript,
                otherText: self.feedbackOtherText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self.feedbackOtherText,
                intent: option.intent,
                difficulty: option.intent == .tooHard ? .hard : nil,
                granularity: option.intent == .tooHard ? .tooLarge : nil,
                skipped: false
            )
            let outcome = try await self.feedbackService.submitFeedback(feedback)
            self.voiceTranscript = ""
            self.feedbackOtherText = ""
            self.feedbackOptions = []
            if let intervention = outcome.interventionRequest {
                try await self.presentInterventionClosure(intervention)
                return
            }
            self.pendingStageUpdate = outcome.stageUpdate
            self.postFeedbackMessage = outcome.stageUpdate == nil
                ? (outcome.lightweightMessage ?? "Feedback saved. The next step is ready.")
                : nil
            self.message = self.postFeedbackMessage
            if let update = outcome.stageUpdate {
                self.readyToContinueAfterFeedback = true
                self.message = update.reason
            } else if self.hasRemainingStage {
                self.readyToContinueAfterFeedback = true
            } else {
                self.readyToContinueAfterFeedback = false
                self.closureSummary = try await self.closureService.presentCompletion(taskId: result.taskId)
                self.reviewResponses = [:]
                self.reviewWasSkipped = false
                self.speakClosureIfNeeded()
                self.route = .closure
            }
        }
    }

    func submitOtherFeedback() {
        let trimmed = feedbackOtherText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            message = "Write the situation first, even a few words."
            return
        }
        submitFeedback(FeedbackOption(label: "Other", emoji: nil, intent: .other))
    }

    private func presentInterventionClosure(_ intervention: InterventionRequest) async throws {
        let reason: String
        switch intervention.interruptionType {
        case .activeQuit:
            reason = "You chose not to continue this task right now."
        case .emotionalOverload:
            reason = "This task started to feel emotionally heavy."
        case .longNoResponse:
            reason = "The step sat too long without a clear next move."
        case .repeatedIncomplete:
            reason = "Several steps did not land today."
        }
        pendingStageUpdate = nil
        postFeedbackMessage = nil
        readyToContinueAfterFeedback = false
        interventionPanelVisible = false
        stuckHelp = nil
        switch intervention.interruptionType {
        case .activeQuit:
            closureSummary = try await closureService.presentAbandonment(taskId: intervention.taskId, reason: reason)
        case .emotionalOverload, .longNoResponse, .repeatedIncomplete:
            closureSummary = try await closureService.presentGracefulPause(taskId: intervention.taskId, reason: reason)
        }
        reviewResponses = [:]
        reviewWasSkipped = false
        await reloadCurrentTask()
        speakClosureIfNeeded()
        route = .closure
        message = "Progress is saved. We can stop here gently."
    }

    func applyPendingStageUpdate() {
        guard let update = pendingStageUpdate else { return }
        run {
            self.stageUpdateUndoSnapshot = self.currentTask
            self.lastAppliedStageUpdate = update
            self.canUndoLastStageUpdate = self.stageUpdateUndoSnapshot != nil
            try await self.executionService.applyStageUpdate(update)
            self.pendingStageUpdate = nil
            await self.reloadCurrentTask()
            self.postFeedbackMessage = "\(update.reason) The next step is ready."
            self.message = self.postFeedbackMessage
            if self.hasRemainingStage {
                self.readyToContinueAfterFeedback = true
            } else {
                self.readyToContinueAfterFeedback = false
                self.closureSummary = try await self.closureService.presentCompletion(taskId: update.taskId)
                self.reviewResponses = [:]
                self.reviewWasSkipped = false
                self.speakClosureIfNeeded()
                self.route = .closure
            }
        }
    }

    func undoLastStageUpdate() {
        guard let snapshot = stageUpdateUndoSnapshot, let update = lastAppliedStageUpdate else {
            message = "No recent adjustment to undo."
            return
        }
        run {
            try await self.executionService.revertStageUpdate(previousTask: snapshot, update: update)
            await self.reloadCurrentTask()
            self.clearStageUpdateUndo()
            self.postFeedbackMessage = "Adjustment undone. The original next step is back."
            self.message = self.postFeedbackMessage
            self.readyToContinueAfterFeedback = self.hasRemainingStage
        }
    }

    func keepOriginalPlanAfterFeedback() {
        clearStageUpdateUndo()
        pendingStageUpdate = nil
        postFeedbackMessage = "Saved. You can keep the next step as-is."
        message = postFeedbackMessage
        if hasRemainingStage {
            readyToContinueAfterFeedback = true
        } else {
            readyToContinueAfterFeedback = false
            guard let taskId = activeResult?.taskId else { return }
            run {
                self.closureSummary = try await self.closureService.presentCompletion(taskId: taskId)
                self.reviewResponses = [:]
                self.reviewWasSkipped = false
                self.speakClosureIfNeeded()
                self.route = .closure
            }
        }
    }

    func skipFeedbackAndContinue() {
        guard let result = activeResult else {
            voiceTranscript = ""
            feedbackOptions = []
            pendingStageUpdate = nil
            clearStageUpdateUndo()
            postFeedbackMessage = nil
            readyToContinueAfterFeedback = false
            startNextStage()
            return
        }
        run {
            let feedback = StageFeedback(
                taskId: result.taskId,
                stageId: result.stageId,
                executionResultId: result.id,
                selectedLabel: "Skipped feedback",
                voiceTranscript: self.voiceTranscript.isEmpty ? nil : self.voiceTranscript,
                otherText: self.feedbackOtherText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self.feedbackOtherText,
                intent: .skippedFeedback,
                skipped: true
            )
            _ = try await self.feedbackService.submitFeedback(feedback)
            self.voiceTranscript = ""
            self.feedbackOtherText = ""
            self.feedbackOptions = []
            self.pendingStageUpdate = nil
            self.clearStageUpdateUndo()
            self.postFeedbackMessage = nil
            self.readyToContinueAfterFeedback = false
            await self.reloadCurrentTask()
            if let task = self.currentTask,
               let next = task.stages.sorted(by: { $0.order < $1.order }).first(where: { $0.status == .idle || $0.status == .adjusted }) {
                try await self.executionService.startStage(taskId: task.id, stageId: next.id)
                await self.reloadCurrentTask()
                self.startFeedbackPrewarmForActiveStage()
                await self.scheduleReminderForActiveStage()
                self.activeResult = nil
                self.stuckHelp = nil
                self.timeoutPromptedStageId = nil
                self.message = "Feedback skipped. Next step is ready."
            } else {
                self.closureSummary = try await self.closureService.presentCompletion(taskId: result.taskId)
                self.reviewResponses = [:]
                self.reviewWasSkipped = false
                self.speakClosureIfNeeded()
                self.route = .closure
            }
        }
    }

    func continueAfterFeedback() {
        guard pendingStageUpdate == nil else {
            message = "Review the suggested plan change first."
            return
        }
        guard readyToContinueAfterFeedback else {
            guard let taskId = currentTask?.id else { return }
            run {
                self.postFeedbackMessage = nil
                self.closureSummary = try await self.closureService.presentCompletion(taskId: taskId)
                self.reviewResponses = [:]
                self.reviewWasSkipped = false
                self.speakClosureIfNeeded()
                self.route = .closure
            }
            return
        }
        startNextStage()
    }

    func requestStuckHelp() {
        run {
            let request = try await self.executionService.requestDifficulty(trigger: .userClickedDifficulty)
            self.stuckHelp = try await self.feedbackService.generateStuckHelp(request)
            self.stuckActionCount += 1
            if self.stuckActionCount >= 2 {
                self.showIntervention(reason: "You have asked for help a couple of times. We can make this gentler.")
            }
        }
    }

    func requestTimeoutStuckHelp() {
        run {
            let request = try await self.executionService.requestDifficulty(trigger: .timeoutNoAction)
            self.timeoutPromptedStageId = request.stageId
            self.stuckHelp = try await self.feedbackService.generateStuckHelp(request)
            self.showIntervention(reason: "The timer ended without a clear next move. We can reset gently.")
            self.message = "The timer ended. Let's make the next move smaller."
        }
    }

    func testDeepSeekConnection() {
        run {
            let client = DeepSeekLLMClient(apiKeyProvider: {
                if let env = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"], !env.isEmpty {
                    return env
                }
                return await self.credentialStore.readDeepSeekAPIKey()
            })
            let response = try await client.complete(
                messages: [
                    LLMMessage(role: "system", content: "Return only JSON."),
                    LLMMessage(role: "user", content: "{\"ping\":\"focusflow\"}")
                ],
                privacyMode: .remoteLLMAllowedForCurrentContext,
                responseFormat: .jsonObject
            )
            self.remoteAgentStatus = "DeepSeek responded: \(response.prefix(80))"
            self.message = "Remote agent connection works."
        }
    }

    func takeShortBreak() {
        startBreak(seconds: 180, label: "Three gentle minutes. Come back when ready.")
    }

    func takeTenMinuteRest() {
        startBreak(seconds: 600, label: "Ten minutes saved. Your place will be here.")
    }

    func testFloatingTimer() {
        floatingController.show(
            stageTitle: activeStage?.title ?? "Floating timer test",
            remainingSeconds: remainingSeconds ?? 300,
            opacity: settings.floatingTimerOpacity,
            savedOrigin: floatingTimerSavedOrigin,
            onFrameChanged: { [weak self] frame in self?.saveFloatingTimerFrame(frame) },
            onDifficulty: { [weak self] in self?.requestStuckHelp() },
            onExtend: { [weak self] in self?.extendCurrentStageByFiveMinutes() },
            onComplete: { [weak self] in self?.completeStage() }
        )
        message = "Floating timer is visible. Drag it to test placement."
    }

    func testVoicePrompt() {
        speechSynthesizer.speak(
            "FocusFlow voice is ready.",
            enabled: true,
            voiceIdentifier: settings.voiceIdentifier
        )
        message = "Voice prompt test played."
    }

    func testShortcuts() {
        applyHotkeySettings()
        Task { @MainActor in
            if hotKeyManager.failedRegistrationCount > 0 {
                await eventBus.publish(LearningEvent(
                    eventType: .manualCheckIn,
                    sourceModule: .system,
                    status: "shortcut_conflict_kept",
                    tags: ["settings", "shortcut", "risk"],
                    metadata: ["failed_registration_count": "\(hotKeyManager.failedRegistrationCount)"]
                ))
            }
        }
        message = hotKeyStatus
    }

    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
        message = "Opened macOS notification settings."
    }

    private func startBreak(seconds: Int, label: String) {
        run {
            try await self.executionService.pauseCurrentStage(trigger: .user)
            self.breakEndsAt = Date().addingTimeInterval(TimeInterval(seconds))
            self.breakRemainingSeconds = seconds
            let scheduled = await self.notificationService.scheduleStageReminder(
                identifier: "focusflow.break.active",
                title: "FocusFlow break is done",
                body: "Your place is saved. Come back gently when you are ready.",
                secondsFromNow: TimeInterval(seconds)
            )
            if !scheduled {
                await self.activateNotificationFallback(reason: "break_notification_unavailable", stage: self.activeStage)
            }
            await self.recordStuckAction(.shortBreak)
            self.interventionPanelVisible = false
            self.message = label
            await self.reloadCurrentTask()
        }
    }

    func handleStuckAction(_ action: StuckHelpAction) {
        switch action.actionType {
        case .hint:
            run {
                await self.recordStuckAction(.hint)
                self.message = "Hint: name the one word, formula, or sentence you can identify first."
            }
        case .example:
            run {
                await self.recordStuckAction(.example)
                self.message = "Example: write a rough placeholder now and improve it later."
            }
        case .splitSmaller:
            splitActiveStageSmaller()
        case .shortBreak:
            takeShortBreak()
        }
    }

    func splitActiveStageSmaller() {
        guard let task = currentTask, let stage = activeStage else {
            message = "No active stage to split."
            return
        }
        run {
            let remaining = task.stages
                .filter { $0.order > stage.order && ($0.status == .idle || $0.status == .adjusted) }
            let tinyStage = StagePlan(
                taskId: task.id,
                order: stage.order + 1,
                title: "Tiny restart: \(stage.title)",
                instruction: "Do only the first visible two-minute part of this step.",
                completionCriteria: "One small visible part is started.",
                stageType: stage.stageType,
                estimatedSeconds: 120,
                status: .adjusted,
                createdBy: .module3FeedbackOptimization,
                parentStageId: stage.id,
                metadata: ["stuck_action": StuckActionType.splitSmaller.rawValue]
            )
            let update = StageUpdate(
                taskId: task.id,
                sourceStageId: stage.id,
                updateScope: .remainingStages,
                updatedStages: [tinyStage] + remaining,
                reason: "The current step was split after the user asked for stuck help.",
                requiresUserConfirmation: false
            )
            try await self.executionService.applyStageUpdate(update)
            await self.recordStuckAction(.splitSmaller)
            await self.reloadCurrentTask()
            self.interventionPanelVisible = false
            self.message = "A two-minute restart step was added next."
        }
    }

    func showIntervention(reason: String) {
        interventionReason = reason
        interventionPanelVisible = true
        Task {
            await eventBus.publish(LearningEvent(
                eventType: .interventionTriggered,
                sourceModule: .module3FeedbackOptimization,
                taskId: currentTask?.id,
                stageId: activeStage?.id,
                taskTitle: currentTask?.title,
                taskType: currentTask?.taskType,
                stageTitle: activeStage?.title,
                stageType: activeStage?.stageType,
                status: "panel_presented",
                tags: ["intervention"],
                metadata: ["reason": reason]
            ))
        }
    }

    func saveProgressFromIntervention() {
        interventionPanelVisible = false
        abandonTaskGracefully()
    }

    func switchTaskFromIntervention() {
        run {
            if let taskId = self.currentTask?.id {
                _ = try await self.closureService.presentGracefulPause(taskId: taskId, reason: "You chose to switch tasks.")
            }
            self.currentTask = nil
            self.pendingPlanDraft = nil
            self.clarificationQuestions = []
            self.activeResult = nil
            self.feedbackOptions = []
            self.pendingStageUpdate = nil
            self.clearStageUpdateUndo()
            self.postFeedbackMessage = nil
            self.readyToContinueAfterFeedback = false
            self.reviewResponses = [:]
            self.reviewWasSkipped = false
            self.stuckHelp = nil
            self.interventionPanelVisible = false
            self.taskInput = ""
            self.route = .input
            self.message = "Progress saved. Pick a different learning task when ready."
        }
    }

    func beginVoiceInput() {
        guard settings.voiceInputEnabled else {
            message = "Turn on voice input in Settings first."
            return
        }
        run {
            self.isListeningForVoice = true
            self.voiceTranscript = ""
            try await self.speechRecognizer.start { transcript, isFinal in
                self.voiceTranscript = transcript
                if self.route == .input {
                    self.taskInput = transcript
                }
                if isFinal {
                    self.isListeningForVoice = false
                    if self.route == .input {
                        self.message = "Voice input captured."
                    } else {
                        self.handleFinalVoiceTranscript(transcript)
                    }
                }
            }
            self.message = "Listening..."
        }
    }

    func stopVoiceInput() {
        speechRecognizer.stop()
        isListeningForVoice = false
        if !voiceTranscript.isEmpty, route != .input {
            handleFinalVoiceTranscript(voiceTranscript)
        } else {
            message = voiceTranscript.isEmpty ? "Voice input stopped." : "Voice input saved."
        }
    }

    private func handleFinalVoiceTranscript(_ transcript: String) {
        guard let command = VoiceCommandParser.parse(transcript) else {
            message = "Voice note saved."
            return
        }
        Task { @MainActor in
            await recordVoiceCommand(command)
        }
        message = "Voice command: \(command.rawValue)."
        routeVoiceCommand(command)
    }

    private func routeVoiceCommand(_ command: VoiceCommandIntent) {
        switch command {
        case .complete:
            if !feedbackOptions.isEmpty {
                submitFeedback(feedbackOption(for: .completed, fallbackLabel: "Done enough"))
            } else {
                completeStage()
            }
        case .pauseOrResume:
            pauseOrResume()
        case .skip:
            if !feedbackOptions.isEmpty {
                skipFeedbackAndContinue()
            } else {
                skipStage()
            }
        case .help:
            requestStuckHelp()
        case .shortBreak:
            takeShortBreak()
        case .moreTime:
            if !feedbackOptions.isEmpty {
                submitFeedback(feedbackOption(for: .needMoreTime, fallbackLabel: "Need time"))
            } else {
                message = "I heard you need more time. Use I'm stuck if the step needs help."
            }
        case .tooHard:
            if !feedbackOptions.isEmpty {
                submitFeedback(feedbackOption(for: .tooHard, fallbackLabel: "Too hard"))
            } else {
                requestStuckHelp()
            }
        case .distracted:
            markDistraction()
        case .stopTask:
            if !feedbackOptions.isEmpty {
                submitFeedback(FeedbackOption(label: "Stop here", emoji: nil, intent: .wantToQuit))
            } else {
                abandonCurrentTask(reason: "You used a voice command to stop this task.")
            }
        case .continueNext:
            if readyToContinueAfterFeedback {
                continueAfterFeedback()
            } else if !feedbackOptions.isEmpty {
                skipFeedbackAndContinue()
            } else {
                startNextStage()
            }
        }
    }

    private func feedbackOption(for intent: FeedbackIntent, fallbackLabel: String) -> FeedbackOption {
        feedbackOptions.first { $0.intent == intent } ?? FeedbackOption(label: fallbackLabel, emoji: nil, intent: intent)
    }

    func refreshStats() async {
        do {
            stats = try await dataCenter.getStats(range: .last7Days)
            dailyStats = try await dataCenter.getDailyStats(range: .last7Days)
            try await refreshHistory()
            achievements = try await dataCenter.getUnlockedAchievements()
            pendingAchievements = try await dataCenter.getPendingAchievements()
            if !settings.profileLearningEnabled {
                agentObservation = AgentObservation(
                    text: "Profile learning is off. I will use the current task only and keep history available locally.",
                    confidence: 0.0
                )
            } else if let stats {
                let profile = try await dataCenter.getUserProfileSnapshot()
                let observation = try? await agentRunLogger.run(
                    agentName: "ProfileAgent",
                    purpose: "generate_agent_observation_card",
                    sourceModule: .module5DataCenter,
                    privacyMode: .remoteLLMAllowedForCurrentContext,
                    outputSummary: { "confidence=\(String(format: "%.2f", $0.confidence))" },
                    operation: {
                        await profileAgent.observation(profile: profile, stats: stats)
                    }
                )
                if let observation {
                    agentObservation = observation
                } else {
                    agentObservation = await profileAgent.observation(profile: profile, stats: stats)
                }
            }
        } catch {
            message = error.localizedDescription
        }
    }

    func refreshHistory() async throws {
        let taskTypes = historyTaskType == .unknown ? [] : [historyTaskType]
        history = try await dataCenter.queryHistory(HistoryQuery(
            dateRange: historyRange,
            keyword: historyKeyword,
            taskTypes: taskTypes
        ))
    }

    func refreshReadiness() async {
        let hasEnvironmentKey = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"]?.isEmpty == false
        let hasSavedKey = await credentialStore.readDeepSeekAPIKey() != nil
        let dataWritable: Bool
        do {
            try directory.prepare()
            let probeURL = directory.root.appendingPathComponent(".readiness_probe")
            try "ok".write(to: probeURL, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(at: probeURL)
            dataWritable = true
        } catch {
            dataWritable = false
        }
        readinessReport = readinessService.report(for: AppReadinessInputs(
            settings: settings,
            hasDeepSeekAPIKey: hasEnvironmentKey || hasSavedKey,
            notificationAuthorized: latestNotificationAuthorized,
            dataDirectoryWritable: dataWritable,
            hotKeyFailedRegistrationCount: hotKeyManager.failedRegistrationCount,
            englishVoiceAvailable: !SpeechSynthesisService.availableEnglishVoices().isEmpty,
            speechRecognitionAvailable: SpeechRecognitionService.isAvailable()
        ))
    }

    func applyHistoryFilters() {
        run {
            try await self.refreshHistory()
            self.message = "History filters updated."
        }
    }

    func applyNaturalHistoryQuery() {
        let queryText = naturalHistoryQuery
        guard !queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            applyHistoryFilters()
            return
        }
        run {
            let query: HistoryQuery
            do {
                query = try await self.agentRunLogger.run(
                    agentName: "HistoryQueryAgent",
                    purpose: "parse_history_query",
                    sourceModule: .module5DataCenter,
                    privacyMode: .remoteLLMAllowedForCurrentContext,
                    outputSummary: { query in
                        "range=\(query.dateRange?.rawValue ?? "none"); keyword=\(query.keyword ?? "none"); task_types=\(query.taskTypes.map(\.rawValue).joined(separator: ","))"
                    },
                    operation: {
                        try await self.historyQueryAgent.parseUsingLLM(queryText)
                    }
                )
            } catch {
                query = try await self.dataCenter.parseHistoryQuery(queryText)
                await self.eventBus.publish(LearningEvent(
                    eventType: .agentRunFailed,
                    sourceModule: .module5DataCenter,
                    status: "history_query_agent_fallback",
                    tags: ["history", "agent", "fallback"],
                    metadata: ["reason": error.localizedDescription]
                ))
            }
            self.historyRange = query.dateRange ?? .last7Days
            self.historyTaskType = query.taskTypes.first ?? .unknown
            self.historyKeyword = query.keyword ?? ""
            self.history = try await self.dataCenter.queryHistory(query)
            self.message = "History query applied."
        }
    }

    func loadHistoryDetail(_ card: HistoryTaskCard) {
        run {
            self.selectedHistoryDetail = try await self.dataCenter.getHistoryDetail(taskId: card.taskId)
        }
    }

    func deleteHistoryTask(_ detail: HistoryTaskDetail) {
        run {
            try await self.dataCenter.deleteHistoryTask(taskId: detail.taskId)
            self.selectedHistoryDetail = nil
            try await self.refreshHistory()
            self.message = "Task history deleted."
        }
    }

    func deleteSelectedHistoryDay() {
        guard let localDay = deletableHistoryDay else {
            message = "No history day selected."
            return
        }
        run {
            try await self.dataCenter.deleteHistoryDay(localDay: localDay)
            self.selectedHistoryDetail = nil
            try await self.refreshHistory()
            self.message = "History for \(localDay) deleted."
        }
    }

    func dismissAchievement(_ achievement: Achievement) {
        run {
            try await self.dataCenter.markAchievementDisplayed(achievement.id)
            self.pendingAchievements = try await self.dataCenter.getPendingAchievements()
            self.message = "Achievement saved to your garden."
        }
    }

    func loadSettings() async {
        do {
            settings = try await settingsService.loadSettings()
            await dataCenter.setProfileLearningEnabled(settings.profileLearningEnabled)
            await dataCenter.setLocalEncryptionEnabled(settings.localEncryptionEnabled)
            await repository.setLocalEncryptionEnabled(settings.localEncryptionEnabled)
            await runtimeStore.setLocalEncryptionEnabled(settings.localEncryptionEnabled)
            await remoteAgentGate.setEnabled(settings.remoteAgentEnabled)
            applyHotkeySettings()
            if await credentialStore.readDeepSeekAPIKey() != nil {
                remoteAgentStatus = settings.remoteAgentEnabled ? "DeepSeek key is saved in Keychain." : "Remote agent is off. Local fallback is active."
            }
            await refreshReadiness()
        } catch {
            message = error.localizedDescription
        }
    }

    func saveSettings() {
        run {
            try await self.settingsService.saveSettings(self.settings)
            await self.dataCenter.setProfileLearningEnabled(self.settings.profileLearningEnabled)
            await self.dataCenter.setLocalEncryptionEnabled(self.settings.localEncryptionEnabled)
            await self.repository.setLocalEncryptionEnabled(self.settings.localEncryptionEnabled)
            await self.runtimeStore.setLocalEncryptionEnabled(self.settings.localEncryptionEnabled)
            await self.remoteAgentGate.setEnabled(self.settings.remoteAgentEnabled)
            self.applyHotkeySettings()
            if self.settings.notificationsEnabled {
                let authorized = await self.notificationService.requestAuthorization()
                self.latestNotificationAuthorized = authorized
                if !authorized {
                    await self.activateNotificationFallback(reason: "authorization_denied", stage: self.activeStage)
                } else {
                    self.notificationFallbackMessage = nil
                }
                await self.scheduleReminderForActiveStage()
            } else {
                self.notificationService.cancelPendingStageReminders()
                self.notificationFallbackMessage = nil
            }
            self.remoteAgentStatus = self.settings.remoteAgentEnabled ? "DeepSeek v4 flash is enabled when a key is available." : "Remote agent is off. Local fallback is active."
            await self.refreshReadiness()
            self.message = "Settings saved."
        }
    }

    func resetFloatingTimerPosition() {
        settings.floatingTimerOriginX = nil
        settings.floatingTimerOriginY = nil
        floatingController.hide()
        run {
            try await self.settingsService.saveSettings(self.settings)
            await self.refreshReadiness()
            self.message = "Floating timer position reset."
        }
    }

    func saveDeepSeekKey() {
        let key = deepSeekAPIKeyDraft
        run {
            try await self.credentialStore.saveDeepSeekAPIKey(key)
            self.deepSeekAPIKeyDraft = ""
            self.remoteAgentStatus = "DeepSeek key saved in Keychain."
            await self.refreshReadiness()
            self.message = "Remote agent key saved."
        }
    }

    func clearDeepSeekKey() {
        run {
            try await self.credentialStore.deleteDeepSeekAPIKey()
            self.remoteAgentStatus = "DeepSeek v4 flash ready when DEEPSEEK_API_KEY is set."
            await self.refreshReadiness()
            self.message = "Remote agent key removed."
        }
    }

    func exportLocalData() {
        run {
            let (contents, fileExtension): (String, String)
            switch self.exportFormat {
            case "JSON":
                contents = try await self.dataCenter.exportEventsJSON()
                fileExtension = "json"
            case "CSV":
                contents = try await self.dataCenter.exportEventsCSV()
                fileExtension = "csv"
            default:
                contents = try await self.dataCenter.exportEventsMarkdown()
                fileExtension = "md"
            }
            try self.directory.prepare()
            let fileName = "focusflow_export_\(FocusFlowCalendar.localDay()).\(fileExtension)"
            let url = self.directory.export.appendingPathComponent(fileName)
            try contents.write(to: url, atomically: true, encoding: .utf8)
            await self.eventBus.publish(LearningEvent(
                eventType: .dataExported,
                sourceModule: .module5DataCenter,
                relatedObjectId: url.lastPathComponent,
                tags: ["export"],
                metadata: ["path": url.path]
            ))
            self.message = "Exported to \(url.path)"
        }
    }

    func deleteAllData() {
        run {
            try await self.dataCenter.deleteAllUserData()
            self.currentTask = nil
            self.pendingPlanDraft = nil
            self.clarificationQuestions = []
            self.activeResult = nil
            self.feedbackOptions = []
            self.pendingStageUpdate = nil
            self.clearStageUpdateUndo()
            self.postFeedbackMessage = nil
            self.readyToContinueAfterFeedback = false
            self.closureSummary = nil
            self.reviewResponses = [:]
            self.reviewWasSkipped = false
            self.taskInput = ""
            self.route = .input
            self.message = "Local FocusFlow data was deleted."
            await self.refreshStats()
        }
    }

    func clearProfileMemory() {
        run {
            try await self.dataCenter.clearUserProfile()
            self.agentObservation = AgentObservation(
                text: "I cleared the learned profile. Your history is still local and available.",
                confidence: 0.1
            )
            self.message = "Agent profile memory cleared. History was preserved."
            await self.refreshStats()
        }
    }

    func markProfileObservationInaccurate() {
        run {
            let profile = try await self.dataCenter.getUserProfileSnapshot()
            let correction = ProfileCorrection(
                reason: "user_marked_observation_inaccurate",
                affectedStageTypes: profile.difficultStageTypes + profile.easierStageTypes,
                note: self.agentObservation.text,
                confidenceImpact: 0.35
            )
            let corrected = try await self.dataCenter.submitProfileCorrection(correction)
            self.agentObservation = AgentObservation(
                text: "Thanks. I lowered confidence in that observation and will avoid leaning on it.",
                confidence: corrected.confidence
            )
            self.message = "Profile observation marked inaccurate."
        }
    }

    func submitReviewResponse(item: ReviewItem, confirmed: Bool) {
        guard let summary = closureSummary else { return }
        run {
            try await self.closureService.submitReview(summary: summary, item: item, confirmed: confirmed)
            self.reviewResponses[item.id] = confirmed
            self.reviewWasSkipped = false
            self.closureSummary = self.summaryByUpdatingReview(itemId: item.id, confirmed: confirmed)
            self.message = confirmed ? "Review saved." : "Thanks. I will not overfit to that idea."
        }
    }

    func skipClosureReview() {
        guard let summary = closureSummary else { return }
        run {
            try await self.closureService.skipReview(summary: summary)
            self.reviewResponses = [:]
            self.reviewWasSkipped = true
            self.message = "Review skipped. Your progress is still saved."
        }
    }

    func submitClosureReviewNote() {
        guard let summary = closureSummary else { return }
        let trimmed = closureReviewNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            message = "Write one short note first."
            return
        }
        run {
            await self.eventBus.publish(LearningEvent(
                eventType: .reviewSubmitted,
                sourceModule: .module4ClosureEmotion,
                taskId: summary.taskId,
                relatedObjectId: summary.id,
                status: "one_line_note",
                tags: ["closure", "review_note"],
                metadata: [
                    "closure_id": summary.id,
                    "note": trimmed
                ]
            ))
            self.closureReviewNote = ""
            self.message = "Review note saved."
        }
    }

    func markClosureEmotion(_ emotion: EmotionTag) {
        guard let summary = closureSummary else { return }
        run {
            try await self.closureService.markEmotion(summary: summary, emotion: emotion)
            self.closureSummary = self.summaryByUpdatingEmotion(emotion)
            self.message = "Emotion saved. That context helps future support feel more accurate."
        }
    }

    func archiveClosureAndStartNew() {
        guard let summary = closureSummary else { return }
        run {
            try await self.closureService.archiveTask(summary)
            self.resetClosureStateForNextTask()
            self.taskInput = ""
            self.currentTask = nil
            self.pendingPlanDraft = nil
            self.clarificationQuestions = []
            self.activeResult = nil
            self.route = .input
            self.message = "Task archived. A fresh start is ready."
        }
    }

    func archiveClosureAndOpenPersonalCenter() {
        guard let summary = closureSummary else { return }
        run {
            try await self.closureService.archiveTask(summary)
            self.resetClosureStateForNextTask()
            await self.refreshStats()
            self.route = .personalCenter
            self.message = "Task archived in your history."
        }
    }

    private func reloadCurrentTask() async {
        guard let id = currentTask?.id else { return }
        currentTask = try? await repository.getTask(id)
    }

    private func clearStageUpdateUndo() {
        stageUpdateUndoSnapshot = nil
        lastAppliedStageUpdate = nil
        canUndoLastStageUpdate = false
    }

    private func resetClosureStateForNextTask() {
        closureSummary = nil
        pendingPlanDraft = nil
        clarificationQuestions = []
        reviewResponses = [:]
        reviewWasSkipped = false
        feedbackOptions = []
        pendingStageUpdate = nil
        clearStageUpdateUndo()
        postFeedbackMessage = nil
        readyToContinueAfterFeedback = false
        stuckHelp = nil
        interventionPanelVisible = false
    }

    private func agentContextForPlanning() async throws -> AgentContext {
        guard settings.profileLearningEnabled else {
            return AgentContext(
                userProfileSnapshot: .empty,
                recentStatsSummary: try await dataCenter.getStats(range: .last7Days),
                recentSimilarTaskNotes: [],
                privacyMode: .profileDisabled
            )
        }
        return try await agentContextProvider.getContext(for: currentTask?.id, stageId: nil)
    }

    private func hasRemoteAgentCredentials() async -> Bool {
        guard settings.remoteAgentEnabled else { return false }
        if ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"]?.isEmpty == false {
            return true
        }
        return await credentialStore.readDeepSeekAPIKey() != nil
    }

    private func updatePlanningStatus(from task: TaskPlan) {
        let mode = task.metadata["planning_mode"] ?? "local_rules"
        if mode == "deepseek_v4_flash" {
            remoteAgentStatus = "DeepSeek v4 flash planned this task."
        } else if let reason = task.metadata["agent_fallback_reason"], !reason.isEmpty {
            remoteAgentStatus = "Local fallback planned this task. DeepSeek was unavailable."
            message = "Local fallback used: \(reason)"
        } else {
            remoteAgentStatus = "Local fallback planned this task."
        }
    }

    private func planReadyMessage(for task: TaskPlan) -> String {
        if task.metadata["planning_mode"] == "deepseek_v4_flash" {
            return "DeepSeek made a small first step."
        }
        return "A small first step is ready."
    }

    private func planUpdatedMessage(for task: TaskPlan) -> String {
        if let response = task.metadata["agent_response"], !response.isEmpty {
            return response
        }
        if task.metadata["planning_mode"] == "deepseek_v4_flash" {
            return "DeepSeek revised the plan."
        }
        return "Plan updated with local fallback."
    }

    private func restoreLastSession() async {
        guard currentTask == nil else { return }
        do {
            let tasks = try await repository.listTasks()
            guard let task = tasks.first(where: shouldRestore) else { return }
            currentTask = task
            activeResult = nil
            feedbackOptions = []
            pendingStageUpdate = nil
            clearStageUpdateUndo()
            postFeedbackMessage = nil
            readyToContinueAfterFeedback = false
            reviewResponses = [:]
            reviewWasSkipped = false
            if task.status == .draft || task.status == .planned {
                route = .plan
                message = "Your last plan is ready."
            } else {
                route = .execution
                message = "Restored your last learning session."
                await scheduleReminderForActiveStage()
            }
        } catch {
            message = "Could not restore the last session: \(error.localizedDescription)"
        }
    }

    private func startTicker() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.remainingSeconds = try? await self.executionService.remainingSeconds()
                self.updateBreakCountdown()
                self.updateFloatingTimer()
                self.handleTimeoutIfNeeded()
            }
        }
    }

    private func updateBreakCountdown() {
        guard let breakEndsAt else {
            breakRemainingSeconds = nil
            return
        }
        let remaining = max(0, Int(breakEndsAt.timeIntervalSinceNow.rounded(.up)))
        breakRemainingSeconds = remaining
        if remaining == 0 {
            self.breakEndsAt = nil
            message = "Break is done. Your stage is still paused and ready."
        }
    }

    private func updateFloatingTimer() {
        guard route == .execution,
              let stage = activeStage,
              stage.status == .running || stage.status == .overtime,
              let seconds = remainingSeconds else {
            floatingController.hide()
            return
        }
        floatingController.show(
            stageTitle: stage.title,
            remainingSeconds: seconds,
            opacity: settings.floatingTimerOpacity,
            savedOrigin: floatingTimerSavedOrigin,
            onFrameChanged: { [weak self] frame in self?.saveFloatingTimerFrame(frame) },
            onDifficulty: { [weak self] in self?.requestStuckHelp() },
            onExtend: { [weak self] in self?.extendCurrentStageByFiveMinutes() },
            onComplete: { [weak self] in self?.completeStage() }
        )
    }

    private func handleTimeoutIfNeeded() {
        guard let stage = activeStage,
              (stage.status == .running || stage.status == .overtime),
              (remainingSeconds ?? 1) <= 0,
              timeoutPromptedStageId != stage.id else {
            return
        }
        requestTimeoutStuckHelp()
    }

    private func scheduleReminderForActiveStage() async {
        guard settings.notificationsEnabled, let stage = activeStage else { return }
        var allScheduled = true
        if stage.estimatedSeconds > 180 {
            let soonScheduled = await notificationService.scheduleStageReminder(
                identifier: "focusflow.stage.\(stage.id).soon",
                title: "FocusFlow soon",
                body: "Two minutes left. Stop at the next clear edge.",
                secondsFromNow: TimeInterval(max(1, stage.estimatedSeconds - 120))
            )
            allScheduled = allScheduled && soonScheduled
        }
        let checkInScheduled = await notificationService.scheduleStageReminder(
            identifier: "focusflow.stage.\(stage.id).checkin",
            title: "FocusFlow check-in",
            body: "This step is ready for a gentle check-in.",
            secondsFromNow: TimeInterval(max(1, stage.estimatedSeconds))
        )
        allScheduled = allScheduled && checkInScheduled
        if allScheduled {
            notificationFallbackMessage = nil
        } else {
            await activateNotificationFallback(reason: "stage_notification_unavailable", stage: stage)
        }
    }

    private func startFeedbackPrewarmForActiveStage() {
        guard let task = currentTask, let stage = activeStage else { return }
        Task { @MainActor in
            do {
                try await feedbackService.prewarmFeedbackOptions(taskId: task.id, stageId: stage.id)
            } catch {
                await eventBus.publish(LearningEvent(
                    eventType: .agentRunFailed,
                    sourceModule: .module3FeedbackOptimization,
                    taskId: task.id,
                    stageId: stage.id,
                    taskTitle: task.title,
                    taskType: task.taskType,
                    stageTitle: stage.title,
                    stageType: stage.stageType,
                    status: "feedback_prewarm_failed",
                    tags: ["feedback", "prewarm"],
                    metadata: ["error": error.localizedDescription]
                ))
            }
        }
    }

    private func activateNotificationFallback(reason: String, stage: StagePlan?) async {
        notificationFallbackMessage = NotificationFallbackPolicy.floatingTimerMessage(stageTitle: stage?.title)
        message = "Using the floating timer because system notifications are unavailable."
        await eventBus.publish(LearningEvent(
            eventType: .manualCheckIn,
            sourceModule: .module2Execution,
            taskId: currentTask?.id,
            stageId: stage?.id,
            taskTitle: currentTask?.title,
            taskType: currentTask?.taskType,
            stageTitle: stage?.title,
            stageType: stage?.stageType,
            status: "notification_fallback",
            tags: ["notification", "floating_timer", "fallback"],
            metadata: [
                "reason": reason,
                "fallback": "floating_timer"
            ]
        ))
    }

    private var floatingTimerSavedOrigin: CGPoint? {
        guard let x = settings.floatingTimerOriginX,
              let y = settings.floatingTimerOriginY else {
            return nil
        }
        return CGPoint(x: x, y: y)
    }

    private func saveFloatingTimerFrame(_ frame: CGRect) {
        let roundedX = (frame.origin.x * 10).rounded() / 10
        let roundedY = (frame.origin.y * 10).rounded() / 10
        guard settings.floatingTimerOriginX != roundedX || settings.floatingTimerOriginY != roundedY else {
            return
        }
        settings.floatingTimerOriginX = roundedX
        settings.floatingTimerOriginY = roundedY
        let snapshot = settings
        Task {
            try? await settingsService.saveSettings(snapshot)
        }
    }

    private var activeStage: StagePlan? {
        currentTask?.stages.sorted(by: { $0.order < $1.order }).first {
            $0.status == .running || $0.status == .paused || $0.status == .overtime
        }
    }

    private var hasRemainingStage: Bool {
        currentTask?.stages.contains { $0.status == .idle || $0.status == .adjusted } == true
    }

    private func shouldRestore(_ task: TaskPlan) -> Bool {
        guard [.draft, .planned, .active, .paused].contains(task.status) else {
            return false
        }
        return task.stages.contains {
            [.idle, .running, .paused, .overtime, .adjusted].contains($0.status)
        }
    }

    private func installHotkeys() {
        let failedCount = hotKeyManager.register(
            shortcuts: settings.shortcutKeys,
            pauseResume: { [weak self] in self?.pauseOrResume() },
            skip: { [weak self] in
                if self?.feedbackOptions.isEmpty == false {
                    self?.skipFeedbackAndContinue()
                } else if self?.readyToContinueAfterFeedback == true {
                    self?.continueAfterFeedback()
                } else {
                    self?.skipStage()
                }
            },
            voiceInput: { [weak self] in
                guard let self else { return }
                if self.isListeningForVoice {
                    self.stopVoiceInput()
                } else {
                    self.beginVoiceInput()
                }
            },
            markDistraction: { [weak self] in self?.markDistraction() },
            help: { [weak self] in self?.requestStuckHelp() }
        )
        hotKeyStatus = failedCount == 0
            ? "Global shortcuts are active: \(shortcutSummaryText)."
            : "\(failedCount) shortcut\(failedCount == 1 ? "" : "s") could not register because macOS reported a conflict."
    }

    private var shortcutSummaryText: String {
        let keys = settings.shortcutKeys
        return [
            "Pause \(keys.displayText(for: keys.pauseResume))",
            "Skip \(keys.displayText(for: keys.skip))",
            "Voice \(keys.displayText(for: keys.voiceInput))",
            "Distract \(keys.displayText(for: keys.markDistraction))",
            "Help \(keys.displayText(for: keys.help))"
        ].joined(separator: " · ")
    }

    private func applyHotkeySettings() {
        if settings.globalShortcutsEnabled {
            installHotkeys()
        } else {
            hotKeyManager.unregisterAll()
            hotKeyStatus = "Global shortcuts are off."
        }
    }

    private func markDistraction() {
        guard let task = currentTask, let stage = activeStage else {
            message = "No active stage to mark."
            return
        }
        run {
            await self.eventBus.publish(LearningEvent(
                eventType: .stageFeedbackSubmitted,
                sourceModule: .module3FeedbackOptimization,
                taskId: task.id,
                stageId: stage.id,
                taskTitle: task.title,
                taskType: task.taskType,
                stageTitle: stage.title,
                stageType: stage.stageType,
                status: FeedbackIntent.distracted.rawValue,
                tags: ["feedback", "distraction"],
                metadata: ["intent": FeedbackIntent.distracted.rawValue, "trigger": "shortcut"]
            ))
            self.message = "Distraction marked. No judgment, just useful data."
        }
    }

    private func recordVoiceCommand(_ command: VoiceCommandIntent) async {
        await eventBus.publish(LearningEvent(
            eventType: .manualCheckIn,
            sourceModule: .module3FeedbackOptimization,
            taskId: currentTask?.id,
            stageId: activeStage?.id ?? activeResult?.stageId,
            taskTitle: currentTask?.title,
            taskType: currentTask?.taskType,
            stageTitle: activeStage?.title,
            stageType: activeStage?.stageType,
            status: command.rawValue,
            tags: ["voice_command"],
            metadata: [
                "command": command.rawValue,
                "route": "\(route)",
                "has_transcript": "\(voiceTranscript.isEmpty == false)"
            ]
        ))
    }

    private func recordStuckAction(_ action: StuckActionType) async {
        await eventBus.publish(LearningEvent(
            eventType: .interventionTriggered,
            sourceModule: .module3FeedbackOptimization,
            taskId: currentTask?.id,
            stageId: activeStage?.id,
            taskTitle: currentTask?.title,
            taskType: currentTask?.taskType,
            stageTitle: activeStage?.title,
            stageType: activeStage?.stageType,
            status: action.rawValue,
            tags: ["stuck_help", "intervention"],
            metadata: ["action": action.rawValue]
        ))
    }

    private func speakClosureIfNeeded() {
        guard let summary = closureSummary else { return }
        let text = summary.encouragementText ?? summary.soothingText ?? "Your progress is saved."
        speechSynthesizer.speak(text, enabled: settings.voicePromptsEnabled, voiceIdentifier: settings.voiceIdentifier)
    }

    private func summaryByUpdatingReview(itemId: String, confirmed: Bool) -> TaskClosureSummary? {
        guard let summary = closureSummary else { return nil }
        let reviewItems = summary.reviewItems.map { item in
            guard item.id == itemId else { return item }
            return ReviewItem(id: item.id, text: item.text, type: item.type, userConfirmed: confirmed)
        }
        return copySummary(summary, reviewItems: reviewItems, emotionTag: summary.emotionTag)
    }

    private func summaryByUpdatingEmotion(_ emotion: EmotionTag) -> TaskClosureSummary? {
        guard let summary = closureSummary else { return nil }
        return copySummary(summary, reviewItems: summary.reviewItems, emotionTag: emotion)
    }

    private func copySummary(_ summary: TaskClosureSummary, reviewItems: [ReviewItem], emotionTag: EmotionTag?) -> TaskClosureSummary {
        return TaskClosureSummary(
            id: summary.id,
            taskId: summary.taskId,
            closedAt: summary.closedAt,
            closureType: summary.closureType,
            totalPlannedSeconds: summary.totalPlannedSeconds,
            totalFocusSeconds: summary.totalFocusSeconds,
            completedStageCount: summary.completedStageCount,
            skippedStageCount: summary.skippedStageCount,
            abandonedStageCount: summary.abandonedStageCount,
            keyBreakthroughs: summary.keyBreakthroughs,
            encouragementText: summary.encouragementText,
            soothingText: summary.soothingText,
            reviewItems: reviewItems,
            emotionTag: emotionTag,
            archiveEventIds: summary.archiveEventIds
        )
    }

    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        isWorking = true
        Task { @MainActor in
            do {
                try await operation()
                await refreshStats()
            } catch {
                message = error.localizedDescription
            }
            isWorking = false
        }
    }
}
