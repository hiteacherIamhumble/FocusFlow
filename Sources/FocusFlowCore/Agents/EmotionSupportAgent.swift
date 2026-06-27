import Foundation

public struct EmotionSupportAgent: Sendable {
    private let llmClient: (any LLMClient)?

    public init(llmClient: (any LLMClient)? = nil) {
        self.llmClient = llmClient
    }

    public func closureCopy(for task: TaskPlan, focusSeconds: Int, closureType: TaskClosureType, reason: String?) async -> EmotionClosureCopy {
        guard let llmClient else {
            return fallbackClosureCopy(for: task, focusSeconds: focusSeconds, closureType: closureType, reason: reason)
        }
        do {
            let content = try await llmClient.complete(
                messages: [
                    LLMMessage(role: "system", content: emotionSystemPrompt),
                    LLMMessage(role: "user", content: """
                    Task: \(task.title)
                    Task type: \(task.taskType.rawValue)
                    Closure type: \(closureType.rawValue)
                    Completed stages: \(task.stages.filter { $0.status == .completed }.map(\.title).joined(separator: ", "))
                    Focus seconds: \(focusSeconds)
                    Pause reason: \(reason ?? "")
                    """)
                ],
                privacyMode: .remoteLLMAllowedForCurrentContext,
                responseFormat: .jsonObject
            )
            let decoded = try FocusFlowJSON.decoder.decode(LLMEmotionClosureCopy.self, from: Data(content.utf8))
            return EmotionClosureCopy(
                encouragementText: decoded.encouragementText?.safeAgentText(maxCharacters: 90),
                soothingText: decoded.soothingText?.safeAgentText(maxCharacters: 110),
                reviewItems: decoded.reviewItems.prefix(3).map {
                    ReviewItem(
                        text: $0.text.safeAgentText(maxCharacters: 140) ?? "You made the next step clearer.",
                        type: ReviewItemType(rawValue: $0.type) ?? .highlight
                    )
                }
            )
        } catch {
            return fallbackClosureCopy(for: task, focusSeconds: focusSeconds, closureType: closureType, reason: reason)
        }
    }

    public func completionText(for task: TaskPlan, focusSeconds: Int) -> String {
        let minutes = max(1, focusSeconds / 60)
        switch task.taskType {
        case .presentation:
            return "Your presentation has a real starting shape now. \(minutes) focused minutes counted."
        case .writing:
            return "The blank-page part is smaller now. You moved the writing forward."
        case .reading:
            return "You made the reading more familiar. That is real progress."
        default:
            return "You moved this task forward, one clear step at a time."
        }
    }

    public func soothingText(reason: String?) -> String {
        if let reason, !reason.isEmpty {
            return "We can stop here and keep the progress. \(reason)"
        }
        return "Stopping here is allowed. Your progress is saved, and coming back later still counts."
    }

    public func reviewItems(for task: TaskPlan) -> [ReviewItem] {
        [
            ReviewItem(text: "You turned the task into visible steps.", type: .highlight),
            ReviewItem(text: "Next time, start from the smallest saved stage.", type: .suggestion)
        ]
    }

    private func fallbackClosureCopy(for task: TaskPlan, focusSeconds: Int, closureType: TaskClosureType, reason: String?) -> EmotionClosureCopy {
        EmotionClosureCopy(
            encouragementText: closureType == .completed ? completionText(for: task, focusSeconds: focusSeconds) : nil,
            soothingText: closureType == .gracefullyPaused ? soothingText(reason: reason) : nil,
            reviewItems: reviewItems(for: task)
        )
    }

    private var emotionSystemPrompt: String {
        """
        You are FocusFlow's EmotionSupportAgent. Output ONLY valid JSON.
        Write English copy for an ADHD-friendly educational agent.
        Do not diagnose, shame, compare, punish, or use words like lazy, failure, failed, should, must.
        Encouragement <= 90 characters. Soothing <= 110 characters.
        Review items should be lightweight and skippable.
        JSON schema:
        {
          "encouragement_text": "string or null",
          "soothing_text": "string or null",
          "review_items": [{"text":"string","type":"highlight|suggestion|userNote"}]
        }
        """
    }
}

public struct EmotionClosureCopy: Equatable, Sendable {
    public let encouragementText: String?
    public let soothingText: String?
    public let reviewItems: [ReviewItem]

    public init(encouragementText: String?, soothingText: String?, reviewItems: [ReviewItem]) {
        self.encouragementText = encouragementText
        self.soothingText = soothingText
        self.reviewItems = reviewItems
    }
}

private struct LLMEmotionClosureCopy: Decodable {
    let encouragementText: String?
    let soothingText: String?
    let reviewItems: [LLMReviewItem]
}

private struct LLMReviewItem: Decodable {
    let text: String
    let type: String
}

private extension String {
    func safeAgentText(maxCharacters: Int) -> String? {
        let banned = ["lazy", "failure", "failed", "you should", "you must", "diagnosis", "adhd severity"]
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !banned.contains(where: { trimmed.lowercased().contains($0) }) else { return nil }
        if trimmed.count <= maxCharacters { return trimmed }
        return String(trimmed.prefix(maxCharacters)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
