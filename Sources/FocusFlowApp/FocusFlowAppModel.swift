import Combine
import FocusFlowCore
import Foundation
import AppKit
import SwiftUI

struct StuckHintEntry: Identifiable, Equatable {
    enum Kind: Equatable {
        case hint
        case example
    }

    let id = UUID()
    let kind: Kind
    let text: String
    let hintLevel: Int?

    init(kind: Kind, text: String, hintLevel: Int? = nil) {
        self.kind = kind
        self.text = text
        self.hintLevel = hintLevel
    }

    var label: String {
        switch kind {
        case .hint:
            switch hintLevel ?? 0 {
            case 0: return "Gentle hint"
            case 1: return "Deeper hint"
            default: return "Concrete hint"
            }
        case .example:
            return "Example"
        }
    }

    var symbol: String {
        switch kind {
        case .hint: return "lightbulb"
        case .example: return "text.alignleft"
        }
    }
}

struct PlanningAttachment: Identifiable, Equatable {
    let id: String
    let fileName: String
    let extractedText: String
}

@MainActor
final class FocusFlowAppModel: ObservableObject {
    enum OnboardingStep: Int, CaseIterable {
        case welcome
        case startFocus
        case planReview
        case focusSession
        case saveForLater
        case insights
        case settings

        var numberText: String {
            "\(rawValue + 1) of \(Self.allCases.count)"
        }
    }

    enum Route {
        case home
        case input
        case plan
        case execution
        case closure
        case personalCenter
        case history
        case settings
    }

    enum NavTab: CaseIterable {
        case home
        case focus
        case insights
        case settings
    }

    @Published var route: Route = .home
    @Published var taskInput = ""
    @Published var pendingPlanDraft: TaskPlanDraft?
    @Published var clarificationQuestions: [ClarificationQuestion] = []
    @Published var clarificationAnswerDraft = ""
    @Published var planningAttachments: [PlanningAttachment] = []
    var clarificationTurnNumber: Int { clarificationTurns.count + 1 }
    @Published var currentTask: TaskPlan?
    @Published var activeResult: StageExecutionResult?
    @Published var feedbackOptions: [FeedbackOption] = []
    @Published var feedbackOtherText = ""
    @Published var pendingStageUpdate: StageUpdate?
    @Published var canUndoLastStageUpdate = false
    @Published var postFeedbackMessage: String?
    @Published var readyToContinueAfterFeedback = false
    @Published var stuckHelp: StuckHelpResponse?
    @Published var timeoutDifficultyPrompt: DifficultyPrompt?
    @Published var stuckHintEntries: [StuckHintEntry] = []
    @Published var stuckHintLoading = false
    @Published var stuckEscalationVisible = false
    @Published var interventionPanelVisible = false
    @Published var interventionReason = "This step may be asking for too much right now."
    @Published var closureSummary: TaskClosureSummary?
    @Published var reviewResponses: [String: Bool] = [:]
    @Published var reviewWasSkipped = false
    @Published var stats: StatsSummary?
    @Published var dailyStats: [DailyStatsPoint] = []
    @Published var history: [HistoryTaskCard] = []
    @Published var uncompletedTasks: [TaskPlan] = []
    @Published var achievements: [Achievement] = []
    @Published var pendingAchievements: [Achievement] = []
    @Published var historyKeyword = ""
    @Published var historyRange: StatsRange = .last7Days
    @Published var historyTaskType: EducationTaskType = .unknown
    @Published var naturalHistoryQuery = ""
    @Published var selectedHistoryDetail: HistoryTaskDetail?
    @Published var exportFormat = "Markdown"
    @Published var remainingSeconds: Int?
    @Published var floatingTimerMinimized = false
    @Published var message: String?
    @Published var isWorking = false
    @Published var agentProcessingMessage: String?
    @Published var notificationFallbackMessage: String?
    @Published var remoteAgentStatus = "DeepSeek v4 flash ready when DEEPSEEK_API_KEY is set."
    @Published var hotKeyStatus = "Global shortcuts are ready."
    @Published var readinessReport = AppReadinessReport.empty
    @Published var settings = FocusFlowSettings.defaults
    @Published var onboardingStep: OnboardingStep?
    @Published var deepSeekAPIKeyDraft = ""
    @Published var isListeningForVoice = false
    @Published var voiceTranscript = ""
    @Published var closureReviewNote = ""
    @Published var agentObservation = AgentObservation(
        text: "I am still learning your study rhythm. We will keep using small, clear starts for now.",
        confidence: 0.2
    )
    private var onboardingPreviewTaskId: String?

    var deletableHistoryDay: String? {
        selectedHistoryDetail?.latestLocalDay ?? history.first?.localDay
    }

    var availableVoiceOptions: [SpeechSynthesisService.VoiceOption] {
        SpeechSynthesisService.availableEnglishVoices()
    }

    var isOnboardingExecutionTourStep: Bool {
        onboardingStep == .focusSession || onboardingStep == .saveForLater
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
    private var stuckActionCount = 0
    private var stuckHintLevel = 0
    private var lastStuckRequest: StuckHelpRequest?
    private let maxStuckHintLevel = 2
    private var stageUpdateUndoSnapshot: TaskPlan?
    private var lastAppliedStageUpdate: StageUpdate?
    private var latestNotificationAuthorized: Bool?
    private var clarificationTurns: [TaskPlanningTurn] = []

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
        self.feedbackService = FeedbackOptimizationService(
            repository: repository,
            eventBus: eventBus,
            feedbackAgent: FeedbackAgent(llmClient: llmClient),
            optimizationAgent: PlanOptimizationAgent(llmClient: llmClient)
        )
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
            await refreshUncompletedTasks()
            if settings.notificationsEnabled {
                let authorized = await notificationService.requestAuthorization()
                latestNotificationAuthorized = authorized
                if !authorized {
                    await activateNotificationFallback(reason: "authorization_denied", stage: activeStage)
                }
            }
            await refreshStats()
            await refreshReadiness()
            presentOnboardingIfNeeded()
        }
    }

    func createPlan() {
        let input = taskInput
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "Write one learning task first. It can be messy."
            return
        }
        run(agentMessage: "AI is planning a small first step.") {
            self.resetPlanningClarificationState()
            let canUseRemoteAgent = await self.hasRemoteAgentCredentials()
            self.message = canUseRemoteAgent ? "Planning with DeepSeek v4 flash..." : "No DeepSeek key yet. Using local planning fallback."
            let context = try await self.agentContextForPlanning()
            let draft = try await self.planningService.createDraft(from: input, agentContext: context)
            self.updatePlanningStatus(from: draft.task)
            if !draft.clarificationQuestions.isEmpty {
                self.pendingPlanDraft = draft
                self.clarificationQuestions = draft.clarificationQuestions
                self.message = nil
            } else {
                let plan = try await self.planningService.acceptDraft(draft, clarificationAnswer: nil)
                self.resetPlanningClarificationState()
                self.currentTask = plan
                self.route = .plan
                self.message = self.planReadyMessage(for: plan)
            }
        }
    }

    func applyClarificationHint(_ hint: String) {
        guard !ClarificationHintRules.isAttachmentAction(hint) else { return }
        clarificationAnswerDraft = hint
    }

    func attachPlanningPDF(from url: URL) {
        run {
            guard url.pathExtension.lowercased() == "pdf" else {
                self.message = "Only PDF files are supported right now."
                return
            }
            guard let text = PDFTextExtractor.extractText(from: url) else {
                self.message = "Could not read text from that PDF."
                return
            }
            try self.directory.prepare()
            let storedName = "\(FocusFlowID.make("attachment")).pdf"
            let storedURL = self.directory.attachments.appendingPathComponent(storedName)
            if FileManager.default.fileExists(atPath: storedURL.path) {
                try FileManager.default.removeItem(at: storedURL)
            }
            try FileManager.default.copyItem(at: url, to: storedURL)
            let attachment = PlanningAttachment(id: storedName, fileName: url.lastPathComponent, extractedText: text)
            if self.planningAttachments.count >= 2 {
                self.planningAttachments.removeFirst()
            }
            self.planningAttachments.append(attachment)
            self.message = "Attached \(url.lastPathComponent)."
        }
    }

    func removePlanningAttachment(_ id: String) {
        planningAttachments.removeAll { $0.id == id }
    }

    func submitClarificationAnswer(skip: Bool = false) {
        guard let question = clarificationQuestions.first else {
            clarificationQuestions = []
            return
        }
        let answer = clarificationAnswerDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !skip, answer.isEmpty, planningAttachments.isEmpty, !question.skippable {
            message = "Write a short answer or attach a PDF so we can plan this properly."
            return
        }
        run(agentMessage: "AI is continuing the plan.") {
            if skip {
                self.clarificationTurns.append(TaskPlanningTurn(question: question.question, answer: "(skipped)"))
            } else {
                var combined = answer
                if combined.isEmpty, !self.planningAttachments.isEmpty {
                    combined = "See attached material."
                }
                if !combined.isEmpty || !self.planningAttachments.isEmpty {
                    self.clarificationTurns.append(TaskPlanningTurn(question: question.question, answer: combined))
                }
            }
            let planningContext = TaskPlanningContext(
                rawInput: self.taskInput,
                turns: self.clarificationTurns,
                attachments: self.planningAttachments.map {
                    TaskPlanningAttachment(fileName: $0.fileName, extractedText: $0.extractedText)
                }
            )
            let agentContext = try await self.agentContextForPlanning()
            let draft = try await self.planningService.continuePlanning(context: planningContext, agentContext: agentContext)
            self.updatePlanningStatus(from: draft.task)
            if !draft.clarificationQuestions.isEmpty {
                self.pendingPlanDraft = draft
                self.clarificationQuestions = draft.clarificationQuestions
                self.clarificationAnswerDraft = ""
                self.message = nil
            } else {
                let summary = self.clarificationSummary()
                let plan = try await self.planningService.acceptDraft(draft, clarificationAnswer: summary)
                self.resetPlanningClarificationState()
                self.currentTask = plan
                self.route = .plan
                self.message = self.planReadyMessage(for: plan)
            }
        }
    }

    func answerClarification(_ answer: String?) {
        if let answer, !answer.isEmpty {
            clarificationAnswerDraft = answer
        }
        submitClarificationAnswer(skip: answer == nil)
    }

    func refinePlan(_ instruction: String) {
        guard let task = currentTask else { return }
        run(agentMessage: "AI is revising the plan.") {
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
        run(agentMessage: "AI is regenerating the plan.") {
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
            self.syncFloatingExecutionWindow()
            self.message = "Start with only the current step."
        }
    }

    func pauseOrResume() {
        run {
            if let runtime = try await self.executionService.activeRuntime(), runtime.status == .paused {
                try await self.executionService.resumeCurrentStage(trigger: .user)
                await self.scheduleReminderForActiveStage()
                self.message = "Welcome back. Continuing counts."
            } else {
                try await self.executionService.pauseCurrentStage(trigger: .user)
                await self.notificationService.cancelPendingStageReminders()
                self.message = "Paused. Your place is saved."
            }
            await self.reloadCurrentTask()
        }
    }

    func completeStage() {
        run {
            let result = try await self.executionService.completeCurrentStage(trigger: .user)
            await self.notificationService.cancelPendingStageReminders()
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
            _ = try await self.executionService.extendCurrentStage(seconds: 300, trigger: .user)
            await self.reloadCurrentTask()
            await self.scheduleReminderForActiveStage()
            self.remainingSeconds = try? await self.executionService.remainingSeconds()
            self.timeoutDifficultyPrompt = nil
            self.timeoutPromptedStageId = nil
            let remaining = self.remainingSeconds ?? 0
            self.message = "Added 5 minutes. About \(max(1, remaining / 60)) min left on this step."
        }
    }

    func completeTaskNow() {
        guard let taskId = currentTask?.id else { return }
        run {
            if try await self.executionService.activeRuntime() != nil {
                _ = try await self.executionService.completeCurrentStage(trigger: .user)
            }
            await self.notificationService.cancelPendingStageReminders()
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
            await self.notificationService.cancelPendingStageReminders()
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
            await self.notificationService.cancelPendingStageReminders()
            self.reviewResponses = [:]
            self.reviewWasSkipped = false
            self.speakClosureIfNeeded()
            await self.reloadCurrentTask()
            self.route = .closure
        }
    }

    func saveCurrentTaskForLater(openNewTask: Bool = false) {
        guard currentTask != nil else {
            route = openNewTask ? .input : .home
            return
        }
        run {
            if let runtime = try await self.executionService.activeRuntime(),
               runtime.status == .running || runtime.status == .overtime {
                try await self.executionService.pauseCurrentStage(trigger: .user)
            }
            await self.notificationService.cancelPendingStageReminders()
            await self.reloadCurrentTask()
            await self.refreshUncompletedTasks()
            self.resetActiveExecutionUIState()
            self.closureSummary = nil
            self.currentTask = nil
            self.pendingPlanDraft = nil
            self.clarificationQuestions = []
            self.taskInput = ""
            self.route = openNewTask ? .input : .home
            self.message = openNewTask
                ? "Saved for later. Start a different learning task when ready."
                : "Saved for later. Find it under Unfinished tasks on Home."
        }
    }

    func abandonCurrentTask(reason: String = "You chose to stop this task for now.") {
        guard let taskId = currentTask?.id else { return }
        run {
            self.closureSummary = try await self.closureService.presentAbandonment(taskId: taskId, reason: reason)
            await self.notificationService.cancelPendingStageReminders()
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

    private func proceedAfterFeedback(taskId: String) async throws {
        await reloadCurrentTask()
        postFeedbackMessage = nil
        readyToContinueAfterFeedback = false
        activeResult = nil
        feedbackOptions = []
        pendingStageUpdate = nil
        clearStageUpdateUndo()
        stuckHelp = nil
        timeoutPromptedStageId = nil
        message = nil

        if let task = currentTask,
           let next = task.stages.sorted(by: { $0.order < $1.order }).first(where: { $0.status == .idle || $0.status == .adjusted }) {
            try await executionService.startStage(taskId: task.id, stageId: next.id)
            await reloadCurrentTask()
            startFeedbackPrewarmForActiveStage()
            await scheduleReminderForActiveStage()
        } else {
            closureSummary = try await closureService.presentCompletion(taskId: taskId)
            reviewResponses = [:]
            reviewWasSkipped = false
            speakClosureIfNeeded()
            route = .closure
        }
    }

    func submitFeedback(_ option: FeedbackOption) {
        guard let result = activeResult else { return }
        run(agentMessage: "AI is reviewing your feedback.") {
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
            if let update = outcome.stageUpdate {
                self.pendingStageUpdate = update
                self.message = update.reason
                return
            }
            try await self.proceedAfterFeedback(taskId: result.taskId)
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
            try await self.proceedAfterFeedback(taskId: update.taskId)
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
            try await self.proceedAfterFeedback(taskId: snapshot.id)
        }
    }

    func keepOriginalPlanAfterFeedback() {
        clearStageUpdateUndo()
        pendingStageUpdate = nil
        postFeedbackMessage = nil
        readyToContinueAfterFeedback = false
        guard let taskId = activeResult?.taskId ?? currentTask?.id else { return }
        run {
            try await self.proceedAfterFeedback(taskId: taskId)
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
            try await self.proceedAfterFeedback(taskId: result.taskId)
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
        run(agentMessage: "AI is finding a gentle next step.") {
            let request = try await self.executionService.requestDifficulty(trigger: .userClickedDifficulty)
            self.beginStuckSession(with: request)
            self.stuckActionCount += 1
            self.stuckHelp = try await self.feedbackService.generateStuckHelp(request)
        }
    }

    func requestTimeoutStuckHelp() {
        handleStageTimeout()
    }

    func respondToTimeoutDifficulty(_ option: FeedbackOption) {
        timeoutDifficultyPrompt = nil
        switch option.intent {
        case .completed:
            completeStage()
        case .needMoreTime:
            extendCurrentStageByFiveMinutes()
        case .tooHard, .unclearInstruction:
            requestStuckHelp()
        case .needBreak:
            takeShortBreak()
        case .wantToQuit:
            abandonCurrentTask(reason: "You chose to stop during the time check-in.")
        default:
            requestStuckHelp()
        }
    }

    func dismissTimeoutDifficultyPrompt() {
        timeoutDifficultyPrompt = nil
    }

    private func handleStageTimeout() {
        guard let stage = activeStage else { return }
        timeoutPromptedStageId = stage.id
        timeoutDifficultyPrompt = FeedbackAgent().difficultyPrompt(for: stage)
        setFloatingTimerMinimized(false)
        bringFloatingWindowToFront()
        message = "Time's up for this step. What would help?"

        Task { @MainActor in
            do {
                _ = try await self.executionService.enterOvertimeIfNeeded()
                await self.reloadCurrentTask()
                _ = try await self.executionService.requestDifficulty(trigger: .timeoutNoAction)
            } catch {
                self.message = error.localizedDescription
            }
        }
    }

    private func beginStuckSession(with request: StuckHelpRequest) {
        lastStuckRequest = request
        stuckHintEntries = []
        stuckHintLevel = 0
        stuckEscalationVisible = false
        stuckHintLoading = false
    }

    var canDeepenHint: Bool {
        stuckHintLevel < maxStuckHintLevel
    }

    var activeStageTitle: String? {
        activeStage?.title
    }

    func testDeepSeekConnection() {
        run(agentMessage: "AI is testing the remote agent connection.") {
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
        startBreak(seconds: 180, label: "Paused for a short break. Your place is saved.")
    }

    func takeTenMinuteRest() {
        startBreak(seconds: 600, label: "Paused for a longer rest. Your place is saved.")
    }

    func testFloatingTimer() {
        guard currentTask != nil else {
            message = "Start a task first to preview the floating focus window."
            return
        }
        bringFloatingWindowToFront()
        message = "Floating focus window is visible. Drag it to test placement."
    }

    func bringFloatingWindowToFront() {
        syncFloatingExecutionWindow()
        floatingController.bringToFront()
    }

    func setFloatingTimerMinimized(_ minimized: Bool) {
        floatingTimerMinimized = minimized
        floatingController.setMinimized(minimized)
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
            await self.notificationService.cancelPendingStageReminders()
            var reminderScheduled = false
            if self.settings.notificationsEnabled {
                reminderScheduled = await self.notificationService.scheduleStageReminder(
                    identifier: "focusflow.stage.break.active",
                    title: "FocusFlow break is done",
                    body: "Your place is saved. Come back gently when you are ready.",
                    secondsFromNow: TimeInterval(seconds)
                )
            }
            await self.recordStuckAction(.shortBreak)
            self.interventionPanelVisible = false
            self.message = reminderScheduled ? "\(label) I will remind you." : "\(label) Come back when ready."
            await self.reloadCurrentTask()
        }
    }

    func handleStuckAction(_ action: StuckHelpAction) {
        switch action.actionType {
        case .hint:
            requestNextHint()
        case .example:
            requestStuckExample()
        case .splitSmaller:
            dismissStuckHelp()
            splitActiveStageSmaller()
        case .shortBreak:
            dismissStuckHelp()
            takeShortBreak()
        }
    }

    private func requestNextHint() {
        guard let request = lastStuckRequest, !stuckHintLoading, !isWorking else { return }
        let level = stuckHintLevel
        stuckHintLoading = true
        run(agentMessage: "AI is finding a hint.") {
            defer { self.stuckHintLoading = false }
            let text = try await self.feedbackService.generateHint(request, level: level)
            self.stuckHintEntries.append(StuckHintEntry(kind: .hint, text: text, hintLevel: level))
            self.stuckHintLevel = min(self.stuckHintLevel + 1, self.maxStuckHintLevel)
            await self.recordStuckAction(.hint)
            if !self.canDeepenHint {
                self.stuckEscalationVisible = true
            }
        }
    }

    private func requestStuckExample() {
        guard let request = lastStuckRequest, !stuckHintLoading, !isWorking else { return }
        stuckHintLoading = true
        run(agentMessage: "AI is finding an example.") {
            defer { self.stuckHintLoading = false }
            let text = try await self.feedbackService.generateExample(request)
            self.stuckHintEntries.append(StuckHintEntry(kind: .example, text: text))
            await self.recordStuckAction(.example)
        }
    }

    func dismissStuckHelp() {
        stuckHelp = nil
        stuckHintEntries = []
        stuckHintLevel = 0
        stuckEscalationVisible = false
        stuckHintLoading = false
    }

    /// User-initiated escalation from the stuck sheet into the gentle intervention panel.
    func escalateStuckHelp() {
        dismissStuckHelp()
        showIntervention(reason: "Still hard after a few tries. Let's choose a gentler path together.")
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
        saveCurrentTaskForLater(openNewTask: false)
    }

    func switchTaskFromIntervention() {
        interventionPanelVisible = false
        saveCurrentTaskForLater(openNewTask: true)
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
            await refreshUncompletedTasks()
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
        let notificationAuthorized: Bool?
        if settings.notificationsEnabled {
            notificationAuthorized = await notificationService.currentAuthorizationStatus()
            latestNotificationAuthorized = notificationAuthorized
        } else {
            notificationAuthorized = nil
        }
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
            notificationAuthorized: notificationAuthorized,
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
        run(agentMessage: "AI is interpreting your history query.") {
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
            let hadEncryptionEnabled = settings.localEncryptionEnabled
            settings.localEncryptionEnabled = false
            if hadEncryptionEnabled {
                try await settingsService.saveSettings(settings)
            }
            await applyLocalEncryptionDisabled(migrateLegacyFiles: hadEncryptionEnabled)
            await dataCenter.setProfileLearningEnabled(settings.profileLearningEnabled)
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
            self.settings.localEncryptionEnabled = false
            try await self.settingsService.saveSettings(self.settings)
            await self.applyLocalEncryptionDisabled(migrateLegacyFiles: false)
            await self.dataCenter.setProfileLearningEnabled(self.settings.profileLearningEnabled)
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
                await self.notificationService.cancelPendingFocusFlowReminders()
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

    var activeTab: NavTab {
        switch route {
        case .home: return .home
        case .input, .plan, .execution, .closure: return .focus
        case .personalCenter, .history: return .insights
        case .settings: return .settings
        }
    }

    func openHistory() {
        route = .history
        Task {
            await refreshStats()
        }
    }

    func presentOnboardingIfNeeded() {
        guard !settings.hasCompletedOnboarding else { return }
        startOnboarding()
    }

    func startOnboarding() {
        onboardingStep = .welcome
        applyOnboardingRoute(.welcome)
    }

    func advanceOnboarding() {
        guard let step = onboardingStep else {
            startOnboarding()
            return
        }
        let nextIndex = step.rawValue + 1
        guard nextIndex < OnboardingStep.allCases.count,
              let next = OnboardingStep(rawValue: nextIndex) else {
            completeOnboarding()
            return
        }
        onboardingStep = next
        applyOnboardingRoute(next)
    }

    func goBackOnboarding() {
        guard let step = onboardingStep, step.rawValue > 0,
              let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        onboardingStep = previous
        applyOnboardingRoute(previous)
    }

    func completeOnboarding() {
        clearOnboardingPreviewTask()
        onboardingStep = nil
        settings.hasCompletedOnboarding = true
        syncFloatingExecutionWindow()
        Task { @MainActor in
            try? await settingsService.saveSettings(settings)
        }
    }

    private func applyOnboardingRoute(_ step: OnboardingStep) {
        switch step {
        case .welcome:
            clearOnboardingPreviewTask()
            route = .home
        case .startFocus, .planReview:
            clearOnboardingPreviewTask()
            route = .input
        case .focusSession, .saveForLater:
            if currentTask == nil {
                currentTask = makeOnboardingPreviewTask()
                onboardingPreviewTaskId = currentTask?.id
            }
            route = .execution
            if onboardingPreviewTaskId == nil {
                syncFloatingExecutionWindow()
            }
        case .insights:
            clearOnboardingPreviewTask()
            route = .personalCenter
            Task { await refreshStats() }
        case .settings:
            clearOnboardingPreviewTask()
            route = .settings
        }
        syncFloatingExecutionWindow()
    }

    private func clearOnboardingPreviewTask() {
        guard let previewId = onboardingPreviewTaskId else { return }
        if currentTask?.id == previewId {
            currentTask = nil
        }
        onboardingPreviewTaskId = nil
    }

    private func makeOnboardingPreviewTask() -> TaskPlan {
        let taskId = FocusFlowID.make("tutorial_task")
        return TaskPlan(
            id: taskId,
            originalInput: "Preview: read one short article for class",
            title: "Preview: read one short article",
            taskType: .reading,
            status: .active,
            estimatedTotalSeconds: 900,
            stages: [
                StagePlan(
                    taskId: taskId,
                    order: 1,
                    title: "Open the article and read the first paragraph",
                    instruction: "Only read the first paragraph. Stop before it turns into the whole assignment.",
                    completionCriteria: "The first paragraph is read and one useful phrase is noticed.",
                    stageType: .reading,
                    estimatedSeconds: 300,
                    status: .running,
                    createdBy: .module1TaskPlanning
                ),
                StagePlan(
                    taskId: taskId,
                    order: 2,
                    title: "Write one sentence about the main idea",
                    instruction: "Use plain language. One sentence is enough.",
                    completionCriteria: "One sentence is written.",
                    stageType: .writing,
                    estimatedSeconds: 300,
                    status: .idle,
                    createdBy: .module1TaskPlanning
                ),
                StagePlan(
                    taskId: taskId,
                    order: 3,
                    title: "Save a next-step note",
                    instruction: "Write where you would continue next time.",
                    completionCriteria: "A next-step note exists.",
                    stageType: .reviewing,
                    estimatedSeconds: 300,
                    status: .idle,
                    createdBy: .module1TaskPlanning
                )
            ],
            metadata: [
                "tutorial_preview": "true",
                "planning_mode": "preview"
            ]
        )
    }

    var hasResumableTask: Bool {
        guard let task = currentTask else { return false }
        return isUncompletedTask(task)
    }

    func refreshUncompletedTasks() async {
        do {
            uncompletedTasks = try await repository.listTasks().filter(isUncompletedTask)
        } catch {
            message = "Could not load unfinished tasks: \(error.localizedDescription)"
        }
    }

    func selectTab(_ tab: NavTab) {
        switch tab {
        case .home:
            route = .home
        case .focus:
            enterFocusFlow()
        case .insights:
            route = .personalCenter
            Task { await refreshStats() }
        case .settings:
            route = .settings
        }
    }

    func enterFocusFlow() {
        if closureSummary != nil {
            route = .closure
            return
        }
        guard let task = currentTask else {
            route = .input
            return
        }
        switch task.status {
        case .draft, .planned:
            route = .plan
        case .active, .paused, .gracefullyPaused:
            route = .execution
            syncFloatingExecutionWindow()
        default:
            route = .input
        }
    }

    func resumeTask(_ task: TaskPlan) {
        run {
            let latest = try await self.repository.getTask(task.id)
            guard self.isUncompletedTask(latest) else {
                await self.refreshUncompletedTasks()
                self.message = "That task is already closed."
                return
            }

            self.currentTask = latest
            self.resetActiveExecutionUIState()
            self.closureSummary = nil
            self.taskInput = latest.originalInput

            if latest.status == .draft || latest.status == .planned {
                self.route = .plan
                self.message = "Plan reopened."
                return
            }

            guard let stage = self.nextResumableStage(in: latest) else {
                await self.refreshUncompletedTasks()
                self.message = "No unfinished step found for that task."
                return
            }

            if let runtime = try await self.executionService.activeRuntime(),
               runtime.taskId == latest.id,
               runtime.stageId == stage.id {
                if runtime.status == .paused {
                    try await self.executionService.resumeCurrentStage(trigger: .user)
                }
            } else {
                try await self.executionService.startStage(taskId: latest.id, stageId: stage.id)
            }

            self.currentTask = try await self.repository.getTask(latest.id)
            self.startFeedbackPrewarmForActiveStage()
            await self.scheduleReminderForActiveStage()
            await self.refreshUncompletedTasks()
            self.route = .execution
            self.syncFloatingExecutionWindow()
            self.message = "Task reopened where you can continue."
        }
    }

    func goHome() {
        route = .home
    }

    func beginNewTask() {
        taskInput = ""
        pendingPlanDraft = nil
        clarificationQuestions = []
        route = .input
    }

    func goToFlowStep(_ target: Route) {
        let order: [Route] = [.input, .plan, .execution, .closure]
        guard let current = order.firstIndex(of: route),
              let next = order.firstIndex(of: target),
              next < current else { return }
        // Only allow safe backward navigation within the planning phase.
        if route == .plan, target == .input {
            route = .input
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

    private func resetActiveExecutionUIState() {
        activeResult = nil
        feedbackOptions = []
        pendingStageUpdate = nil
        clearStageUpdateUndo()
        postFeedbackMessage = nil
        readyToContinueAfterFeedback = false
        stuckHelp = nil
        timeoutDifficultyPrompt = nil
        stuckHintEntries = []
        stuckHintLevel = 0
        stuckHintLoading = false
        stuckEscalationVisible = false
        interventionPanelVisible = false
        voiceTranscript = ""
        feedbackOtherText = ""
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

    func clearPlanningClarification() {
        resetPlanningClarificationState()
    }

    private func resetPlanningClarificationState() {
        pendingPlanDraft = nil
        clarificationQuestions = []
        clarificationAnswerDraft = ""
        planningAttachments = []
        clarificationTurns = []
    }

    private func clarificationSummary() -> String? {
        guard !clarificationTurns.isEmpty || !planningAttachments.isEmpty else { return nil }
        var parts: [String] = clarificationTurns.map { "Q: \($0.question)\nA: \($0.answer)" }
        for attachment in planningAttachments {
            parts.append("Attachment: \(attachment.fileName)\n\(attachment.extractedText.prefix(500))")
        }
        return parts.joined(separator: "\n\n")
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
                syncFloatingExecutionWindow()
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
                self.syncFloatingExecutionWindow()
                self.handleTimeoutIfNeeded()
            }
        }
    }

    private func syncFloatingExecutionWindow() {
        guard route == .execution, currentTask != nil, onboardingStep == nil, onboardingPreviewTaskId == nil else {
            floatingController.hide()
            return
        }
        floatingController.show(
            model: self,
            savedOrigin: floatingTimerSavedOrigin,
            onFrameChanged: { [weak self] frame in self?.saveFloatingTimerFrame(frame) }
        )
    }

    private func applyLocalEncryptionDisabled(migrateLegacyFiles: Bool) async {
        await dataCenter.setLocalEncryptionEnabled(false)
        await repository.setLocalEncryptionEnabled(false)
        await runtimeStore.setLocalEncryptionEnabled(false)
        guard migrateLegacyFiles else { return }
        let encryption = LocalEncryptionService()
        do {
            let migratedCount = try await encryption.migrateEncryptedFilesToPlaintext(under: directory.root)
            if migratedCount > 0 {
                message = "Local encryption is off. Converted \(migratedCount) file(s) to plain storage."
            }
        } catch {
            message = "Local encryption is off, but some encrypted files could not be converted: \(error.localizedDescription)"
        }
    }

    private func handleTimeoutIfNeeded() {
        guard timeoutDifficultyPrompt == nil,
              stuckHelp == nil,
              let stage = activeStage,
              stage.status == .running || stage.status == .overtime,
              let remaining = remainingSeconds,
              remaining <= 0,
              timeoutPromptedStageId != stage.id else {
            return
        }
        handleStageTimeout()
    }

    private func scheduleReminderForActiveStage() async {
        guard settings.notificationsEnabled, let stage = activeStage else { return }
        await notificationService.cancelPendingStageReminders()
        let runtimeRemaining: Int
        do {
            runtimeRemaining = try await executionService.remainingSeconds() ?? stage.estimatedSeconds
        } catch {
            runtimeRemaining = stage.estimatedSeconds
        }
        let remaining = max(1, runtimeRemaining)
        var allScheduled = true
        if remaining > 180 {
            let soonScheduled = await notificationService.scheduleStageReminder(
                identifier: "focusflow.stage.\(stage.id).soon",
                title: "FocusFlow soon",
                body: "Two minutes left. Stop at the next clear edge.",
                secondsFromNow: TimeInterval(max(1, remaining - 120))
            )
            allScheduled = allScheduled && soonScheduled
        }
        let checkInScheduled = await notificationService.scheduleStageReminder(
            identifier: "focusflow.stage.\(stage.id).checkin",
            title: "FocusFlow check-in",
            body: "This step is ready for a gentle check-in.",
            secondsFromNow: TimeInterval(remaining)
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
        isUncompletedTask(task)
    }

    private func isUncompletedTask(_ task: TaskPlan) -> Bool {
        guard [.draft, .planned, .active, .paused, .gracefullyPaused].contains(task.status) else {
            return false
        }
        return task.stages.contains {
            [.idle, .running, .paused, .overtime, .adjusted].contains($0.status)
        }
    }

    private func nextResumableStage(in task: TaskPlan) -> StagePlan? {
        let stages = task.stages.sorted { $0.order < $1.order }
        return stages.first { [.running, .paused, .overtime].contains($0.status) }
            ?? stages.first { [.idle, .adjusted].contains($0.status) }
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

    private func run(agentMessage: String? = nil, _ operation: @escaping @MainActor () async throws -> Void) {
        guard !isWorking else { return }
        isWorking = true
        agentProcessingMessage = agentMessage
        Task { @MainActor in
            do {
                try await operation()
                await refreshStats()
            } catch {
                message = error.localizedDescription
            }
            agentProcessingMessage = nil
            isWorking = false
        }
    }
}
