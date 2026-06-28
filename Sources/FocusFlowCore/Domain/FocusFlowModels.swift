import Foundation

public enum SourceModule: String, Codable, Sendable {
    case module1TaskPlanning
    case module2Execution
    case module3FeedbackOptimization
    case module4ClosureEmotion
    case module5DataCenter
    case system
}

public enum EducationTaskType: String, Codable, CaseIterable, Sendable {
    case writing
    case reading
    case examReview
    case homework
    case presentation
    case longTermProject
    case unknown
}

public enum StageType: String, Codable, CaseIterable, Sendable {
    case startup
    case reading
    case writing
    case reviewing
    case problemSolving
    case organizing
    case presentationMaking
    case breakTime
    case other
}

public enum TaskStatus: String, Codable, Sendable {
    case draft
    case planned
    case active
    case paused
    case completed
    case gracefullyPaused
    case abandoned
    case archived
    case deleted
}

public enum StageStatus: String, Codable, Sendable {
    case idle
    case running
    case paused
    case overtime
    case completed
    case skipped
    case abandoned
    case adjusted
}

public enum EndReason: String, Codable, Sendable {
    case completedEarly
    case completedOnTime
    case completedAfterOvertime
    case userPaused
    case userSkipped
    case userAbandoned
    case timeoutPrompted
    case appInterrupted
}

public enum EventTrigger: String, Codable, Sendable {
    case user
    case system
    case shortcut
    case voice
}

public struct TaskPlan: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var originalInput: String
    public var title: String
    public var taskType: EducationTaskType
    public var status: TaskStatus
    public var createdAt: Date
    public var updatedAt: Date
    public var deadline: Date?
    public var estimatedTotalSeconds: Int
    public var stages: [StagePlan]
    public var metadata: [String: String]

    public init(
        id: String = FocusFlowID.make("task"),
        originalInput: String,
        title: String,
        taskType: EducationTaskType,
        status: TaskStatus = .draft,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deadline: Date? = nil,
        estimatedTotalSeconds: Int,
        stages: [StagePlan],
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.originalInput = originalInput
        self.title = title
        self.taskType = taskType
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deadline = deadline
        self.estimatedTotalSeconds = estimatedTotalSeconds
        self.stages = stages
        self.metadata = metadata
    }
}

public struct StagePlan: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let taskId: String
    public var order: Int
    public var title: String
    public var instruction: String
    public var completionCriteria: String
    public var stageType: StageType
    public var estimatedSeconds: Int
    public var status: StageStatus
    public var createdBy: SourceModule
    public var parentStageId: String?
    public var metadata: [String: String]

    public init(
        id: String = FocusFlowID.make("stage"),
        taskId: String,
        order: Int,
        title: String,
        instruction: String,
        completionCriteria: String,
        stageType: StageType,
        estimatedSeconds: Int,
        status: StageStatus = .idle,
        createdBy: SourceModule = .module1TaskPlanning,
        parentStageId: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.taskId = taskId
        self.order = order
        self.title = title
        self.instruction = instruction
        self.completionCriteria = completionCriteria
        self.stageType = stageType
        self.estimatedSeconds = estimatedSeconds
        self.status = status
        self.createdBy = createdBy
        self.parentStageId = parentStageId
        self.metadata = metadata
    }
}

public struct StagePlanPatch: Codable, Equatable, Sendable {
    public var title: String?
    public var instruction: String?
    public var completionCriteria: String?
    public var stageType: StageType?
    public var estimatedSeconds: Int?

    public init(
        title: String? = nil,
        instruction: String? = nil,
        completionCriteria: String? = nil,
        stageType: StageType? = nil,
        estimatedSeconds: Int? = nil
    ) {
        self.title = title
        self.instruction = instruction
        self.completionCriteria = completionCriteria
        self.stageType = stageType
        self.estimatedSeconds = estimatedSeconds
    }

    public var changedFields: [String] {
        var fields: [String] = []
        if title != nil { fields.append("title") }
        if instruction != nil { fields.append("instruction") }
        if completionCriteria != nil { fields.append("completion_criteria") }
        if stageType != nil { fields.append("stage_type") }
        if estimatedSeconds != nil { fields.append("estimated_seconds") }
        return fields
    }
}

public struct StageRuntime: Codable, Equatable, Sendable {
    public let taskId: String
    public let stageId: String
    public var status: StageStatus
    public var startedAt: Date?
    public var pauseStartedAt: Date?
    public var pauseTotalSeconds: Int
    public var plannedSeconds: Int
    public var lastTickAt: Date?
    public var monotonicAnchor: TimeInterval?
    public var difficultyHitCount: Int
    public var timeoutPrompted: Bool
    public var pauseCount: Int

    public init(
        taskId: String,
        stageId: String,
        status: StageStatus = .idle,
        startedAt: Date? = nil,
        pauseStartedAt: Date? = nil,
        pauseTotalSeconds: Int = 0,
        plannedSeconds: Int,
        lastTickAt: Date? = nil,
        monotonicAnchor: TimeInterval? = nil,
        difficultyHitCount: Int = 0,
        timeoutPrompted: Bool = false,
        pauseCount: Int = 0
    ) {
        self.taskId = taskId
        self.stageId = stageId
        self.status = status
        self.startedAt = startedAt
        self.pauseStartedAt = pauseStartedAt
        self.pauseTotalSeconds = pauseTotalSeconds
        self.plannedSeconds = plannedSeconds
        self.lastTickAt = lastTickAt
        self.monotonicAnchor = monotonicAnchor
        self.difficultyHitCount = difficultyHitCount
        self.timeoutPrompted = timeoutPrompted
        self.pauseCount = pauseCount
    }
}

public struct StageExecutionResult: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let taskId: String
    public let stageId: String
    public let startedAt: Date
    public let endedAt: Date
    public let plannedSeconds: Int
    public let actualFocusSeconds: Int
    public let pauseCount: Int
    public let pauseTotalSeconds: Int
    public let overtimeSeconds: Int
    public let difficultyHitCount: Int
    public let timeoutPrompted: Bool
    public let endReason: EndReason
    public let endTrigger: EventTrigger
    public let localDay: String

    public init(
        id: String = FocusFlowID.make("result"),
        taskId: String,
        stageId: String,
        startedAt: Date,
        endedAt: Date,
        plannedSeconds: Int,
        actualFocusSeconds: Int,
        pauseCount: Int,
        pauseTotalSeconds: Int,
        overtimeSeconds: Int,
        difficultyHitCount: Int,
        timeoutPrompted: Bool,
        endReason: EndReason,
        endTrigger: EventTrigger,
        localDay: String = FocusFlowCalendar.localDay()
    ) {
        self.id = id
        self.taskId = taskId
        self.stageId = stageId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.plannedSeconds = plannedSeconds
        self.actualFocusSeconds = actualFocusSeconds
        self.pauseCount = pauseCount
        self.pauseTotalSeconds = pauseTotalSeconds
        self.overtimeSeconds = overtimeSeconds
        self.difficultyHitCount = difficultyHitCount
        self.timeoutPrompted = timeoutPrompted
        self.endReason = endReason
        self.endTrigger = endTrigger
        self.localDay = localDay
    }
}

public struct StageFeedback: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let taskId: String
    public let stageId: String
    public let executionResultId: String
    public let submittedAt: Date
    public let selectedLabel: String?
    public let freeText: String?
    public let voiceTranscript: String?
    public let otherText: String?
    public let intent: FeedbackIntent
    public let difficulty: DifficultyLevel?
    public let granularity: GranularityFeedback?
    public let emotionTag: EmotionTag?
    public let skipped: Bool
    public let metadata: [String: String]

    public init(
        id: String = FocusFlowID.make("feedback"),
        taskId: String,
        stageId: String,
        executionResultId: String,
        submittedAt: Date = Date(),
        selectedLabel: String? = nil,
        freeText: String? = nil,
        voiceTranscript: String? = nil,
        otherText: String? = nil,
        intent: FeedbackIntent,
        difficulty: DifficultyLevel? = nil,
        granularity: GranularityFeedback? = nil,
        emotionTag: EmotionTag? = nil,
        skipped: Bool = false,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.taskId = taskId
        self.stageId = stageId
        self.executionResultId = executionResultId
        self.submittedAt = submittedAt
        self.selectedLabel = selectedLabel
        self.freeText = freeText
        self.voiceTranscript = voiceTranscript
        self.otherText = otherText
        self.intent = intent
        self.difficulty = difficulty
        self.granularity = granularity
        self.emotionTag = emotionTag
        self.skipped = skipped
        self.metadata = metadata
    }
}

public enum FeedbackIntent: String, Codable, Sendable {
    case completed
    case tooHard
    case distracted
    case needBreak
    case needMoreTime
    case unclearInstruction
    case wantToQuit
    case other
    case skippedFeedback
}

public enum DifficultyLevel: String, Codable, Sendable {
    case easy
    case normal
    case hard
    case tooHard
}

public enum GranularityFeedback: String, Codable, Sendable {
    case tooSmall
    case justRight
    case tooLarge
}

public enum EmotionTag: String, Codable, Sendable {
    case calm
    case happy
    case tired
    case frustrated
    case overwhelmed
    case anxious
    case unknown
}

public struct StageUpdate: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let taskId: String
    public let sourceStageId: String?
    public let updateScope: StageUpdateScope
    public let updatedStages: [StagePlan]
    public let removedStageIds: [String]
    public let reason: String
    public let requiresUserConfirmation: Bool
    public let createdAt: Date

    public init(
        id: String = FocusFlowID.make("update"),
        taskId: String,
        sourceStageId: String?,
        updateScope: StageUpdateScope,
        updatedStages: [StagePlan],
        removedStageIds: [String] = [],
        reason: String,
        requiresUserConfirmation: Bool,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.taskId = taskId
        self.sourceStageId = sourceStageId
        self.updateScope = updateScope
        self.updatedStages = updatedStages
        self.removedStageIds = removedStageIds
        self.reason = reason
        self.requiresUserConfirmation = requiresUserConfirmation
        self.createdAt = createdAt
    }
}

public enum StageUpdateScope: String, Codable, Sendable {
    case currentStageOnly
    case remainingStages
    case entireTask
}

public struct TaskClosureSummary: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let taskId: String
    public let closedAt: Date
    public let closureType: TaskClosureType
    public let totalPlannedSeconds: Int
    public let totalFocusSeconds: Int
    public let completedStageCount: Int
    public let skippedStageCount: Int
    public let abandonedStageCount: Int
    public let keyBreakthroughs: [String]
    public let encouragementText: String?
    public let soothingText: String?
    public let reviewItems: [ReviewItem]
    public let emotionTag: EmotionTag?
    public let archiveEventIds: [String]

    public init(
        id: String = FocusFlowID.make("closure"),
        taskId: String,
        closedAt: Date = Date(),
        closureType: TaskClosureType,
        totalPlannedSeconds: Int,
        totalFocusSeconds: Int,
        completedStageCount: Int,
        skippedStageCount: Int,
        abandonedStageCount: Int,
        keyBreakthroughs: [String],
        encouragementText: String?,
        soothingText: String?,
        reviewItems: [ReviewItem],
        emotionTag: EmotionTag?,
        archiveEventIds: [String] = []
    ) {
        self.id = id
        self.taskId = taskId
        self.closedAt = closedAt
        self.closureType = closureType
        self.totalPlannedSeconds = totalPlannedSeconds
        self.totalFocusSeconds = totalFocusSeconds
        self.completedStageCount = completedStageCount
        self.skippedStageCount = skippedStageCount
        self.abandonedStageCount = abandonedStageCount
        self.keyBreakthroughs = keyBreakthroughs
        self.encouragementText = encouragementText
        self.soothingText = soothingText
        self.reviewItems = reviewItems
        self.emotionTag = emotionTag
        self.archiveEventIds = archiveEventIds
    }
}

public enum TaskClosureType: String, Codable, Sendable {
    case completed
    case gracefullyPaused
    case abandoned
    case archivedOnly
}

public struct ReviewItem: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let text: String
    public let type: ReviewItemType
    public var userConfirmed: Bool?

    public init(
        id: String = FocusFlowID.make("review"),
        text: String,
        type: ReviewItemType,
        userConfirmed: Bool? = nil
    ) {
        self.id = id
        self.text = text
        self.type = type
        self.userConfirmed = userConfirmed
    }
}

public enum ReviewItemType: String, Codable, Sendable {
    case highlight
    case suggestion
    case userNote
}

public struct LearningEvent: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let eventType: LearningEventType
    public let sourceModule: SourceModule
    public let timestamp: Date
    public let localDay: String
    public let timezoneIdentifier: String
    public let taskId: String?
    public let stageId: String?
    public let relatedObjectId: String?
    public let taskTitle: String?
    public let taskType: EducationTaskType?
    public let stageTitle: String?
    public let stageType: StageType?
    public let status: String?
    public let plannedDurationSeconds: Int?
    public let actualFocusSeconds: Int?
    public let pauseCount: Int?
    public let tags: [String]
    public let metadata: [String: String]

    public init(
        id: String = FocusFlowID.make("evt"),
        eventType: LearningEventType,
        sourceModule: SourceModule,
        timestamp: Date = Date(),
        localDay: String = FocusFlowCalendar.localDay(),
        timezoneIdentifier: String = TimeZone.current.identifier,
        taskId: String? = nil,
        stageId: String? = nil,
        relatedObjectId: String? = nil,
        taskTitle: String? = nil,
        taskType: EducationTaskType? = nil,
        stageTitle: String? = nil,
        stageType: StageType? = nil,
        status: String? = nil,
        plannedDurationSeconds: Int? = nil,
        actualFocusSeconds: Int? = nil,
        pauseCount: Int? = nil,
        tags: [String] = [],
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.eventType = eventType
        self.sourceModule = sourceModule
        self.timestamp = timestamp
        self.localDay = localDay
        self.timezoneIdentifier = timezoneIdentifier
        self.taskId = taskId
        self.stageId = stageId
        self.relatedObjectId = relatedObjectId
        self.taskTitle = taskTitle
        self.taskType = taskType
        self.stageTitle = stageTitle
        self.stageType = stageType
        self.status = status
        self.plannedDurationSeconds = plannedDurationSeconds
        self.actualFocusSeconds = actualFocusSeconds
        self.pauseCount = pauseCount
        self.tags = tags
        self.metadata = metadata
    }
}

public enum LearningEventType: String, Codable, Sendable {
    case taskCreated
    case taskPlanConfirmed
    case taskPlanUpdated
    case stageStarted
    case stagePaused
    case stageResumed
    case stageCompleted
    case stageSkipped
    case stageAbandoned
    case stageTimeoutPrompted
    case stageDifficultyRequested
    case stuckHelpRequested
    case runtimeExtended
    case stageFeedbackSubmitted
    case stageAdjusted
    case interventionTriggered
    case taskCompleted
    case taskGracefullyPaused
    case taskAbandoned
    case taskArchived
    case emotionMarked
    case reviewSubmitted
    case agentRunStarted
    case agentRunCompleted
    case agentRunFailed
    case achievementUnlocked
    case manualCheckIn
    case profileCorrectionSubmitted
    case eventWriteRetried
    case dataExported
    case dataDeleted
}

public struct RetryReplaySummary: Codable, Equatable, Sendable {
    public let replayedCount: Int
    public let skippedDuplicateCount: Int
    public let failedCount: Int
    public let queueFileCount: Int

    public init(
        replayedCount: Int,
        skippedDuplicateCount: Int,
        failedCount: Int,
        queueFileCount: Int
    ) {
        self.replayedCount = replayedCount
        self.skippedDuplicateCount = skippedDuplicateCount
        self.failedCount = failedCount
        self.queueFileCount = queueFileCount
    }
}

public struct ProfileCorrection: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let submittedAt: Date
    public let reason: String
    public let affectedStageTypes: [StageType]
    public let note: String?
    public let confidenceImpact: Double

    public init(
        id: String = FocusFlowID.make("profileCorrection"),
        submittedAt: Date = Date(),
        reason: String,
        affectedStageTypes: [StageType] = [],
        note: String? = nil,
        confidenceImpact: Double = 0.25
    ) {
        self.id = id
        self.submittedAt = submittedAt
        self.reason = reason
        self.affectedStageTypes = affectedStageTypes
        self.note = note
        self.confidenceImpact = confidenceImpact
    }
}

public struct UserProfileSnapshot: Codable, Equatable, Sendable {
    public let preferredStageDurationSeconds: Int?
    public let recommendedFirstStageSeconds: Int?
    public let difficultStageTypes: [StageType]
    public let easierStageTypes: [StageType]
    public let effectiveInterventions: [InterventionType]
    public let encouragementStyle: EncouragementStyle
    public let rewardPreference: RewardPreference
    public let streakSensitivity: SensitivityLevel
    public let confidence: Double
    public let lastUpdatedAt: Date

    public init(
        preferredStageDurationSeconds: Int? = nil,
        recommendedFirstStageSeconds: Int? = nil,
        difficultStageTypes: [StageType] = [],
        easierStageTypes: [StageType] = [],
        effectiveInterventions: [InterventionType] = [],
        encouragementStyle: EncouragementStyle = .gentleDirect,
        rewardPreference: RewardPreference = .quietBadge,
        streakSensitivity: SensitivityLevel = .medium,
        confidence: Double = 0,
        lastUpdatedAt: Date = Date()
    ) {
        self.preferredStageDurationSeconds = preferredStageDurationSeconds
        self.recommendedFirstStageSeconds = recommendedFirstStageSeconds
        self.difficultStageTypes = difficultStageTypes
        self.easierStageTypes = easierStageTypes
        self.effectiveInterventions = effectiveInterventions
        self.encouragementStyle = encouragementStyle
        self.rewardPreference = rewardPreference
        self.streakSensitivity = streakSensitivity
        self.confidence = confidence
        self.lastUpdatedAt = lastUpdatedAt
    }

    public static let empty = UserProfileSnapshot()
}

public enum InterventionType: String, Codable, Sendable {
    case splitSmaller
    case addShortBreak
    case simplifyInstruction
    case extendTime
    case switchTask
    case bodyDoubleEncouragement
}

public enum EncouragementStyle: String, Codable, Sendable {
    case gentleDirect
    case playful
    case quiet
    case minimal
}

public enum RewardPreference: String, Codable, Sendable {
    case quietBadge
    case softAnimation
    case noPopup
    case voiceEncouragement
}

public enum SensitivityLevel: String, Codable, Sendable {
    case low
    case medium
    case high
}

public struct TaskPlanningTurn: Codable, Equatable, Sendable {
    public let question: String
    public let answer: String

    public init(question: String, answer: String) {
        self.question = question
        self.answer = answer
    }
}

public struct TaskPlanningAttachment: Codable, Equatable, Sendable {
    public let fileName: String
    public let extractedText: String

    public init(fileName: String, extractedText: String) {
        self.fileName = fileName
        self.extractedText = extractedText
    }
}

public struct TaskPlanningContext: Codable, Equatable, Sendable {
    public let rawInput: String
    public let turns: [TaskPlanningTurn]
    public let attachments: [TaskPlanningAttachment]

    public init(
        rawInput: String,
        turns: [TaskPlanningTurn] = [],
        attachments: [TaskPlanningAttachment] = []
    ) {
        self.rawInput = rawInput
        self.turns = turns
        self.attachments = attachments
    }
}

public struct TaskInputRequest: Codable, Equatable, Sendable {
    public let rawInput: String
    public let createdAt: Date
    public let userProfileSnapshot: UserProfileSnapshot?
    public let agentContext: AgentContext?

    public init(
        rawInput: String,
        createdAt: Date = Date(),
        userProfileSnapshot: UserProfileSnapshot?,
        agentContext: AgentContext? = nil
    ) {
        self.rawInput = rawInput
        self.createdAt = createdAt
        self.userProfileSnapshot = userProfileSnapshot
        self.agentContext = agentContext
    }
}

public struct TaskPlanDraft: Codable, Equatable, Sendable {
    public let task: TaskPlan
    public let confidence: Double
    public let clarificationQuestions: [ClarificationQuestion]

    public init(task: TaskPlan, confidence: Double, clarificationQuestions: [ClarificationQuestion]) {
        self.task = task
        self.confidence = confidence
        self.clarificationQuestions = clarificationQuestions
    }
}

public struct ClarificationQuestion: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let question: String
    public let placeholder: String?
    public let hintOptions: [String]
    public let allowsFileUpload: Bool
    public let skippable: Bool

    /// Legacy alias used by older UI code paths.
    public var options: [String] { hintOptions }

    public init(
        id: String = FocusFlowID.make("question"),
        question: String,
        placeholder: String? = nil,
        hintOptions: [String] = [],
        allowsFileUpload: Bool = false,
        skippable: Bool = true
    ) {
        self.id = id
        self.question = question
        self.placeholder = placeholder
        self.hintOptions = hintOptions
        self.allowsFileUpload = allowsFileUpload
        self.skippable = skippable
    }

    enum CodingKeys: String, CodingKey {
        case id
        case question
        case placeholder
        case hintOptions
        case options
        case allowsFileUpload
        case skippable
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? FocusFlowID.make("question")
        question = try container.decode(String.self, forKey: .question)
        placeholder = try container.decodeIfPresent(String.self, forKey: .placeholder)
        hintOptions = try container.decodeIfPresent([String].self, forKey: .hintOptions)
            ?? container.decodeIfPresent([String].self, forKey: .options)
            ?? []
        allowsFileUpload = try container.decodeIfPresent(Bool.self, forKey: .allowsFileUpload) ?? false
        skippable = try container.decodeIfPresent(Bool.self, forKey: .skippable) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(question, forKey: .question)
        try container.encodeIfPresent(placeholder, forKey: .placeholder)
        try container.encode(hintOptions, forKey: .hintOptions)
        try container.encode(allowsFileUpload, forKey: .allowsFileUpload)
        try container.encode(skippable, forKey: .skippable)
    }
}

public struct FeedbackOption: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let emoji: String?
    public let intent: FeedbackIntent

    public init(id: String = FocusFlowID.make("option"), label: String, emoji: String?, intent: FeedbackIntent) {
        self.id = id
        self.label = label
        self.emoji = emoji
        self.intent = intent
    }
}

public struct DifficultyPrompt: Codable, Equatable, Sendable {
    public let promptText: String
    public let options: [FeedbackOption]

    public init(promptText: String, options: [FeedbackOption]) {
        self.promptText = promptText
        self.options = options
    }
}

public struct FeedbackOptimizationResult: Codable, Equatable, Sendable {
    public let feedback: StageFeedback
    public let stageUpdate: StageUpdate?
    public let interventionRequest: InterventionRequest?
    public let lightweightMessage: String?

    public init(
        feedback: StageFeedback,
        stageUpdate: StageUpdate?,
        interventionRequest: InterventionRequest?,
        lightweightMessage: String?
    ) {
        self.feedback = feedback
        self.stageUpdate = stageUpdate
        self.interventionRequest = interventionRequest
        self.lightweightMessage = lightweightMessage
    }
}

public struct InterventionRequest: Codable, Equatable, Sendable {
    public let taskId: String
    public let stageId: String?
    public let interruptionType: InterruptionType
    public let urgency: InterventionUrgency
    public let lastFeedback: StageFeedback?
    public let suggestedTone: EncouragementStyle
    public let createdAt: Date

    public init(
        taskId: String,
        stageId: String?,
        interruptionType: InterruptionType,
        urgency: InterventionUrgency,
        lastFeedback: StageFeedback?,
        suggestedTone: EncouragementStyle,
        createdAt: Date = Date()
    ) {
        self.taskId = taskId
        self.stageId = stageId
        self.interruptionType = interruptionType
        self.urgency = urgency
        self.lastFeedback = lastFeedback
        self.suggestedTone = suggestedTone
        self.createdAt = createdAt
    }
}

public enum InterruptionType: String, Codable, Sendable {
    case repeatedIncomplete
    case activeQuit
    case longNoResponse
    case emotionalOverload
}

public enum InterventionUrgency: String, Codable, Sendable {
    case low
    case medium
    case high
}

public struct StuckHelpRequest: Codable, Equatable, Sendable {
    public let taskId: String
    public let stageId: String
    public let taskTitle: String
    public let stageTitle: String
    public let instruction: String
    public let stageType: StageType
    public let plannedSeconds: Int
    public let elapsedSeconds: Int
    public let trigger: StuckTrigger

    public init(
        taskId: String,
        stageId: String,
        taskTitle: String,
        stageTitle: String,
        instruction: String,
        stageType: StageType = .other,
        plannedSeconds: Int,
        elapsedSeconds: Int,
        trigger: StuckTrigger
    ) {
        self.taskId = taskId
        self.stageId = stageId
        self.taskTitle = taskTitle
        self.stageTitle = stageTitle
        self.instruction = instruction
        self.stageType = stageType
        self.plannedSeconds = plannedSeconds
        self.elapsedSeconds = elapsedSeconds
        self.trigger = trigger
    }
}

public enum StuckTrigger: String, Codable, Sendable {
    case userClickedDifficulty
    case timeoutNoAction
}

public struct StuckHelpResponse: Codable, Equatable, Sendable {
    public let comfortText: String
    public let nextSmallStep: String
    public let actions: [StuckHelpAction]

    public init(comfortText: String, nextSmallStep: String, actions: [StuckHelpAction]) {
        self.comfortText = comfortText
        self.nextSmallStep = nextSmallStep
        self.actions = actions
    }
}

public struct StuckHelpAction: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let actionType: StuckActionType

    public init(id: String = FocusFlowID.make("stuckAction"), title: String, actionType: StuckActionType) {
        self.id = id
        self.title = title
        self.actionType = actionType
    }
}

public enum StuckActionType: String, Codable, Sendable {
    case hint
    case splitSmaller
    case example
    case shortBreak
}

public struct StatsSummary: Codable, Equatable, Sendable {
    public let range: StatsRange
    public let activeDays: Int
    public let strictStreakDays: Int
    public let gentleRhythmText: String
    public let totalFocusSeconds: Int
    public let completedStageCount: Int
    public let stageCompletionRate: Double?
    public let taskCompletionRate: Double?
    public let recoveryCount: Int

    public init(
        range: StatsRange,
        activeDays: Int,
        strictStreakDays: Int,
        gentleRhythmText: String,
        totalFocusSeconds: Int,
        completedStageCount: Int,
        stageCompletionRate: Double?,
        taskCompletionRate: Double?,
        recoveryCount: Int
    ) {
        self.range = range
        self.activeDays = activeDays
        self.strictStreakDays = strictStreakDays
        self.gentleRhythmText = gentleRhythmText
        self.totalFocusSeconds = totalFocusSeconds
        self.completedStageCount = completedStageCount
        self.stageCompletionRate = stageCompletionRate
        self.taskCompletionRate = taskCompletionRate
        self.recoveryCount = recoveryCount
    }
}

public struct DailyStatsPoint: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let localDay: String
    public let focusSeconds: Int
    public let completedStageCount: Int
    public let recoveryCount: Int

    public init(
        id: String? = nil,
        localDay: String,
        focusSeconds: Int,
        completedStageCount: Int,
        recoveryCount: Int
    ) {
        self.id = id ?? localDay
        self.localDay = localDay
        self.focusSeconds = focusSeconds
        self.completedStageCount = completedStageCount
        self.recoveryCount = recoveryCount
    }
}

public enum StatsRange: String, Codable, Sendable {
    case today
    case last7Days
    case last30Days
    case thisMonth
    case allTime
}

public struct HistoryQuery: Codable, Equatable, Sendable {
    public let dateRange: StatsRange?
    public let keyword: String?
    public let taskTypes: [EducationTaskType]
    public let stageTypes: [StageType]
    public let statuses: [String]

    public init(
        dateRange: StatsRange? = nil,
        keyword: String? = nil,
        taskTypes: [EducationTaskType] = [],
        stageTypes: [StageType] = [],
        statuses: [String] = []
    ) {
        self.dateRange = dateRange
        self.keyword = keyword
        self.taskTypes = taskTypes
        self.stageTypes = stageTypes
        self.statuses = statuses
    }
}

public struct HistoryTaskCard: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let taskId: String
    public let title: String
    public let taskType: EducationTaskType?
    public let localDay: String
    public let status: String?
    public let completedStageCount: Int
    public let totalFocusSeconds: Int

    public init(
        id: String = FocusFlowID.make("history"),
        taskId: String,
        title: String,
        taskType: EducationTaskType?,
        localDay: String,
        status: String?,
        completedStageCount: Int,
        totalFocusSeconds: Int
    ) {
        self.id = id
        self.taskId = taskId
        self.title = title
        self.taskType = taskType
        self.localDay = localDay
        self.status = status
        self.completedStageCount = completedStageCount
        self.totalFocusSeconds = totalFocusSeconds
    }
}

public struct HistoryStageRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let stageId: String?
    public let title: String
    public let stageType: StageType?
    public let status: String?
    public let localDay: String
    public let plannedSeconds: Int?
    public let actualFocusSeconds: Int?
    public let pauseCount: Int?

    public init(
        id: String = FocusFlowID.make("historyStage"),
        stageId: String?,
        title: String,
        stageType: StageType?,
        status: String?,
        localDay: String,
        plannedSeconds: Int?,
        actualFocusSeconds: Int?,
        pauseCount: Int?
    ) {
        self.id = id
        self.stageId = stageId
        self.title = title
        self.stageType = stageType
        self.status = status
        self.localDay = localDay
        self.plannedSeconds = plannedSeconds
        self.actualFocusSeconds = actualFocusSeconds
        self.pauseCount = pauseCount
    }
}

public struct HistoryTaskDetail: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let taskId: String
    public let title: String
    public let taskType: EducationTaskType?
    public let firstLocalDay: String
    public let latestLocalDay: String
    public let status: String?
    public let totalFocusSeconds: Int
    public let completedStageCount: Int
    public let skippedStageCount: Int
    public let abandonedStageCount: Int
    public let stages: [HistoryStageRecord]
    public let eventCount: Int

    public init(
        id: String = FocusFlowID.make("historyDetail"),
        taskId: String,
        title: String,
        taskType: EducationTaskType?,
        firstLocalDay: String,
        latestLocalDay: String,
        status: String?,
        totalFocusSeconds: Int,
        completedStageCount: Int,
        skippedStageCount: Int,
        abandonedStageCount: Int,
        stages: [HistoryStageRecord],
        eventCount: Int
    ) {
        self.id = id
        self.taskId = taskId
        self.title = title
        self.taskType = taskType
        self.firstLocalDay = firstLocalDay
        self.latestLocalDay = latestLocalDay
        self.status = status
        self.totalFocusSeconds = totalFocusSeconds
        self.completedStageCount = completedStageCount
        self.skippedStageCount = skippedStageCount
        self.abandonedStageCount = abandonedStageCount
        self.stages = stages
        self.eventCount = eventCount
    }
}

public struct Achievement: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let message: String
    public let unlockedAt: Date
    public let iconName: String

    public init(
        id: String,
        title: String,
        message: String,
        unlockedAt: Date = Date(),
        iconName: String
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.unlockedAt = unlockedAt
        self.iconName = iconName
    }
}

public struct AchievementDefinition: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let message: String
    public let iconName: String

    public init(id: String, title: String, message: String, iconName: String) {
        self.id = id
        self.title = title
        self.message = message
        self.iconName = iconName
    }

    public func unlocked(at date: Date = Date()) -> Achievement {
        Achievement(
            id: id,
            title: title,
            message: message,
            unlockedAt: date,
            iconName: iconName
        )
    }
}

public enum AchievementCatalog {
    public static let all: [AchievementDefinition] = [
        AchievementDefinition(
            id: "tiny_start",
            title: "Tiny Start",
            message: "You started. That small move matters.",
            iconName: "leaf"
        ),
        AchievementDefinition(
            id: "first_stage",
            title: "First Step Done",
            message: "One stage is enough to make the task real.",
            iconName: "checkmark.circle"
        ),
        AchievementDefinition(
            id: "gentle_return",
            title: "Gentle Return",
            message: "Coming back counts. You did that three times.",
            iconName: "arrow.uturn.left.circle"
        ),
        AchievementDefinition(
            id: "ten_small_steps",
            title: "Ten Small Steps",
            message: "Ten completed stages, each one a real piece of progress.",
            iconName: "list.number"
        ),
        AchievementDefinition(
            id: "sixty_minutes",
            title: "Sixty Quiet Minutes",
            message: "Your focused minutes have added up gently.",
            iconName: "clock.badge.checkmark"
        ),
        AchievementDefinition(
            id: "first_loop_closed",
            title: "First Loop Closed",
            message: "You brought a learning task to a kind stopping point.",
            iconName: "checkmark.seal"
        ),
        AchievementDefinition(
            id: "noticed_distraction",
            title: "Noticed Gently",
            message: "You marked distraction three times. Awareness is useful data.",
            iconName: "eye"
        )
    ]

    public static func definition(for id: String) -> AchievementDefinition? {
        all.first { $0.id == id }
    }

    public static func achievement(id: String, unlockedAt date: Date = Date()) -> Achievement? {
        definition(for: id)?.unlocked(at: date)
    }
}

public enum PrivacyMode: String, Codable, Sendable {
    case localOnly
    case remoteLLMAllowedForCurrentContext
    case profileDisabled
}

public struct AgentContext: Codable, Equatable, Sendable {
    public let userProfileSnapshot: UserProfileSnapshot
    public let recentStatsSummary: StatsSummary?
    public let recentSimilarTaskNotes: [String]
    public let privacyMode: PrivacyMode

    public init(
        userProfileSnapshot: UserProfileSnapshot,
        recentStatsSummary: StatsSummary?,
        recentSimilarTaskNotes: [String],
        privacyMode: PrivacyMode
    ) {
        self.userProfileSnapshot = userProfileSnapshot
        self.recentStatsSummary = recentStatsSummary
        self.recentSimilarTaskNotes = recentSimilarTaskNotes
        self.privacyMode = privacyMode
    }
}

public struct FocusFlowSettings: Codable, Equatable, Sendable {
    public var notificationsEnabled: Bool
    public var floatingTimerOpacity: Double
    public var floatingTimerOriginX: Double?
    public var floatingTimerOriginY: Double?
    public var voicePromptsEnabled: Bool
    public var voiceInputEnabled: Bool
    public var voiceIdentifier: String?
    public var globalShortcutsEnabled: Bool
    public var achievementsToastEnabled: Bool
    public var profileLearningEnabled: Bool
    public var remoteAgentEnabled: Bool
    public var localEncryptionEnabled: Bool
    public var privacyMode: PrivacyMode
    public var shortcutKeys: FocusFlowShortcutSettings

    public init(
        notificationsEnabled: Bool = true,
        floatingTimerOpacity: Double = 0.85,
        floatingTimerOriginX: Double? = nil,
        floatingTimerOriginY: Double? = nil,
        voicePromptsEnabled: Bool = false,
        voiceInputEnabled: Bool = false,
        voiceIdentifier: String? = nil,
        globalShortcutsEnabled: Bool = true,
        achievementsToastEnabled: Bool = true,
        profileLearningEnabled: Bool = true,
        remoteAgentEnabled: Bool = true,
        localEncryptionEnabled: Bool = false,
        privacyMode: PrivacyMode = .remoteLLMAllowedForCurrentContext,
        shortcutKeys: FocusFlowShortcutSettings = .defaults
    ) {
        self.notificationsEnabled = notificationsEnabled
        self.floatingTimerOpacity = floatingTimerOpacity
        self.floatingTimerOriginX = floatingTimerOriginX
        self.floatingTimerOriginY = floatingTimerOriginY
        self.voicePromptsEnabled = voicePromptsEnabled
        self.voiceInputEnabled = voiceInputEnabled
        self.voiceIdentifier = voiceIdentifier
        self.globalShortcutsEnabled = globalShortcutsEnabled
        self.achievementsToastEnabled = achievementsToastEnabled
        self.profileLearningEnabled = profileLearningEnabled
        self.remoteAgentEnabled = remoteAgentEnabled
        self.localEncryptionEnabled = localEncryptionEnabled
        self.privacyMode = privacyMode
        self.shortcutKeys = shortcutKeys
    }

    public static let defaults = FocusFlowSettings()

    private enum CodingKeys: String, CodingKey {
        case notificationsEnabled
        case floatingTimerOpacity
        case floatingTimerOriginX
        case floatingTimerOriginY
        case voicePromptsEnabled
        case voiceInputEnabled
        case voiceIdentifier
        case globalShortcutsEnabled
        case achievementsToastEnabled
        case profileLearningEnabled
        case remoteAgentEnabled
        case localEncryptionEnabled
        case privacyMode
        case shortcutKeys
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            notificationsEnabled: try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true,
            floatingTimerOpacity: try container.decodeIfPresent(Double.self, forKey: .floatingTimerOpacity) ?? 0.85,
            floatingTimerOriginX: try container.decodeIfPresent(Double.self, forKey: .floatingTimerOriginX),
            floatingTimerOriginY: try container.decodeIfPresent(Double.self, forKey: .floatingTimerOriginY),
            voicePromptsEnabled: try container.decodeIfPresent(Bool.self, forKey: .voicePromptsEnabled) ?? false,
            voiceInputEnabled: try container.decodeIfPresent(Bool.self, forKey: .voiceInputEnabled) ?? false,
            voiceIdentifier: try container.decodeIfPresent(String.self, forKey: .voiceIdentifier),
            globalShortcutsEnabled: try container.decodeIfPresent(Bool.self, forKey: .globalShortcutsEnabled) ?? true,
            achievementsToastEnabled: try container.decodeIfPresent(Bool.self, forKey: .achievementsToastEnabled) ?? true,
            profileLearningEnabled: try container.decodeIfPresent(Bool.self, forKey: .profileLearningEnabled) ?? true,
            remoteAgentEnabled: try container.decodeIfPresent(Bool.self, forKey: .remoteAgentEnabled) ?? true,
            localEncryptionEnabled: try container.decodeIfPresent(Bool.self, forKey: .localEncryptionEnabled) ?? false,
            privacyMode: try container.decodeIfPresent(PrivacyMode.self, forKey: .privacyMode) ?? .remoteLLMAllowedForCurrentContext,
            shortcutKeys: try container.decodeIfPresent(FocusFlowShortcutSettings.self, forKey: .shortcutKeys) ?? .defaults
        )
    }
}

public struct FocusFlowShortcutSettings: Codable, Equatable, Sendable {
    public var pauseResume: String
    public var skip: String
    public var voiceInput: String
    public var markDistraction: String
    public var help: String

    public init(
        pauseResume: String = "P",
        skip: String = "S",
        voiceInput: String = "M",
        markDistraction: String = "D",
        help: String = "H"
    ) {
        self.pauseResume = Self.normalizedKey(pauseResume, fallback: "P")
        self.skip = Self.normalizedKey(skip, fallback: "S")
        self.voiceInput = Self.normalizedKey(voiceInput, fallback: "M")
        self.markDistraction = Self.normalizedKey(markDistraction, fallback: "D")
        self.help = Self.normalizedKey(help, fallback: "H")
    }

    public static let defaults = FocusFlowShortcutSettings()

    public static let supportedKeys = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)

    public static func normalizedKey(_ value: String, fallback: String) -> String {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let first = candidate.first else { return fallback }
        let key = String(first)
        return supportedKeys.contains(key) ? key : fallback
    }

    public func displayText(for key: String) -> String {
        "⌘ ⇧ \(key)"
    }

    public var duplicateKeys: [String] {
        let keys = [pauseResume, skip, voiceInput, markDistraction, help]
        let counts = Dictionary(grouping: keys, by: { $0 }).mapValues(\.count)
        return counts.filter { $0.value > 1 }.map(\.key).sorted()
    }
}

public struct AgentObservation: Codable, Equatable, Sendable {
    public let text: String
    public let confidence: Double
    public let generatedAt: Date

    public init(text: String, confidence: Double, generatedAt: Date = Date()) {
        self.text = text
        self.confidence = confidence
        self.generatedAt = generatedAt
    }
}
