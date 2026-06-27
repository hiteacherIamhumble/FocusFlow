import Foundation

public actor AppEventBus {
    private let dataCenter: any DataCenterServiceProtocol
    private var recentEvents: [LearningEvent] = []
    private let maxRecentEvents = 100

    public init(dataCenter: any DataCenterServiceProtocol) {
        self.dataCenter = dataCenter
    }

    public func publish(_ event: LearningEvent) async {
        recentEvents.append(event)
        if recentEvents.count > maxRecentEvents {
            recentEvents.removeFirst(recentEvents.count - maxRecentEvents)
        }
        try? await dataCenter.recordEvent(event)
    }

    public func latestEvents() -> [LearningEvent] {
        recentEvents
    }
}
