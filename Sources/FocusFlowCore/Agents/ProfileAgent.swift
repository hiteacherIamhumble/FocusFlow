import Foundation

public struct ProfileAgent: Sendable {
    private let llmClient: (any LLMClient)?

    public init(llmClient: (any LLMClient)? = nil) {
        self.llmClient = llmClient
    }

    public func observation(profile: UserProfileSnapshot, stats: StatsSummary) async -> AgentObservation {
        guard let llmClient else {
            return fallbackObservation(profile: profile, stats: stats)
        }
        do {
            let content = try await llmClient.complete(
                messages: [
                    LLMMessage(role: "system", content: profileSystemPrompt),
                    LLMMessage(role: "user", content: """
                    Active days: \(stats.activeDays)
                    Completed stages: \(stats.completedStageCount)
                    Total focus seconds: \(stats.totalFocusSeconds)
                    Recovery count: \(stats.recoveryCount)
                    Preferred stage seconds: \(profile.preferredStageDurationSeconds.map(String.init) ?? "unknown")
                    Difficult stage types: \(profile.difficultStageTypes.map(\.rawValue).joined(separator: ", "))
                    Profile confidence: \(profile.confidence)
                    """)
                ],
                privacyMode: .remoteLLMAllowedForCurrentContext,
                responseFormat: .jsonObject
            )
            let decoded = try FocusFlowJSON.decoder.decode(LLMProfileObservation.self, from: Data(content.utf8))
            return AgentObservation(
                text: decoded.text.safeProfileText ?? fallbackObservation(profile: profile, stats: stats).text,
                confidence: min(1, max(0, decoded.confidence))
            )
        } catch {
            return fallbackObservation(profile: profile, stats: stats)
        }
    }

    private func fallbackObservation(profile: UserProfileSnapshot, stats: StatsSummary) -> AgentObservation {
        if stats.completedStageCount == 0 {
            return AgentObservation(
                text: "I am still learning your study rhythm. We will keep using small, clear starts for now.",
                confidence: 0.2
            )
        }
        if let preferred = profile.preferredStageDurationSeconds {
            return AgentObservation(
                text: "Your recent completed steps suggest \(preferred.minutesText) blocks may be a comfortable starting size.",
                confidence: max(0.3, profile.confidence)
            )
        }
        return AgentObservation(
            text: "You completed \(stats.completedStageCount) recent step\(stats.completedStageCount == 1 ? "" : "s"). Short, visible actions are worth keeping.",
            confidence: max(0.25, profile.confidence)
        )
    }

    private var profileSystemPrompt: String {
        """
        You are FocusFlow's ProfileAgent. Output ONLY valid JSON.
        Write one concise English observation about the user's learning rhythm.
        Do not diagnose, shame, compare, or overclaim. Say uncertainty when data is sparse.
        Mention only behavior patterns, not medical conclusions.
        JSON schema: {"text":"string <= 150 chars","confidence":0.0}
        """
    }
}

private struct LLMProfileObservation: Decodable {
    let text: String
    let confidence: Double
}

private extension String {
    var safeProfileText: String? {
        let banned = ["lazy", "failure", "failed", "diagnosis", "severity", "you should", "you must"]
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !banned.contains(where: { trimmed.lowercased().contains($0) }) else { return nil }
        if trimmed.count <= 160 { return trimmed }
        return String(trimmed.prefix(160)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
