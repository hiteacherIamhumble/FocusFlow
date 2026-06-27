import FocusFlowCore
import Charts
import SwiftUI

struct PersonalCenterView: View {
    @EnvironmentObject private var model: FocusFlowAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Personal center")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(FFColors.ink)
                    Text(model.stats?.gentleRhythmText ?? "FocusFlow is still learning your rhythm.")
                        .font(.title3)
                        .foregroundStyle(FFColors.softGray)
                }

                HStack(spacing: 14) {
                    MetricCard(title: "Learning rhythm", value: "\(model.stats?.activeDays ?? 0) days", tint: FFColors.mint)
                    MetricCard(title: "This week focus", value: (model.stats?.totalFocusSeconds ?? 0).minutesText, tint: FFColors.blue)
                    MetricCard(title: "Stages completed", value: "\(model.stats?.completedStageCount ?? 0)", tint: FFColors.peach)
                }

                FocusTrendView(points: model.dailyStats)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Agent observation")
                        .font(.headline)
                        .foregroundStyle(FFColors.ink)
                    Text(model.agentObservation.text)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(FFColors.ink)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                    Button {
                        model.markProfileObservationInaccurate()
                    } label: {
                        Label("This observation is inaccurate", systemImage: "hand.raised")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("profile_observation_inaccurate_button")
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent history")
                        .font(.headline)
                        .foregroundStyle(FFColors.ink)
                    HStack {
                        TextField("Try: last week reading records", text: $model.naturalHistoryQuery)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 280)
                        Button("Ask history") {
                            model.applyNaturalHistoryQuery()
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    HStack {
                        TextField("Search task or stage", text: $model.historyKeyword)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 260)
                        Picker("Range", selection: $model.historyRange) {
                            Text("Today").tag(StatsRange.today)
                            Text("7 days").tag(StatsRange.last7Days)
                            Text("30 days").tag(StatsRange.last30Days)
                            Text("This month").tag(StatsRange.thisMonth)
                            Text("All").tag(StatsRange.allTime)
                        }
                        .frame(width: 150)
                        Picker("Type", selection: $model.historyTaskType) {
                            Text("All types").tag(EducationTaskType.unknown)
                            Text("Writing").tag(EducationTaskType.writing)
                            Text("Reading").tag(EducationTaskType.reading)
                            Text("Review").tag(EducationTaskType.examReview)
                            Text("Homework").tag(EducationTaskType.homework)
                            Text("Presentation").tag(EducationTaskType.presentation)
                            Text("Project").tag(EducationTaskType.longTermProject)
                        }
                        .frame(width: 170)
                        Button("Apply") {
                            model.applyHistoryFilters()
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        if let day = model.deletableHistoryDay {
                            Button("Delete \(day)") {
                                model.deleteSelectedHistoryDay()
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                    if model.history.isEmpty {
                        Text("No learning history yet. The first small step will show up here.")
                            .font(.body)
                            .foregroundStyle(FFColors.softGray)
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        ForEach(model.history) { item in
                            Button {
                                model.loadHistoryDetail(item)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(item.title)
                                            .font(.headline)
                                            .foregroundStyle(FFColors.ink)
                                        Text("\(item.localDay) · \(item.taskType?.readableName ?? "Learning")")
                                            .font(.caption)
                                            .foregroundStyle(FFColors.softGray)
                                    }
                                    Spacer()
                                    Text("\(item.completedStageCount) steps")
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(FFColors.blue)
                                    Text(item.totalFocusSeconds.minutesText)
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(FFColors.softGray)
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(FFColors.softGray)
                                }
                                .padding(16)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if let detail = model.selectedHistoryDetail {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(detail.title)
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(FFColors.ink)
                                    Text("\(detail.firstLocalDay) to \(detail.latestLocalDay) · \(detail.eventCount) events")
                                        .font(.caption)
                                        .foregroundStyle(FFColors.softGray)
                                }
                                Spacer()
                                Button("Delete this task history") {
                                    model.deleteHistoryTask(detail)
                                }
                                .buttonStyle(SecondaryButtonStyle())
                            }
                            HStack {
                                MetricCard(title: "Focus", value: detail.totalFocusSeconds.minutesText, tint: FFColors.blue)
                                MetricCard(title: "Completed", value: "\(detail.completedStageCount)", tint: FFColors.mint)
                                MetricCard(title: "Saved/Skipped", value: "\(detail.skippedStageCount + detail.abandonedStageCount)", tint: FFColors.peach)
                            }
                            ForEach(detail.stages) { stage in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(stage.title)
                                            .font(.callout.weight(.semibold))
                                            .foregroundStyle(FFColors.ink)
                                        Text(stage.status ?? "recorded")
                                            .font(.caption)
                                            .foregroundStyle(FFColors.softGray)
                                    }
                                    Spacer()
                                    Text((stage.actualFocusSeconds ?? 0).minutesText)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(FFColors.blue)
                                }
                                .padding(12)
                                .background(Color.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(16)
                        .background(FFColors.lavender, in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Achievement garden")
                        .font(.headline)
                        .foregroundStyle(FFColors.ink)
                    if !model.pendingAchievements.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(model.pendingAchievements) { achievement in
                                HStack {
                                    Image(systemName: achievement.iconName)
                                        .foregroundStyle(FFColors.peach)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(achievement.title)
                                            .font(.headline)
                                            .foregroundStyle(FFColors.ink)
                                        Text(achievement.message)
                                            .font(.callout)
                                            .foregroundStyle(FFColors.softGray)
                                    }
                                    Spacer()
                                    Button("Save") {
                                        model.dismissAchievement(achievement)
                                    }
                                    .buttonStyle(SecondaryButtonStyle())
                                }
                                .padding(14)
                                .background(FFColors.peach.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                        ForEach(AchievementCatalog.all) { definition in
                            let achievement = model.achievements.first { $0.id == definition.id }
                            Badge(
                                title: achievement?.title ?? definition.title,
                                message: achievement?.message ?? definition.message,
                                icon: achievement?.iconName ?? definition.iconName,
                                unlocked: achievement != nil
                            )
                        }
                    }
                }
            }
            .padding(42)
        }
        .task {
            await model.refreshStats()
        }
    }

}

struct FocusTrendView: View {
    let points: [DailyStatsPoint]

    private var hasFocusData: Bool {
        points.contains { $0.focusSeconds > 0 || $0.completedStageCount > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("7-day focus trend")
                    .font(.headline)
                    .foregroundStyle(FFColors.ink)
                Spacer()
                Text("\(points.reduce(0) { $0 + $1.completedStageCount }) steps")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FFColors.blue)
            }
            if hasFocusData {
                Chart(points) { point in
                    BarMark(
                        x: .value("Day", dayLabel(point.localDay)),
                        y: .value("Minutes", Double(point.focusSeconds) / 60.0)
                    )
                    .foregroundStyle(FFColors.blue.gradient)
                    .cornerRadius(5)
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel()
                            .foregroundStyle(FFColors.softGray)
                    }
                }
                .frame(height: 150)
            } else {
                Text("No focus minutes recorded yet.")
                    .font(.callout)
                    .foregroundStyle(FFColors.softGray)
                    .frame(maxWidth: .infinity, minHeight: 150, alignment: .center)
                    .background(FFColors.canvas.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack(spacing: 8) {
                ForEach(points) { point in
                    VStack(spacing: 4) {
                        Text(dayLabel(point.localDay))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(FFColors.softGray)
                        Text("\(point.completedStageCount)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(point.completedStageCount > 0 ? FFColors.mint : FFColors.softGray)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
    }

    private func dayLabel(_ localDay: String) -> String {
        String(localDay.suffix(5))
    }
}

struct Badge: View {
    let title: String
    let message: String
    let icon: String
    let unlocked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(unlocked ? FFColors.blue : FFColors.softGray)
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(FFColors.ink)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            Text(message)
                .font(.caption)
                .foregroundStyle(FFColors.softGray)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background((unlocked ? FFColors.peach.opacity(0.22) : Color.white.opacity(0.70)), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .topTrailing) {
            Image(systemName: unlocked ? "checkmark.circle.fill" : "lock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(unlocked ? FFColors.mint : FFColors.softGray.opacity(0.7))
                .padding(10)
        }
    }
}
