import Foundation

public struct HistoryQueryAgent: Sendable {
    private let llmClient: (any LLMClient)?

    public init(llmClient: (any LLMClient)? = nil) {
        self.llmClient = llmClient
    }

    public func parseUsingLLM(_ text: String) async throws -> HistoryQuery {
        guard let llmClient else {
            throw FocusFlowError.invalidState("No remote history query agent is configured.")
        }
        let content = try await llmClient.complete(
            messages: [
                LLMMessage(role: "system", content: systemPrompt),
                LLMMessage(role: "user", content: text)
            ],
            privacyMode: .remoteLLMAllowedForCurrentContext,
            responseFormat: .jsonObject
        )
        let decoded = try FocusFlowJSON.decoder.decode(LLMHistoryQuery.self, from: Data(content.utf8))
        return HistoryQuery(
            dateRange: decoded.dateRange.flatMap(StatsRange.init(rawValue:)),
            keyword: decoded.keyword?.cleanKeyword,
            taskTypes: decoded.taskTypes?.compactMap(EducationTaskType.init(rawValue:)) ?? [],
            stageTypes: decoded.stageTypes?.compactMap(StageType.init(rawValue:)) ?? [],
            statuses: decoded.statuses?.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? []
        )
    }

    private var systemPrompt: String {
        """
        You are FocusFlow's HistoryQueryAgent. Convert the user's search request into JSON only.
        Do not infer private history. Use only the request text.
        Valid date_range: today, last7Days, last30Days, thisMonth, allTime.
        Valid task_types: writing, reading, examReview, homework, presentation, longTermProject, unknown.
        Valid stage_types: startup, reading, writing, reviewing, problemSolving, organizing, presentationMaking, breakTime, other.
        Statuses may include completed, paused, gracefullyPaused, skipped, abandoned, archived.
        JSON schema:
        {"date_range":"last7Days","keyword":"paper","task_types":["reading"],"stage_types":[],"statuses":["completed"]}
        """
    }
}

private struct LLMHistoryQuery: Decodable {
    let dateRange: String?
    let keyword: String?
    let taskTypes: [String]?
    let stageTypes: [String]?
    let statuses: [String]?
}

private extension String {
    var cleanKeyword: String? {
        let banned = ["lazy", "failure", "failed", "diagnosis"]
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !banned.contains(where: { trimmed.lowercased().contains($0) }) else { return nil }
        return String(trimmed.prefix(80))
    }
}
