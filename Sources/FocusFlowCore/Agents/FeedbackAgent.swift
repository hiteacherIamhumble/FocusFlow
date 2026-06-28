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
            return StuckHelpResponse(
                comfortText: decoded.comfortText.cleanLongSentence(maxCharacters: 120, fallback: "No pressure. This is a normal place to get stuck."),
                nextSmallStep: decoded.nextSmallStep.cleanLongSentence(maxCharacters: 180, fallback: "Do only the first visible action for two minutes."),
                actions: canonicalStuckHelpActions()
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
            promptText: "The timer ended. What would help right now?",
            options: [
                FeedbackOption(label: "Done now", emoji: "✅", intent: .completed),
                FeedbackOption(label: "+5 min", emoji: "⏱", intent: .needMoreTime),
                FeedbackOption(label: "Stuck", emoji: "🧩", intent: .tooHard),
                FeedbackOption(label: "Break", emoji: "☕️", intent: .needBreak)
            ]
        )
    }

    public func stuckHelp(for request: StuckHelpRequest) -> StuckHelpResponse {
        StuckHelpResponse(
            comfortText: "No pressure. This is a normal place to get stuck.",
            nextSmallStep: hint(for: request, level: 0),
            actions: canonicalStuckHelpActions()
        )
    }

    private func canonicalStuckHelpActions() -> [StuckHelpAction] {
        [
            StuckHelpAction(title: "Get a hint", actionType: .hint),
            StuckHelpAction(title: "See an example", actionType: .example),
            StuckHelpAction(title: "Split smaller", actionType: .splitSmaller),
            StuckHelpAction(title: "Short break", actionType: .shortBreak)
        ]
    }

    /// Layered, type-aware hint. Level 0 is the gentlest nudge; higher levels are more concrete.
    public func hint(for request: StuckHelpRequest, level: Int) -> String {
        let hints = layeredHints(for: request.stageType)
        let index = min(max(0, level), hints.count - 1)
        return hints[index]
    }

    public func hintUsingLLM(for request: StuckHelpRequest, level: Int) async -> String {
        guard let llmClient else { return hint(for: request, level: level) }
        do {
            let content = try await llmClient.complete(
                messages: [
                    LLMMessage(role: "system", content: hintSystemPrompt),
                    LLMMessage(role: "user", content: """
                    Task: \(request.taskTitle)
                    Stage: \(request.stageTitle)
                    Instruction: \(request.instruction)
                    Stage type: \(request.stageType.rawValue)
                    Hint level (0 = gentlest, higher = more concrete): \(level)
                    Give ONE concrete next-action hint for this level. Never solve the whole task.
                    """)
                ],
                privacyMode: .remoteLLMAllowedForCurrentContext,
                responseFormat: .jsonObject
            )
            let decoded = try FocusFlowJSON.decoder.decode(LLMSingleText.self, from: Data(content.utf8))
            return decoded.text.cleanLongSentence(maxCharacters: 180, fallback: hint(for: request, level: level))
        } catch {
            return hint(for: request, level: level)
        }
    }

    public func example(for request: StuckHelpRequest) -> String {
        switch request.stageType {
        case .writing, .presentationMaking:
            return "Copy this and fill the blanks roughly: \"In this part I want to say ___ because ___.\""
        case .reading:
            return "Try this frame: \"The main point seems to be ___. One detail that supports it is ___.\""
        case .problemSolving:
            return "Worked start: write \"Given: ___\" and \"Find: ___\", then attempt only the first line."
        case .reviewing:
            return "Recall card: \"Concept ___ means ___ in one sentence.\" Fill it from memory first."
        case .organizing:
            return "Starter structure: make \"Bucket A: ___\" and \"Bucket B: ___\", then drop one item in each."
        case .startup:
            return "Placeholder line: write \"Goal for the next 2 minutes: ___\" and stop there."
        default:
            return "Write a rough placeholder like \"___ (improve later)\" so the page is no longer blank."
        }
    }

    public func exampleUsingLLM(for request: StuckHelpRequest) async -> String {
        guard let llmClient else { return example(for: request) }
        do {
            let content = try await llmClient.complete(
                messages: [
                    LLMMessage(role: "system", content: exampleSystemPrompt),
                    LLMMessage(role: "user", content: """
                    Task: \(request.taskTitle)
                    Stage: \(request.stageTitle)
                    Instruction: \(request.instruction)
                    Stage type: \(request.stageType.rawValue)
                    Give ONE short copyable example or template with blanks. Do not complete the work.
                    """)
                ],
                privacyMode: .remoteLLMAllowedForCurrentContext,
                responseFormat: .jsonObject
            )
            let decoded = try FocusFlowJSON.decoder.decode(LLMSingleText.self, from: Data(content.utf8))
            return decoded.text.cleanLongSentence(maxCharacters: 200, fallback: example(for: request))
        } catch {
            return example(for: request)
        }
    }

    private func layeredHints(for type: StageType) -> [String] {
        switch type {
        case .reading:
            return [
                "Find just the first sentence that looks important and read only that one.",
                "Underline one phrase you understand and one word you don't.",
                "Write a one-line summary of that single paragraph in your own words."
            ]
        case .writing, .presentationMaking:
            return [
                "Write the first three rough words. They do not need to be a sentence.",
                "Turn those words into one ugly sentence. Ugly is completely allowed.",
                "Add one more sentence that just says what should come next."
            ]
        case .problemSolving:
            return [
                "Write what the question is actually asking, in plain words.",
                "List what you already know and what is missing.",
                "Attempt only the very first step of the method, even if unsure."
            ]
        case .reviewing:
            return [
                "Pick one concept from the page and say it out loud once.",
                "Cover it and try to recall the single key point.",
                "Write that one point in your own words on paper."
            ]
        case .organizing:
            return [
                "Make just one heading or bucket to put things into.",
                "Drop the first item into that bucket. Only one.",
                "Add two more items, with no sorting yet."
            ]
        case .startup:
            return [
                "Open the file or page you need. That is the whole step for now.",
                "Write a title line or today's date, just to touch the page.",
                "List one thing you want to do next, in a few words."
            ]
        default:
            return [
                "Do only the first visible action for one minute.",
                "Name the very next concrete move in a few words.",
                "Do that move now, even if it is rough."
            ]
        }
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
        Include one comfort sentence, one 1-3 minute next small step, and exactly four distinct actions.
        Valid action_type values: hint, splitSmaller, example, shortBreak.
        Return each action_type at most once. Do not repeat hint multiple times.
        Avoid shame, diagnosis, urgency panic, or long text.
        JSON schema:
        {
          "comfort_text":"No pressure. This part can be sticky.",
          "next_small_step":"Read only the last two sentences and underline one phrase.",
          "actions":[
            {"title":"Get a hint","action_type":"hint"},
            {"title":"See an example","action_type":"example"},
            {"title":"Split smaller","action_type":"splitSmaller"},
            {"title":"Short break","action_type":"shortBreak"}
          ]
        }
        """
    }

    private var hintSystemPrompt: String {
        """
        You are FocusFlow's stuck-help hint agent. Output ONLY valid JSON.
        Give exactly ONE concrete, doable next-action hint for a student with ADHD traits.
        Higher hint levels are more concrete, but never finish the assignment for them.
        Keep it under 30 words, warm, specific, and non-shaming.
        JSON schema: {"text":"Underline one phrase you understand and one word you don't."}
        """
    }

    private var exampleSystemPrompt: String {
        """
        You are FocusFlow's stuck-help example agent. Output ONLY valid JSON.
        Give ONE short copyable example or fill-in-the-blank template for the current step.
        Use blanks like ___ so the student adapts it. Never complete the actual work.
        Keep it under 35 words, concrete, and non-shaming.
        JSON schema: {"text":"Template: \\"In this part I want to say ___ because ___.\\""}
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

private struct LLMSingleText: Decodable {
    let text: String
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

    /// Keeps a full sentence intact. Only filters shaming language and caps length
    /// at a word boundary, instead of collapsing to three words like `cleanSentence`.
    func cleanLongSentence(maxCharacters: Int, fallback: String) -> String {
        let banned = ["lazy", "failure", "failed", "you should", "you must"]
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        guard !banned.contains(where: { trimmed.lowercased().contains($0) }) else { return fallback }
        guard trimmed.count > maxCharacters else { return trimmed }
        let prefix = trimmed.prefix(maxCharacters)
        if let lastSpace = prefix.lastIndex(of: " ") {
            return String(prefix[..<lastSpace]) + "…"
        }
        return String(prefix) + "…"
    }
}
