import Foundation

public struct FeedbackAgent: Sendable {
    private let llmClient: (any LLMClient)?

    public init(llmClient: (any LLMClient)? = nil) {
        self.llmClient = llmClient
    }

    public func optionsUsingLLM(for task: TaskPlan, stage: StagePlan) async -> [FeedbackOption] {
        guard let llmClient else { return options(for: stage) }
        do {
            let content = try await llmClient.complete(
                messages: [
                    LLMMessage(role: "system", content: feedbackSystemPrompt),
                    LLMMessage(role: "user", content: """
                    Task title: \(task.title)
                    Task type: \(task.taskType.rawValue)
                    Stage title: \(stage.title)
                    Stage type: \(stage.stageType.rawValue)
                    Stage instruction: \(stage.instruction)
                    Return 3-4 feedback options.
                    """)
                ],
                privacyMode: .remoteLLMAllowedForCurrentContext,
                responseFormat: .jsonObject
            )
            let decoded = try FocusFlowJSON.decoder.decode(LLMFeedbackOptions.self, from: Data(content.utf8))
            let mapped = decoded.options.prefix(4).compactMap { option -> FeedbackOption? in
                guard let intent = FeedbackIntent(rawValue: option.intent) else { return nil }
                return FeedbackOption(label: option.label.cleanFeedbackLabel, emoji: option.emoji, intent: intent)
            }
            return mapped.isEmpty ? options(for: stage) : Array(mapped)
        } catch {
            return options(for: stage)
        }
    }

    public func stuckHelpUsingLLM(for request: StuckHelpRequest) async -> StuckHelpResponse {
        guard let llmClient else { return stuckHelp(for: request) }
        do {
            let content = try await llmClient.complete(
                messages: [
                    LLMMessage(role: "system", content: stuckHelpSystemPrompt),
                    LLMMessage(role: "user", content: """
                    Task: \(request.taskTitle)
                    Stage: \(request.stageTitle)
                    Instruction: \(request.instruction)
                    Planned seconds: \(request.plannedSeconds)
                    Elapsed seconds: \(request.elapsedSeconds)
                    Trigger: \(request.trigger.rawValue)
                    """)
                ],
                privacyMode: .remoteLLMAllowedForCurrentContext,
                responseFormat: .jsonObject
            )
            let decoded = try FocusFlowJSON.decoder.decode(LLMStuckHelp.self, from: Data(content.utf8))
            let actions = decoded.actions.prefix(4).compactMap { action -> StuckHelpAction? in
                guard let type = StuckActionType(rawValue: action.actionType) else { return nil }
                return StuckHelpAction(title: action.title.cleanActionTitle, actionType: type)
            }
            guard !actions.isEmpty else { return stuckHelp(for: request) }
            return StuckHelpResponse(
                comfortText: decoded.comfortText.cleanSentence(maxCharacters: 80, fallback: "No pressure. This is a normal place to get stuck."),
                nextSmallStep: decoded.nextSmallStep.cleanSentence(maxCharacters: 120, fallback: "Do only the first visible action for two minutes."),
                actions: Array(actions)
            )
        } catch {
            return stuckHelp(for: request)
        }
    }

    public func options(for stage: StagePlan) -> [FeedbackOption] {
        switch stage.stageType {
        case .startup:
            return [
                FeedbackOption(label: "Found it", emoji: "📌", intent: .completed),
                FeedbackOption(label: "Still looking", emoji: "🔍", intent: .tooHard),
                FeedbackOption(label: "Got distracted", emoji: "〰️", intent: .distracted),
                FeedbackOption(label: "Need a break", emoji: "☕️", intent: .needBreak)
            ]
        case .reading:
            return [
                FeedbackOption(label: "Read enough", emoji: "📄", intent: .completed),
                FeedbackOption(label: "Too dense", emoji: "🔍", intent: .tooHard),
                FeedbackOption(label: "Drifted off", emoji: "〰️", intent: .distracted),
                FeedbackOption(label: "Need time", emoji: "⏱", intent: .needMoreTime)
            ]
        case .writing, .presentationMaking:
            return [
                FeedbackOption(label: "Draft exists", emoji: "✍️", intent: .completed),
                FeedbackOption(label: "Stuck early", emoji: "🧩", intent: .tooHard),
                FeedbackOption(label: "Need example", emoji: "💡", intent: .unclearInstruction),
                FeedbackOption(label: "Need time", emoji: "⏱", intent: .needMoreTime)
            ]
        case .problemSolving:
            return [
                FeedbackOption(label: "Tried it", emoji: "✅", intent: .completed),
                FeedbackOption(label: "Too hard", emoji: "🧩", intent: .tooHard),
                FeedbackOption(label: "Need hint", emoji: "💡", intent: .unclearInstruction),
                FeedbackOption(label: "Need break", emoji: "☕️", intent: .needBreak)
            ]
        default:
            return [
                FeedbackOption(label: "Done enough", emoji: "✅", intent: .completed),
                FeedbackOption(label: "Too big", emoji: "🧩", intent: .tooHard),
                FeedbackOption(label: "Unclear", emoji: "💡", intent: .unclearInstruction),
                FeedbackOption(label: "Need break", emoji: "☕️", intent: .needBreak)
            ]
        }
    }

    public func difficultyPrompt(for stage: StagePlan) -> DifficultyPrompt {
        DifficultyPrompt(
            promptText: "Where did this step get sticky?",
            options: [
                FeedbackOption(label: "Done now", emoji: "✅", intent: .completed),
                FeedbackOption(label: "+5 min", emoji: "⏱", intent: .needMoreTime),
                FeedbackOption(label: "Stuck", emoji: "🧩", intent: .tooHard),
                FeedbackOption(label: "Break", emoji: "☕️", intent: .needBreak)
            ]
        )
    }

    public func stuckHelp(for request: StuckHelpRequest) -> StuckHelpResponse {
        let nextSmallStep: String
        if request.instruction.lowercased().contains("read") {
            nextSmallStep = "Read only the last two sentences of this section and underline one useful phrase."
        } else if request.instruction.lowercased().contains("write") {
            nextSmallStep = "Write three rough words first. They do not need to become a sentence yet."
        } else if request.instruction.lowercased().contains("slide") {
            nextSmallStep = "Put one plain sentence on the slide. Design can wait."
        } else {
            nextSmallStep = "Do only the first visible action for two minutes, then stop and check in."
        }

        return StuckHelpResponse(
            comfortText: "No pressure. This is a normal place to get stuck.",
            nextSmallStep: nextSmallStep,
            actions: [
                StuckHelpAction(title: "Hint", actionType: .hint),
                StuckHelpAction(title: "Split", actionType: .splitSmaller),
                StuckHelpAction(title: "Example", actionType: .example),
                StuckHelpAction(title: "3-min break", actionType: .shortBreak)
            ]
        )
    }

    private var feedbackSystemPrompt: String {
        """
        You are FocusFlow's FeedbackAgent. Output ONLY valid JSON.
        Create 3-4 short feedback options for a student with ADHD traits.
        Each label must be English, <= 14 characters if possible, warm, non-shaming.
        Valid intents: completed, tooHard, distracted, needBreak, needMoreTime, unclearInstruction, wantToQuit, other.
        JSON schema:
        {"options":[{"label":"Done enough","emoji":"✅","intent":"completed"}]}
        """
    }

    private var stuckHelpSystemPrompt: String {
        """
        You are FocusFlow's stuck-help agent. Output ONLY valid JSON.
        Help the user return to action without doing the assignment for them.
        Include one comfort sentence, one 1-3 minute next small step, and four actions.
        Valid action_type values: hint, splitSmaller, example, shortBreak.
        Avoid shame, diagnosis, urgency panic, or long text.
        JSON schema:
        {
          "comfort_text":"No pressure. This part can be sticky.",
          "next_small_step":"Read only the last two sentences and underline one phrase.",
          "actions":[{"title":"Hint","action_type":"hint"}]
        }
        """
    }
}

private struct LLMFeedbackOptions: Decodable {
    let options: [LLMFeedbackOption]
}

private struct LLMFeedbackOption: Decodable {
    let label: String
    let emoji: String?
    let intent: String
}

private struct LLMStuckHelp: Decodable {
    let comfortText: String
    let nextSmallStep: String
    let actions: [LLMStuckAction]
}

private struct LLMStuckAction: Decodable {
    let title: String
    let actionType: String
}

private extension String {
    var cleanFeedbackLabel: String {
        cleanSentence(maxCharacters: 18, fallback: "Done enough")
    }

    var cleanActionTitle: String {
        cleanSentence(maxCharacters: 14, fallback: "Hint")
    }

    func cleanSentence(maxCharacters: Int, fallback: String) -> String {
        let banned = ["lazy", "failure", "failed", "you should", "you must"]
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        guard !banned.contains(where: { trimmed.lowercased().contains($0) }) else { return fallback }
        let words = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let shortened = words.count > 3 ? words.prefix(3).joined(separator: " ") : trimmed
        if shortened.count <= maxCharacters { return shortened }
        return fallback
    }
}
