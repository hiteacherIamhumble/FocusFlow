import Foundation

public actor LocalDataCenterService: DataCenterServiceProtocol {
    private let directory: LocalDataDirectory
    private let simulateEventWriteFailure: Bool
    private let encryptionService: LocalEncryptionService
    private var knownEventIds: Set<String> = []
    private var cachedEvents: [LearningEvent]?
    private var profileLearningEnabled = true
    private var localEncryptionEnabled = false

    public init(
        directory: LocalDataDirectory,
        simulateEventWriteFailure: Bool = false,
        encryptionService: LocalEncryptionService = LocalEncryptionService()
    ) {
        self.directory = directory
        self.simulateEventWriteFailure = simulateEventWriteFailure
        self.encryptionService = encryptionService
    }

    public func recordEvent(_ event: LearningEvent) async throws {
        try directory.prepare()
        if !simulateEventWriteFailure {
            _ = try await replayRetryQueue()
        }
        if knownEventIds.isEmpty {
            knownEventIds = try await loadAllEvents().reduce(into: Set<String>()) { $0.insert($1.id) }
        }
        guard !knownEventIds.contains(event.id) else { return }

        do {
            try await appendEvent(event)
        } catch {
            try await enqueueRetryEvent(event)
            return
        }
        if event.eventType != .achievementUnlocked && event.eventType != .profileCorrectionSubmitted && event.eventType != .eventWriteRetried {
            if profileLearningEnabled {
                try await updateProfileFromRecentEvents()
            }
            let unlocked = try await evaluateAchievements()
            if !unlocked.isEmpty {
                try await savePendingAchievements(unlocked)
                for achievement in unlocked {
                    try await appendEvent(LearningEvent(
                        eventType: .achievementUnlocked,
                        sourceModule: .module5DataCenter,
                        relatedObjectId: achievement.id,
                        tags: ["achievement"],
                        metadata: ["title": achievement.title]
                    ))
                }
            }
        }
    }

    public func replayRetryQueue() async throws -> RetryReplaySummary {
        try directory.prepare()
        let queueFiles = try FileManager.default.contentsOfDirectory(at: directory.retryQueue, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }
        guard !queueFiles.isEmpty else {
            return RetryReplaySummary(replayedCount: 0, skippedDuplicateCount: 0, failedCount: 0, queueFileCount: 0)
        }
        if knownEventIds.isEmpty {
            knownEventIds = try await loadAllEvents().reduce(into: Set<String>()) { $0.insert($1.id) }
        }

        var replayed = 0
        var skipped = 0
        var failed = 0
        var retained: [LearningEvent] = []

        for file in queueFiles {
            for event in try await loadRetryEvents(from: file) {
                if knownEventIds.contains(event.id) {
                    skipped += 1
                    continue
                }
                do {
                    try await appendEvent(event)
                    replayed += 1
                } catch {
                    failed += 1
                    retained.append(event)
                }
            }
        }

        for file in queueFiles {
            try? FileManager.default.removeItem(at: file)
        }
        for event in retained {
            try await enqueueRetryEvent(event)
        }
        if replayed > 0 || skipped > 0 {
            try await appendEvent(LearningEvent(
                eventType: .eventWriteRetried,
                sourceModule: .module5DataCenter,
                status: failed == 0 ? "replayed" : "partially_replayed",
                tags: ["retry_queue"],
                metadata: [
                    "replayed_count": "\(replayed)",
                    "skipped_duplicate_count": "\(skipped)",
                    "failed_count": "\(failed)",
                    "queue_file_count": "\(queueFiles.count)"
                ]
            ))
        }
        return RetryReplaySummary(
            replayedCount: replayed,
            skippedDuplicateCount: skipped,
            failedCount: failed,
            queueFileCount: queueFiles.count
        )
    }

    public func setProfileLearningEnabled(_ enabled: Bool) async {
        profileLearningEnabled = enabled
    }

    public func setLocalEncryptionEnabled(_ enabled: Bool) async {
        localEncryptionEnabled = enabled
        cachedEvents = nil
    }

    private func appendEvent(_ event: LearningEvent) async throws {
        if simulateEventWriteFailure {
            throw FocusFlowError.storageFailure("Simulated event write failure for retry queue coverage.")
        }
        let fileURL = directory.events.appendingPathComponent("\(FocusFlowCalendar.monthKey(for: event.timestamp)).jsonl")
        var existing = ""
        if FileManager.default.fileExists(atPath: fileURL.path) {
            existing = try await readPlainTextFile(fileURL)
        }
        let data = try FocusFlowJSON.lineEncoder.encode(event)
        guard var line = String(data: data, encoding: .utf8) else {
            throw FocusFlowError.storageFailure("Could not encode event \(event.id)")
        }
        line.append("\n")
        try await writePlainText(existing + line, to: fileURL)
        knownEventIds.insert(event.id)
        if cachedEvents != nil {
            cachedEvents?.append(event)
        }
    }

    private func enqueueRetryEvent(_ event: LearningEvent) async throws {
        try FileManager.default.createDirectory(at: directory.retryQueue, withIntermediateDirectories: true)
        let fileURL = directory.retryQueue.appendingPathComponent("\(FocusFlowCalendar.monthKey(for: event.timestamp)).jsonl")
        var existing = ""
        if FileManager.default.fileExists(atPath: fileURL.path) {
            existing = try await readPlainTextFile(fileURL)
        }
        let data = try FocusFlowJSON.lineEncoder.encode(event)
        guard var line = String(data: data, encoding: .utf8) else {
            throw FocusFlowError.storageFailure("Could not encode retry event \(event.id)")
        }
        line.append("\n")
        try await writePlainText(existing + line, to: fileURL)
    }

    private func loadRetryEvents(from url: URL) async throws -> [LearningEvent] {
        let content = try await readPlainTextFile(url)
        return content.split(separator: "\n").compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? FocusFlowJSON.decoder.decode(LearningEvent.self, from: data)
        }
    }

    public func getStats(range: StatsRange) async throws -> StatsSummary {
        let events = try await filteredEvents(for: range)
        let activeDaySet = Set(events.compactMap { event -> String? in
            if event.eventType == .stageCompleted || (event.actualFocusSeconds ?? 0) >= 300 || event.eventType == .taskCompleted || event.eventType == .manualCheckIn {
                return event.localDay
            }
            return nil
        })
        let completedStages = events.filter { $0.eventType == .stageCompleted }
        let skippedStages = events.filter { $0.eventType == .stageSkipped }
        let abandonedStages = events.filter { $0.eventType == .stageAbandoned }
        let completedTasks = events.filter { $0.eventType == .taskCompleted }
        let abandonedTasks = events.filter { $0.eventType == .taskAbandoned }
        let stageDenominator = completedStages.count + skippedStages.count + abandonedStages.count
        let taskDenominator = completedTasks.count + abandonedTasks.count
        let totalFocus = events.reduce(0) { $0 + ($1.actualFocusSeconds ?? 0) }
        let recoveries = events.filter { $0.eventType == .stageResumed }.count
        let strictStreak = strictStreakDays(from: activeDaySet)

        return StatsSummary(
            range: range,
            activeDays: activeDaySet.count,
            strictStreakDays: strictStreak,
            gentleRhythmText: rhythmText(activeDays: activeDaySet.count, range: range),
            totalFocusSeconds: totalFocus,
            completedStageCount: completedStages.count,
            stageCompletionRate: stageDenominator == 0 ? nil : Double(completedStages.count) / Double(stageDenominator),
            taskCompletionRate: taskDenominator < 3 ? nil : Double(completedTasks.count) / Double(taskDenominator),
            recoveryCount: recoveries
        )
    }

    public func getDailyStats(range: StatsRange) async throws -> [DailyStatsPoint] {
        let days = dayKeys(for: range)
        let daySet = Set(days)
        let events = try await loadAllEvents().filter { daySet.contains($0.localDay) }
        let grouped = Dictionary(grouping: events, by: \.localDay)
        return days.map { day in
            let dayEvents = grouped[day] ?? []
            return DailyStatsPoint(
                localDay: day,
                focusSeconds: dayEvents.reduce(0) { $0 + ($1.actualFocusSeconds ?? 0) },
                completedStageCount: dayEvents.filter { $0.eventType == .stageCompleted }.count,
                recoveryCount: dayEvents.filter { $0.eventType == .stageResumed }.count
            )
        }
    }

    public func getUserProfileSnapshot() async throws -> UserProfileSnapshot {
        let profileURL = directory.profile.appendingPathComponent("user_profile.json")
        return try await decodeLocalFile(UserProfileSnapshot.self, from: profileURL) ?? .empty
    }

    public func updateProfileFromRecentEvents() async throws {
        guard profileLearningEnabled else { return }
        try directory.prepare()
        let events = try await filteredEvents(for: .last30Days)
        let stageCompleted = events.filter { $0.eventType == .stageCompleted }
        let averageDuration = stageCompleted
            .compactMap(\.actualFocusSeconds)
            .filter { $0 > 0 && $0 <= 10_800 }
            .averageInt()
        let difficultTypes = repeatedStageTypes(
            from: events.filter {
                $0.eventType == .stageFeedbackSubmitted
                    && isDifficultFeedbackIntent($0.metadata["intent"])
            }
        )
        let easierTypes = repeatedStageTypes(from: stageCompleted)
        let confidence = min(0.85, Double(stageCompleted.count) / 20.0)
        let snapshot = UserProfileSnapshot(
            preferredStageDurationSeconds: averageDuration,
            recommendedFirstStageSeconds: 180,
            difficultStageTypes: difficultTypes,
            easierStageTypes: easierTypes,
            effectiveInterventions: [.splitSmaller, .addShortBreak],
            encouragementStyle: .gentleDirect,
            rewardPreference: .quietBadge,
            streakSensitivity: .medium,
            confidence: confidence,
            lastUpdatedAt: Date()
        )
        let data = try FocusFlowJSON.encoder.encode(snapshot)
        try await writePlainData(data, to: directory.profile.appendingPathComponent("user_profile.json"))
        try await appendProfileSnapshot(snapshot)
    }

    public func checkAchievements(after event: LearningEvent) async throws -> [Achievement] {
        try await recordEvent(event)
        return try await getPendingAchievements()
    }

    private func evaluateAchievements() async throws -> [Achievement] {
        let existing = try await loadAchievements()
        let allEvents = try await loadAllEvents()
        let stats = statsFromEvents(allEvents, range: .allTime)
        var unlocked: [Achievement] = []

        if allEvents.contains(where: { $0.eventType == .taskCreated }) {
            appendAchievement("tiny_start", existing: existing, into: &unlocked)
        }
        if stats.completedStageCount >= 1 {
            appendAchievement("first_stage", existing: existing, into: &unlocked)
        }
        if stats.recoveryCount >= 3 {
            appendAchievement("gentle_return", existing: existing, into: &unlocked)
        }
        if stats.completedStageCount >= 10 {
            appendAchievement("ten_small_steps", existing: existing, into: &unlocked)
        }
        if stats.totalFocusSeconds >= 3_600 {
            appendAchievement("sixty_minutes", existing: existing, into: &unlocked)
        }
        if allEvents.contains(where: { $0.eventType == .taskCompleted }) {
            appendAchievement("first_loop_closed", existing: existing, into: &unlocked)
        }
        let distractionMarks = allEvents.filter {
            $0.eventType == .stageFeedbackSubmitted
                && ($0.metadata["intent"] == FeedbackIntent.distracted.rawValue || $0.tags.contains("distraction"))
        }.count
        if distractionMarks >= 3 {
            appendAchievement("noticed_distraction", existing: existing, into: &unlocked)
        }

        if !unlocked.isEmpty {
            var merged = existing
            for achievement in unlocked {
                merged[achievement.id] = achievement
            }
            try await saveAchievements(merged)
        }
        return unlocked
    }

    private func appendAchievement(_ id: String, existing: [String: Achievement], into unlocked: inout [Achievement]) {
        guard existing[id] == nil, let achievement = AchievementCatalog.achievement(id: id) else { return }
        unlocked.append(achievement)
    }

    public func getUnlockedAchievements() async throws -> [Achievement] {
        try await loadAchievements().values.sorted { $0.unlockedAt < $1.unlockedAt }
    }

    public func getPendingAchievements() async throws -> [Achievement] {
        try await loadPendingAchievements().values.sorted { $0.unlockedAt < $1.unlockedAt }
    }

    public func markAchievementDisplayed(_ achievementId: String) async throws {
        var pending = try await loadPendingAchievements()
        pending.removeValue(forKey: achievementId)
        try await savePendingAchievementMap(pending)
    }

    public func queryHistory(_ query: HistoryQuery) async throws -> [HistoryTaskCard] {
        let events = try await filteredEvents(for: query.dateRange ?? .allTime)
            .filter { event in
                if let keyword = query.keyword?.lowercased(), !keyword.isEmpty {
                    let haystack = [event.taskTitle, event.stageTitle, event.status].compactMap { $0?.lowercased() }.joined(separator: " ")
                    guard haystack.contains(keyword) else { return false }
                }
                if !query.taskTypes.isEmpty, let type = event.taskType, !query.taskTypes.contains(type) {
                    return false
                }
                if !query.stageTypes.isEmpty, let type = event.stageType, !query.stageTypes.contains(type) {
                    return false
                }
                if !query.statuses.isEmpty, let status = event.status, !query.statuses.contains(status) {
                    return false
                }
                return event.taskId != nil
            }

        let grouped = Dictionary(grouping: events, by: { "\($0.localDay)|\($0.taskId ?? "unknown")" })
        return grouped.values.map { taskEvents in
            let sorted = taskEvents.sorted { $0.timestamp < $1.timestamp }
            let last = sorted.last
            let taskId = last?.taskId ?? FocusFlowID.make("missing")
            return HistoryTaskCard(
                taskId: taskId,
                title: last?.taskTitle ?? "Learning task",
                taskType: last?.taskType,
                localDay: last?.localDay ?? FocusFlowCalendar.localDay(),
                status: last?.status,
                completedStageCount: taskEvents.filter { $0.eventType == .stageCompleted }.count,
                totalFocusSeconds: taskEvents.reduce(0) { $0 + ($1.actualFocusSeconds ?? 0) }
            )
        }
        .sorted { $0.localDay > $1.localDay }
    }

    public func parseHistoryQuery(_ text: String) async throws -> HistoryQuery {
        let lower = text.lowercased()
        let range: StatsRange?
        if lower.contains("today") || lower.contains("今天") {
            range = .today
        } else if lower.contains("this month") || lower.contains("current month") || lower.contains("本月") {
            range = .thisMonth
        } else if lower.contains("30") || lower.contains("month") {
            range = .last30Days
        } else if lower.contains("week") || lower.contains("7") || lower.contains("上周") || lower.contains("最近") {
            range = .last7Days
        } else if lower.contains("all") || lower.contains("全部") {
            range = .allTime
        } else {
            range = .last7Days
        }

        var taskTypes: [EducationTaskType] = []
        let asksReading = lower.contains("read") || lower.contains("pdf") || lower.contains("论文") || lower.contains("阅读")
        if lower.contains("write") || lower.contains("essay") || (!asksReading && lower.contains("paper")) || lower.contains("写") {
            taskTypes.append(.writing)
        }
        if asksReading {
            taskTypes.append(.reading)
        }
        if lower.contains("exam") || lower.contains("review") || lower.contains("复习") || lower.contains("考试") {
            taskTypes.append(.examReview)
        }
        if lower.contains("homework") || lower.contains("assignment") || lower.contains("作业") {
            taskTypes.append(.homework)
        }
        if lower.contains("presentation") || lower.contains("slide") || lower.contains("ppt") || lower.contains("展示") {
            taskTypes.append(.presentation)
        }
        if lower.contains("project") || lower.contains("thesis") || lower.contains("项目") || lower.contains("毕业") {
            taskTypes.append(.longTermProject)
        }

        var statuses: [String] = []
        if lower.contains("complete") || lower.contains("done") || lower.contains("完成") {
            statuses.append("completed")
        }
        if lower.contains("pause") || lower.contains("paused") || lower.contains("暂停") {
            statuses.append("paused")
            statuses.append("gracefullyPaused")
        }
        if lower.contains("skip") || lower.contains("跳过") {
            statuses.append("skipped")
        }

        let stopWords: Set<String> = [
            "find", "show", "history", "records", "record", "tasks", "task", "last", "week", "today",
            "month", "all", "completed", "complete", "done", "reading", "writing", "presentation",
            "homework", "assignment", "exam", "review", "recent", "days", "day"
        ]
        let keyword = lower
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !stopWords.contains($0) && $0.count > 2 }
            .joined(separator: " ")

        return HistoryQuery(
            dateRange: range,
            keyword: keyword.isEmpty ? nil : keyword,
            taskTypes: Array(Set(taskTypes)),
            statuses: statuses
        )
    }

    public func getHistoryDetail(taskId: String) async throws -> HistoryTaskDetail {
        let events = try await loadAllEvents()
            .filter { $0.taskId == taskId }
            .sorted { $0.timestamp < $1.timestamp }
        guard let first = events.first, let last = events.last else {
            throw FocusFlowError.taskNotFound(taskId)
        }
        let stageEvents = events.filter { $0.stageId != nil }
        let groupedStages = Dictionary(grouping: stageEvents, by: { $0.stageId ?? FocusFlowID.make("missingStage") })
        let stages = groupedStages.values.map { records -> HistoryStageRecord in
            let sorted = records.sorted { $0.timestamp < $1.timestamp }
            let last = sorted.last
            return HistoryStageRecord(
                stageId: last?.stageId,
                title: last?.stageTitle ?? "Stage",
                stageType: last?.stageType,
                status: last?.status,
                localDay: last?.localDay ?? FocusFlowCalendar.localDay(),
                plannedSeconds: last?.plannedDurationSeconds,
                actualFocusSeconds: sorted.reduce(0) { $0 + ($1.actualFocusSeconds ?? 0) },
                pauseCount: sorted.compactMap(\.pauseCount).reduce(0, +)
            )
        }
        .sorted { $0.localDay < $1.localDay }

        return HistoryTaskDetail(
            taskId: taskId,
            title: last.taskTitle ?? first.taskTitle ?? "Learning task",
            taskType: last.taskType ?? first.taskType,
            firstLocalDay: first.localDay,
            latestLocalDay: last.localDay,
            status: last.status,
            totalFocusSeconds: events.reduce(0) { $0 + ($1.actualFocusSeconds ?? 0) },
            completedStageCount: events.filter { $0.eventType == .stageCompleted }.count,
            skippedStageCount: events.filter { $0.eventType == .stageSkipped }.count,
            abandonedStageCount: events.filter { $0.eventType == .stageAbandoned }.count,
            stages: stages,
            eventCount: events.count
        )
    }

    public func deleteHistoryTask(taskId: String) async throws {
        try await rewriteEvents { $0.taskId != taskId }
        let taskURL = directory.tasks.appendingPathComponent("\(taskId).json")
        if FileManager.default.fileExists(atPath: taskURL.path) {
            try FileManager.default.removeItem(at: taskURL)
        }
        try await appendEvent(LearningEvent(
            eventType: .dataDeleted,
            sourceModule: .module5DataCenter,
            taskId: taskId,
            status: "task_history_deleted",
            tags: ["privacy", "delete"]
        ))
    }

    public func deleteHistoryDay(localDay: String) async throws {
        try await rewriteEvents { $0.localDay != localDay }
        try await appendEvent(LearningEvent(
            eventType: .dataDeleted,
            sourceModule: .module5DataCenter,
            status: "day_history_deleted",
            tags: ["privacy", "delete"],
            metadata: ["local_day": localDay]
        ))
    }

    public func exportEventsMarkdown() async throws -> String {
        let events = try await loadAllEvents().sorted { $0.timestamp < $1.timestamp }
        var lines = ["# FocusFlow Export", "", "Data stays local unless you choose to share it.", ""]
        for event in events {
            let title = event.taskTitle ?? "Learning task"
            lines.append("- \(event.localDay): \(event.eventType.rawValue) - \(title)")
        }
        return lines.joined(separator: "\n")
    }

    public func exportEventsJSON() async throws -> String {
        let data = try FocusFlowJSON.encoder.encode(try await loadAllEvents().sorted { $0.timestamp < $1.timestamp })
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    public func exportEventsCSV() async throws -> String {
        let events = try await loadAllEvents().sorted { $0.timestamp < $1.timestamp }
        var lines = ["id,event_type,source_module,timestamp,local_day,task_id,stage_id,task_title,task_type,stage_title,stage_type,status,planned_seconds,actual_focus_seconds,pause_count,tags"]
        for event in events {
            let fields: [String] = [
                event.id,
                event.eventType.rawValue,
                event.sourceModule.rawValue,
                ISO8601DateFormatter().string(from: event.timestamp),
                event.localDay,
                event.taskId ?? "",
                event.stageId ?? "",
                event.taskTitle ?? "",
                event.taskType?.rawValue ?? "",
                event.stageTitle ?? "",
                event.stageType?.rawValue ?? "",
                event.status ?? "",
                event.plannedDurationSeconds.map(String.init) ?? "",
                event.actualFocusSeconds.map(String.init) ?? "",
                event.pauseCount.map(String.init) ?? "",
                event.tags.joined(separator: "|")
            ]
            lines.append(fields.map { csvEscape($0) }.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    public func saveClosureSummary(_ summary: TaskClosureSummary) async throws {
        try directory.prepare()
        let data = try FocusFlowJSON.encoder.encode(summary)
        try await writePlainData(data, to: closureSummaryURL(taskId: summary.taskId))
    }

    public func getClosureSummary(taskId: String) async throws -> TaskClosureSummary {
        try directory.prepare()
        let url = closureSummaryURL(taskId: taskId)
        guard let summary = try await decodeLocalFile(TaskClosureSummary.self, from: url) else {
            throw FocusFlowError.taskNotFound(taskId)
        }
        return summary
    }

    public func submitProfileCorrection(_ correction: ProfileCorrection) async throws -> UserProfileSnapshot {
        try directory.prepare()
        let existing = try await getUserProfileSnapshot()
        let affected = Set(correction.affectedStageTypes)
        let corrected = UserProfileSnapshot(
            preferredStageDurationSeconds: existing.preferredStageDurationSeconds,
            recommendedFirstStageSeconds: existing.recommendedFirstStageSeconds,
            difficultStageTypes: existing.difficultStageTypes.filter { !affected.contains($0) },
            easierStageTypes: existing.easierStageTypes.filter { !affected.contains($0) },
            effectiveInterventions: existing.effectiveInterventions,
            encouragementStyle: existing.encouragementStyle,
            rewardPreference: existing.rewardPreference,
            streakSensitivity: existing.streakSensitivity,
            confidence: max(0, existing.confidence - min(1, max(0, correction.confidenceImpact))),
            lastUpdatedAt: Date()
        )
        let data = try FocusFlowJSON.encoder.encode(corrected)
        try await writePlainData(data, to: directory.profile.appendingPathComponent("user_profile.json"))
        try await appendProfileSnapshot(corrected)
        try await recordEvent(LearningEvent(
            eventType: .profileCorrectionSubmitted,
            sourceModule: .module5DataCenter,
            relatedObjectId: correction.id,
            status: "profile_observation_inaccurate",
            tags: ["profile", "correction"],
            metadata: [
                "reason": correction.reason,
                "affected_stage_types": correction.affectedStageTypes.map(\.rawValue).joined(separator: ","),
                "note": correction.note ?? "",
                "confidence_impact": String(format: "%.2f", correction.confidenceImpact)
            ]
        ))
        return corrected
    }

    public func deleteAllUserData() async throws {
        try directory.removeAll()
        knownEventIds.removeAll()
        cachedEvents = nil
    }

    public func clearUserProfile() async throws {
        try directory.prepare()
        let profileURL = directory.profile.appendingPathComponent("user_profile.json")
        if FileManager.default.fileExists(atPath: profileURL.path) {
            try FileManager.default.removeItem(at: profileURL)
        }
        let snapshotURL = directory.profile.appendingPathComponent("profile_snapshots.jsonl")
        if FileManager.default.fileExists(atPath: snapshotURL.path) {
            try FileManager.default.removeItem(at: snapshotURL)
        }
        await recordProfileDeletionAudit()
    }

    private func recordProfileDeletionAudit() async {
        try? await appendEvent(LearningEvent(
            eventType: .dataDeleted,
            sourceModule: .module5DataCenter,
            status: "profile_memory_cleared",
            tags: ["privacy", "profile"],
            metadata: [
                "scope": "profile_memory",
                "history_preserved": "true"
            ]
        ))
    }

    private func loadAllEvents() async throws -> [LearningEvent] {
        if let cachedEvents {
            return cachedEvents
        }
        try directory.prepare()
        let urls = try FileManager.default.contentsOfDirectory(at: directory.events, includingPropertiesForKeys: nil)
        var events: [LearningEvent] = []
        for url in urls where url.pathExtension == "jsonl" {
            let content = (try? await readPlainTextFile(url)) ?? ""
            events.append(contentsOf: content.split(separator: "\n").compactMap { line in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? FocusFlowJSON.decoder.decode(LearningEvent.self, from: data)
            })
        }
        cachedEvents = events
        return events
    }

    private func rewriteEvents(keeping predicate: (LearningEvent) -> Bool) async throws {
        try directory.prepare()
        let retained = try await loadAllEvents().filter(predicate)
        let urls = try FileManager.default.contentsOfDirectory(at: directory.events, includingPropertiesForKeys: nil)
        for url in urls where url.pathExtension == "jsonl" {
            try FileManager.default.removeItem(at: url)
        }
        knownEventIds.removeAll()
        cachedEvents = []
        for event in retained.sorted(by: { $0.timestamp < $1.timestamp }) {
            try await appendEvent(event)
        }
    }

    private func filteredEvents(for range: StatsRange) async throws -> [LearningEvent] {
        eventsInRange(try await loadAllEvents(), range: range)
    }

    private func eventsInRange(_ events: [LearningEvent], range: StatsRange) -> [LearningEvent] {
        guard range != .allTime else { return events }
        guard let lowerBound = lowerBoundDate(for: range) else { return events }
        return events.filter { $0.timestamp >= lowerBound }
    }

    private func lowerBoundDate(for range: StatsRange) -> Date? {
        let calendar = Calendar.current
        let now = Date()
        switch range {
        case .today:
            return calendar.startOfDay(for: now)
        case .last7Days:
            return calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))
        case .last30Days:
            return calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now))
        case .thisMonth:
            return calendar.date(from: calendar.dateComponents([.year, .month], from: now))
        case .allTime:
            return nil
        }
    }

    private func dayKeys(for range: StatsRange) -> [String] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let count: Int
        switch range {
        case .today:
            count = 1
        case .last7Days:
            count = 7
        case .last30Days, .allTime:
            count = 30
        case .thisMonth:
            count = calendar.component(.day, from: today)
        }
        return (0..<count).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset - (count - 1), to: today) else { return nil }
            return FocusFlowCalendar.localDay(for: date, calendar: calendar)
        }
    }

    private func statsFromEvents(_ events: [LearningEvent], range: StatsRange) -> StatsSummary {
        let scoped = eventsInRange(events, range: range)
        let activeDaySet = Set(scoped.compactMap { event -> String? in
            if event.eventType == .stageCompleted || (event.actualFocusSeconds ?? 0) >= 300 || event.eventType == .taskCompleted || event.eventType == .manualCheckIn {
                return event.localDay
            }
            return nil
        })
        let completedStages = scoped.filter { $0.eventType == .stageCompleted }
        let skippedStages = scoped.filter { $0.eventType == .stageSkipped }
        let abandonedStages = scoped.filter { $0.eventType == .stageAbandoned }
        let completedTasks = scoped.filter { $0.eventType == .taskCompleted }
        let abandonedTasks = scoped.filter { $0.eventType == .taskAbandoned }
        let stageDenominator = completedStages.count + skippedStages.count + abandonedStages.count
        let taskDenominator = completedTasks.count + abandonedTasks.count
        return StatsSummary(
            range: range,
            activeDays: activeDaySet.count,
            strictStreakDays: strictStreakDays(from: activeDaySet),
            gentleRhythmText: rhythmText(activeDays: activeDaySet.count, range: range),
            totalFocusSeconds: scoped.reduce(0) { $0 + ($1.actualFocusSeconds ?? 0) },
            completedStageCount: completedStages.count,
            stageCompletionRate: stageDenominator == 0 ? nil : Double(completedStages.count) / Double(stageDenominator),
            taskCompletionRate: taskDenominator < 3 ? nil : Double(completedTasks.count) / Double(taskDenominator),
            recoveryCount: scoped.filter { $0.eventType == .stageResumed }.count
        )
    }

    private func strictStreakDays(from activeDays: Set<String>) -> Int {
        var count = 0
        var day = Calendar.current.startOfDay(for: Date())
        while activeDays.contains(FocusFlowCalendar.localDay(for: day)) {
            count += 1
            guard let previous = Calendar.current.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    private func rhythmText(activeDays: Int, range: StatsRange) -> String {
        switch (activeDays, range) {
        case (0, _):
            return "Your rhythm is ready when you are."
        case (1, .today):
            return "You came back to learning today."
        case (_, .last7Days):
            return "You returned to learning \(activeDays) day\(activeDays == 1 ? "" : "s") this week."
        case (_, .thisMonth):
            return "You returned to learning \(activeDays) day\(activeDays == 1 ? "" : "s") this month."
        default:
            return "You have \(activeDays) active learning day\(activeDays == 1 ? "" : "s")."
        }
    }

    private func repeatedStageTypes(from events: [LearningEvent]) -> [StageType] {
        let counts = Dictionary(grouping: events.compactMap(\.stageType), by: { $0 }).mapValues(\.count)
        return counts.filter { $0.value >= 3 }.keys.sorted { $0.rawValue < $1.rawValue }
    }

    private func isDifficultFeedbackIntent(_ intent: String?) -> Bool {
        guard let intent else { return false }
        let normalized = intent
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "")
            .lowercased()
        return [
            FeedbackIntent.tooHard.rawValue,
            FeedbackIntent.distracted.rawValue,
            FeedbackIntent.unclearInstruction.rawValue,
            FeedbackIntent.wantToQuit.rawValue,
            "too_hard",
            "unclear_instruction",
            "want_to_quit"
        ]
        .map { $0.replacingOccurrences(of: "_", with: "").lowercased() }
        .contains(normalized)
    }

    private func readPlainData(_ url: URL) async throws -> Data {
        let data = try Data(contentsOf: url)
        return try await encryptionService.decryptIfNeeded(data)
    }

    private func readPlainTextFile(_ url: URL) async throws -> String {
        let data = try await readPlainData(url)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func writePlainData(_ data: Data, to url: URL) async throws {
        let output = localEncryptionEnabled ? try await encryptionService.encrypt(data) : data
        try output.write(to: url, options: [.atomic])
    }

    private func writePlainText(_ text: String, to url: URL) async throws {
        guard let data = text.data(using: .utf8) else {
            throw FocusFlowError.storageFailure("Could not encode local storage text.")
        }
        try await writePlainData(data, to: url)
    }

    private func appendProfileSnapshot(_ snapshot: UserProfileSnapshot) async throws {
        let url = directory.profile.appendingPathComponent("profile_snapshots.jsonl")
        var existing = ""
        if FileManager.default.fileExists(atPath: url.path) {
            existing = try await readPlainTextFile(url)
        }
        let data = try FocusFlowJSON.lineEncoder.encode(snapshot)
        guard var line = String(data: data, encoding: .utf8) else {
            throw FocusFlowError.storageFailure("Could not encode profile snapshot.")
        }
        line.append("\n")
        try await writePlainText(existing + line, to: url)
    }

    private func decodeLocalFile<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let rawData = try Data(contentsOf: url)
        if LocalEncryptionService.isEncrypted(rawData) {
            let data = try await encryptionService.decryptIfNeeded(rawData)
            return try FocusFlowJSON.decoder.decode(T.self, from: data)
        }
        return try CorruptFileRecovery.decodeOrQuarantine(T.self, from: url, root: directory.root)
    }

    private func loadAchievements() async throws -> [String: Achievement] {
        let url = directory.achievements.appendingPathComponent("unlocked.json")
        return try await decodeLocalFile([String: Achievement].self, from: url) ?? [:]
    }

    private func saveAchievements(_ achievements: [String: Achievement]) async throws {
        try directory.prepare()
        let data = try FocusFlowJSON.encoder.encode(achievements)
        try await writePlainData(data, to: directory.achievements.appendingPathComponent("unlocked.json"))
    }

    private func loadPendingAchievements() async throws -> [String: Achievement] {
        let url = directory.achievements.appendingPathComponent("pending_queue.json")
        return try await decodeLocalFile([String: Achievement].self, from: url) ?? [:]
    }

    private func savePendingAchievements(_ achievements: [Achievement]) async throws {
        var pending = try await loadPendingAchievements()
        for achievement in achievements {
            pending[achievement.id] = achievement
        }
        try await savePendingAchievementMap(pending)
    }

    private func savePendingAchievementMap(_ achievements: [String: Achievement]) async throws {
        try directory.prepare()
        let data = try FocusFlowJSON.encoder.encode(achievements)
        try await writePlainData(data, to: directory.achievements.appendingPathComponent("pending_queue.json"))
    }

    private func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
            return "\"\(escaped)\""
        }
        return escaped
    }

    private func closureSummaryURL(taskId: String) -> URL {
        directory.summaries.appendingPathComponent("\(taskId)_closure.json")
    }
}

private extension Array where Element == Int {
    func averageInt() -> Int? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / count
    }
}
