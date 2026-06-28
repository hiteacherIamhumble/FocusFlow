import Foundation

public protocol TaskPlanningServiceProtocol: Sendable {
    func createDraft(from input: String, agentContext: AgentContext?) async throws -> TaskPlanDraft
    func continuePlanning(context: TaskPlanningContext, agentContext: AgentContext?) async throws -> TaskPlanDraft
    func acceptDraft(_ draft: TaskPlanDraft, clarificationAnswer: String?) async throws -> TaskPlan
    func createPlan(from input: String, context: UserProfileSnapshot?) async throws -> TaskPlan
    func createPlan(from input: String, agentContext: AgentContext?) async throws -> TaskPlan
    func refinePlan(_ task: TaskPlan, userInstruction: String) async throws -> TaskPlan
    func regeneratePlan(_ task: TaskPlan, agentContext: AgentContext?) async throws -> TaskPlan
    func updateStage(taskId: String, stageId: String, patch: StagePlanPatch) async throws -> TaskPlan
    func confirmPlan(_ task: TaskPlan) async throws
}

public protocol ExecutionServiceProtocol: Sendable {
    func startTask(_ taskId: String) async throws
    func startStage(taskId: String, stageId: String) async throws
    func pauseCurrentStage(trigger: EventTrigger) async throws
    func resumeCurrentStage(trigger: EventTrigger) async throws
    func completeCurrentStage(trigger: EventTrigger) async throws -> StageExecutionResult
    func skipCurrentStage(trigger: EventTrigger) async throws -> StageExecutionResult
    func abandonCurrentStage(trigger: EventTrigger) async throws -> StageExecutionResult
    func extendCurrentStage(seconds: Int, trigger: EventTrigger) async throws -> StageRuntime
    func applyStageUpdate(_ update: StageUpdate) async throws
    func revertStageUpdate(previousTask: TaskPlan, update: StageUpdate) async throws
}

public protocol FeedbackOptimizationServiceProtocol: Sendable {
    func prewarmFeedbackOptions(taskId: String, stageId: String) async throws
    func prepareFeedbackOptions(taskId: String, stageId: String) async throws -> [FeedbackOption]
    func submitFeedback(_ feedback: StageFeedback) async throws -> FeedbackOptimizationResult
    func handleTimeoutDifficulty(taskId: String, stageId: String, runtime: StageRuntime) async throws -> DifficultyPrompt
    func generateStuckHelp(_ request: StuckHelpRequest) async throws -> StuckHelpResponse
    func generateHint(_ request: StuckHelpRequest, level: Int) async throws -> String
    func generateExample(_ request: StuckHelpRequest) async throws -> String
}

public protocol TaskClosureServiceProtocol: Sendable {
    func presentCompletion(taskId: String) async throws -> TaskClosureSummary
    func presentGracefulPause(taskId: String, reason: String?) async throws -> TaskClosureSummary
    func presentAbandonment(taskId: String, reason: String?) async throws -> TaskClosureSummary
    func markEmotion(summary: TaskClosureSummary, emotion: EmotionTag) async throws
    func submitReview(summary: TaskClosureSummary, item: ReviewItem, confirmed: Bool) async throws
    func skipReview(summary: TaskClosureSummary) async throws
    func archiveTask(_ summary: TaskClosureSummary) async throws
}

public protocol DataCenterServiceProtocol: Sendable {
    func recordEvent(_ event: LearningEvent) async throws
    func replayRetryQueue() async throws -> RetryReplaySummary
    func setLocalEncryptionEnabled(_ enabled: Bool) async
    func setProfileLearningEnabled(_ enabled: Bool) async
    func getStats(range: StatsRange) async throws -> StatsSummary
    func getDailyStats(range: StatsRange) async throws -> [DailyStatsPoint]
    func getUserProfileSnapshot() async throws -> UserProfileSnapshot
    func updateProfileFromRecentEvents() async throws
    func checkAchievements(after event: LearningEvent) async throws -> [Achievement]
    func getUnlockedAchievements() async throws -> [Achievement]
    func getPendingAchievements() async throws -> [Achievement]
    func markAchievementDisplayed(_ achievementId: String) async throws
    func queryHistory(_ query: HistoryQuery) async throws -> [HistoryTaskCard]
    func parseHistoryQuery(_ text: String) async throws -> HistoryQuery
    func getHistoryDetail(taskId: String) async throws -> HistoryTaskDetail
    func deleteHistoryTask(taskId: String) async throws
    func deleteHistoryDay(localDay: String) async throws
    func exportEventsMarkdown() async throws -> String
    func exportEventsJSON() async throws -> String
    func exportEventsCSV() async throws -> String
    func saveClosureSummary(_ summary: TaskClosureSummary) async throws
    func getClosureSummary(taskId: String) async throws -> TaskClosureSummary
    func submitProfileCorrection(_ correction: ProfileCorrection) async throws -> UserProfileSnapshot
    func clearUserProfile() async throws
    func deleteAllUserData() async throws
}

public protocol TaskRepositoryProtocol: Sendable {
    func setLocalEncryptionEnabled(_ enabled: Bool) async
    func save(_ task: TaskPlan) async throws
    func getTask(_ taskId: String) async throws -> TaskPlan
    func update(_ task: TaskPlan) async throws
    func apply(_ update: StageUpdate) async throws -> TaskPlan
    func listTasks() async throws -> [TaskPlan]
    func deleteTask(_ taskId: String) async throws
}

public protocol RuntimeStoreProtocol: Sendable {
    func setLocalEncryptionEnabled(_ enabled: Bool) async
    func save(_ runtime: StageRuntime) async throws
    func loadActiveRuntime() async throws -> StageRuntime?
    func clearActiveRuntime() async throws
}

public protocol AgentContextProviderProtocol: Sendable {
    func getContext(for taskId: String?, stageId: String?) async throws -> AgentContext
}

public struct LLMMessage: Codable, Equatable, Sendable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public protocol LLMClient: Sendable {
    func complete(messages: [LLMMessage], privacyMode: PrivacyMode, responseFormat: LLMResponseFormat?) async throws -> String
}

public enum LLMResponseFormat: String, Codable, Sendable {
    case text
    case jsonObject
}

public struct LocalOnlyLLMClient: LLMClient {
    public init() {}

    public func complete(messages: [LLMMessage], privacyMode: PrivacyMode, responseFormat: LLMResponseFormat?) async throws -> String {
        "Local template mode is active."
    }
}
