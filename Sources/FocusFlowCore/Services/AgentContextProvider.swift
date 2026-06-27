import Foundation

public struct LocalAgentContextProvider: AgentContextProviderProtocol {
    private let dataCenter: any DataCenterServiceProtocol

    public init(dataCenter: any DataCenterServiceProtocol) {
        self.dataCenter = dataCenter
    }

    public func getContext(for taskId: String?, stageId: String?) async throws -> AgentContext {
        let history = try await dataCenter.queryHistory(HistoryQuery(dateRange: .last30Days))
        let notes = history
            .filter { taskId == nil || $0.taskId != taskId }
            .prefix(5)
            .map(Self.makeHistoryNote)
        return AgentContext(
            userProfileSnapshot: try await dataCenter.getUserProfileSnapshot(),
            recentStatsSummary: try await dataCenter.getStats(range: .last7Days),
            recentSimilarTaskNotes: Array(notes),
            privacyMode: .localOnly
        )
    }

    private static func makeHistoryNote(from card: HistoryTaskCard) -> String {
        let type = card.taskType?.rawValue ?? "learning"
        let minutes = max(0, card.totalFocusSeconds / 60)
        let status = card.status ?? "recorded"
        return "\(type): \(card.completedStageCount) completed step\(card.completedStageCount == 1 ? "" : "s"), \(minutes) focus minute\(minutes == 1 ? "" : "s"), latest status \(status)."
    }
}
