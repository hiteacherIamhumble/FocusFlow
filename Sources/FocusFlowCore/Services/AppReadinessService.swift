import Foundation

public enum AppReadinessState: String, Codable, Sendable {
    case ready
    case needsAttention
    case off
}

public struct AppReadinessItem: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let state: AppReadinessState
    public let isRequired: Bool

    public init(id: String, title: String, detail: String, state: AppReadinessState, isRequired: Bool = false) {
        self.id = id
        self.title = title
        self.detail = detail
        self.state = state
        self.isRequired = isRequired
    }
}

public struct AppReadinessReport: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let items: [AppReadinessItem]

    public init(generatedAt: Date = Date(), items: [AppReadinessItem]) {
        self.generatedAt = generatedAt
        self.items = items
    }

    public static let empty = AppReadinessReport(items: [])

    public var readyCount: Int {
        items.filter { $0.state == .ready }.count
    }

    public var attentionCount: Int {
        items.filter { $0.state == .needsAttention }.count
    }

    public var requiredAttentionCount: Int {
        items.filter { $0.isRequired && $0.state == .needsAttention }.count
    }

    public var isPrototypeReady: Bool {
        requiredAttentionCount == 0
    }

    public var summaryText: String {
        if requiredAttentionCount == 0 && attentionCount == 0 {
            return "All core systems are ready."
        }
        if requiredAttentionCount == 0 {
            return "\(attentionCount) optional item\(attentionCount == 1 ? "" : "s") need attention."
        }
        return "\(requiredAttentionCount) required item\(requiredAttentionCount == 1 ? "" : "s") need attention."
    }
}

public struct AppReadinessInputs: Equatable, Sendable {
    public let settings: FocusFlowSettings
    public let hasDeepSeekAPIKey: Bool
    public let notificationAuthorized: Bool?
    public let dataDirectoryWritable: Bool
    public let hotKeyFailedRegistrationCount: Int
    public let englishVoiceAvailable: Bool
    public let speechRecognitionAvailable: Bool

    public init(
        settings: FocusFlowSettings,
        hasDeepSeekAPIKey: Bool,
        notificationAuthorized: Bool?,
        dataDirectoryWritable: Bool,
        hotKeyFailedRegistrationCount: Int,
        englishVoiceAvailable: Bool,
        speechRecognitionAvailable: Bool
    ) {
        self.settings = settings
        self.hasDeepSeekAPIKey = hasDeepSeekAPIKey
        self.notificationAuthorized = notificationAuthorized
        self.dataDirectoryWritable = dataDirectoryWritable
        self.hotKeyFailedRegistrationCount = hotKeyFailedRegistrationCount
        self.englishVoiceAvailable = englishVoiceAvailable
        self.speechRecognitionAvailable = speechRecognitionAvailable
    }
}

public struct AppReadinessService: Sendable {
    public init() {}

    public func report(for inputs: AppReadinessInputs, generatedAt: Date = Date()) -> AppReadinessReport {
        let settings = inputs.settings
        var items: [AppReadinessItem] = []

        items.append(AppReadinessItem(
            id: "local_data",
            title: "Local data store",
            detail: inputs.dataDirectoryWritable
                ? "Learning history, profile memory, runtime recovery, and exports can be written locally."
                : "FocusFlow cannot write to its local data directory.",
            state: inputs.dataDirectoryWritable ? .ready : .needsAttention,
            isRequired: true
        ))

        items.append(AppReadinessItem(
            id: "deepseek",
            title: "DeepSeek v4 flash",
            detail: deepSeekDetail(settings: settings, hasKey: inputs.hasDeepSeekAPIKey),
            state: deepSeekState(settings: settings, hasKey: inputs.hasDeepSeekAPIKey),
            isRequired: false
        ))

        items.append(AppReadinessItem(
            id: "profile_learning",
            title: "Profile learning",
            detail: settings.profileLearningEnabled
                ? "Local profile learning is on, so the agent can adapt to your study rhythm."
                : "Profile learning is off. History remains local, but personalization is paused.",
            state: settings.profileLearningEnabled ? .ready : .off
        ))

        items.append(AppReadinessItem(
            id: "local_encryption",
            title: "Local encryption",
            detail: "Off. Learning data is stored as plain JSON on this Mac, without Keychain prompts for file storage.",
            state: .off
        ))

        items.append(AppReadinessItem(
            id: "notifications",
            title: "System notifications",
            detail: notificationDetail(settings: settings, authorized: inputs.notificationAuthorized),
            state: notificationState(settings: settings, authorized: inputs.notificationAuthorized)
        ))

        items.append(AppReadinessItem(
            id: "floating_timer",
            title: "Floating timer",
            detail: "Native floating timer fallback is ready at \(Int(settings.floatingTimerOpacity * 100))% opacity.",
            state: .ready,
            isRequired: true
        ))

        items.append(AppReadinessItem(
            id: "shortcuts",
            title: "Global shortcuts",
            detail: shortcutDetail(settings: settings, failedCount: inputs.hotKeyFailedRegistrationCount),
            state: shortcutState(settings: settings, failedCount: inputs.hotKeyFailedRegistrationCount)
        ))

        items.append(AppReadinessItem(
            id: "voice_encouragement",
            title: "Voice encouragement",
            detail: voiceEncouragementDetail(settings: settings, available: inputs.englishVoiceAvailable),
            state: voiceFeatureState(enabled: settings.voicePromptsEnabled, available: inputs.englishVoiceAvailable)
        ))

        items.append(AppReadinessItem(
            id: "voice_input",
            title: "Voice input",
            detail: voiceInputDetail(settings: settings, available: inputs.speechRecognitionAvailable),
            state: voiceFeatureState(enabled: settings.voiceInputEnabled, available: inputs.speechRecognitionAvailable)
        ))

        return AppReadinessReport(generatedAt: generatedAt, items: items)
    }

    private func deepSeekState(settings: FocusFlowSettings, hasKey: Bool) -> AppReadinessState {
        guard settings.remoteAgentEnabled else { return .off }
        return hasKey ? .ready : .needsAttention
    }

    private func deepSeekDetail(settings: FocusFlowSettings, hasKey: Bool) -> String {
        if !settings.remoteAgentEnabled {
            return "Remote agent calls are off. Local deterministic fallback remains available."
        }
        if hasKey {
            return "Remote agent calls can use DeepSeek v4 flash when privacy mode allows it."
        }
        return "Remote agent is on, but no DeepSeek key is available. Local fallback will be used."
    }

    private func notificationState(settings: FocusFlowSettings, authorized: Bool?) -> AppReadinessState {
        guard settings.notificationsEnabled else { return .off }
        if authorized == true { return .ready }
        return .needsAttention
    }

    private func notificationDetail(settings: FocusFlowSettings, authorized: Bool?) -> String {
        if !settings.notificationsEnabled {
            return "System notifications are off. The floating timer can still keep the active step visible."
        }
        if authorized == true {
            return "System reminders are authorized for gentle check-ins."
        }
        if authorized == false {
            return "Notifications are enabled, but macOS has not authorized them. Floating timer fallback is active."
        }
        return "Notification permission has not been checked yet."
    }

    private func shortcutState(settings: FocusFlowSettings, failedCount: Int) -> AppReadinessState {
        guard settings.globalShortcutsEnabled else { return .off }
        return failedCount == 0 ? .ready : .needsAttention
    }

    private func shortcutDetail(settings: FocusFlowSettings, failedCount: Int) -> String {
        if !settings.globalShortcutsEnabled {
            return "Global shortcuts are off."
        }
        if failedCount == 0 {
            return "Global shortcuts are registered for pause, skip, voice, distraction, and help."
        }
        return "\(failedCount) shortcut\(failedCount == 1 ? "" : "s") could not register because macOS reported a conflict."
    }

    private func voiceFeatureState(enabled: Bool, available: Bool) -> AppReadinessState {
        guard enabled else { return .off }
        return available ? .ready : .needsAttention
    }

    private func voiceEncouragementDetail(settings: FocusFlowSettings, available: Bool) -> String {
        if !settings.voicePromptsEnabled {
            return "Voice encouragement is off."
        }
        return available
            ? "English speech synthesis is available for optional encouragement."
            : "Voice encouragement is on, but no English system voice is available."
    }

    private func voiceInputDetail(settings: FocusFlowSettings, available: Bool) -> String {
        if !settings.voiceInputEnabled {
            return "Voice input is off."
        }
        return available
            ? "Speech recognition can be requested when you start voice feedback."
            : "Voice input is on, but speech recognition is unavailable right now."
    }
}
