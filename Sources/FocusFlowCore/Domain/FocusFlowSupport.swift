import Foundation

public enum FocusFlowID {
    public static func make(_ prefix: String) -> String {
        "\(prefix)_\(UUID().uuidString.lowercased())"
    }
}

public enum FocusFlowCalendar {
    public static func localDay(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    public static func monthKey(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }
}

public enum FocusFlowJSON {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    public static let lineEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}

public enum FocusFlowError: Error, LocalizedError, Equatable, Sendable {
    case nonEducationalTask
    case taskNotFound(String)
    case stageNotFound(String)
    case noActiveRuntime
    case invalidState(String)
    case storageFailure(String)

    public var errorDescription: String? {
        switch self {
        case .nonEducationalTask:
            return "FocusFlow is built for learning tasks. Try a course, assignment, exam, reading, or presentation."
        case .taskNotFound(let id):
            return "Task not found: \(id)"
        case .stageNotFound(let id):
            return "Stage not found: \(id)"
        case .noActiveRuntime:
            return "No stage is currently active."
        case .invalidState(let message):
            return message
        case .storageFailure(let message):
            return message
        }
    }
}

public extension Int {
    var minutesText: String {
        let minutes = Swift.max(1, Int((Double(self) / 60.0).rounded()))
        return minutes == 1 ? "1 min" : "\(minutes) min"
    }
}

public enum VoiceCommandIntent: String, Equatable, Sendable {
    case complete
    case pauseOrResume
    case skip
    case help
    case shortBreak
    case moreTime
    case tooHard
    case distracted
    case stopTask
    case continueNext
}

public enum VoiceCommandParser {
    public static func parse(_ transcript: String) -> VoiceCommandIntent? {
        let lower = transcript
            .lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
        guard !lower.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        if containsAny(lower, ["stop task", "end task", "quit task", "give up", "i want to stop", "i want to quit", "done for today", "不想做", "结束任务"]) {
            return .stopTask
        }
        if containsAny(lower, ["im stuck", "i am stuck", "stuck", "help me", "need help", "hint", "卡住", "帮助"]) {
            return .help
        }
        if containsAny(lower, ["take a break", "need a break", "short break", "three minute break", "3 minute break", "rest", "休息"]) {
            return .shortBreak
        }
        if containsAny(lower, ["too hard", "too big", "too difficult", "hard", "太难", "太大"]) {
            return .tooHard
        }
        if containsAny(lower, ["more time", "need time", "five more", "another five", "再给", "更多时间"]) {
            return .moreTime
        }
        if containsAny(lower, ["distracted", "drifted", "lost focus", "分心"]) {
            return .distracted
        }
        if containsAny(lower, ["skip", "skip this", "next one", "跳过"]) {
            return .skip
        }
        if containsAny(lower, ["continue", "go on", "next step", "start next", "继续", "下一步"]) {
            return .continueNext
        }
        if containsAny(lower, ["pause", "resume", "hold on", "暂停", "恢复"]) {
            return .pauseOrResume
        }
        if containsAny(lower, ["done", "finished", "complete", "completed", "i did it", "i finished", "完成", "做完"]) {
            return .complete
        }
        return nil
    }

    private static func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains { value.contains($0) }
    }
}

public enum NotificationFallbackPolicy {
    public static func floatingTimerMessage(stageTitle: String?) -> String {
        let target = stageTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let visibleTarget = target?.isEmpty == false ? target! : "the current stage"
        return "System notifications are unavailable. The floating timer will keep \(visibleTarget) visible."
    }
}
