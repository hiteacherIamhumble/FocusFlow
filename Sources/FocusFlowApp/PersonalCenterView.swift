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
                        .font(AppFont.pageTitle)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(model.stats?.gentleRhythmText ?? "FocusFlow is still learning your rhythm.")
                        .font(.title3)
                        .foregroundStyle(AppColor.textSecondary)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) {
                        MetricCard(title: "Learning rhythm", value: "\(model.stats?.activeDays ?? 0) days", tint: AppColor.success)
                        MetricCard(title: "This week focus", value: (model.stats?.totalFocusSeconds ?? 0).minutesText, tint: AppColor.actionPrimary)
                        MetricCard(title: "Stages completed", value: "\(model.stats?.completedStageCount ?? 0)", tint: AppColor.warning)
                    }
                    VStack(spacing: 14) {
                        MetricCard(title: "Learning rhythm", value: "\(model.stats?.activeDays ?? 0) days", tint: AppColor.success)
                        MetricCard(title: "This week focus", value: (model.stats?.totalFocusSeconds ?? 0).minutesText, tint: AppColor.actionPrimary)
                        MetricCard(title: "Stages completed", value: "\(model.stats?.completedStageCount ?? 0)", tint: AppColor.warning)
                    }
                }

                FocusTrendView(points: model.dailyStats)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Agent observation")
                        .font(.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(model.agentObservation.text)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppColor.surfaceCard, in: RoundedRectangle(cornerRadius: 8))
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
                        .foregroundStyle(AppColor.textPrimary)
                    AdaptiveButtonRow {
                        TextField("Try: last week reading records", text: $model.naturalHistoryQuery)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 280)
                        Button("Ask history") {
                            model.applyNaturalHistoryQuery()
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    AdaptiveButtonRow {
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
                            .foregroundStyle(AppColor.textSecondary)
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppColor.surfaceCard, in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        ForEach(model.history) { item in
                            Button {
                                model.loadHistoryDetail(item)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(item.title)
                                            .font(.headline)
                                            .foregroundStyle(AppColor.textPrimary)
                                        Text("\(item.localDay) · \(item.taskType?.readableName ?? "Learning")")
                                            .font(.caption)
                                            .foregroundStyle(AppColor.textSecondary)
                                    }
                                    Spacer()
                                    Text("\(item.completedStageCount) steps")
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(AppColor.actionPrimary)
                                    Text(item.totalFocusSeconds.minutesText)
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(AppColor.textSecondary)
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(AppColor.textSecondary)
                                }
                                .padding(16)
                                .background(AppColor.surfaceCard, in: RoundedRectangle(cornerRadius: 8))
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
                                        .foregroundStyle(AppColor.textPrimary)
                                    Text("\(detail.firstLocalDay) to \(detail.latestLocalDay) · \(detail.eventCount) events")
                                        .font(.caption)
                                        .foregroundStyle(AppColor.textSecondary)
                                }
                                Spacer()
                                Button("Delete this task history") {
                                    model.deleteHistoryTask(detail)
                                }
                                .buttonStyle(SecondaryButtonStyle())
                            }
                            ViewThatFits(in: .horizontal) {
                                HStack {
                                    MetricCard(title: "Focus", value: detail.totalFocusSeconds.minutesText, tint: AppColor.actionPrimary)
                                    MetricCard(title: "Completed", value: "\(detail.completedStageCount)", tint: AppColor.success)
                                    MetricCard(title: "Saved/Skipped", value: "\(detail.skippedStageCount + detail.abandonedStageCount)", tint: AppColor.warning)
                                }
                                VStack(spacing: 10) {
                                    MetricCard(title: "Focus", value: detail.totalFocusSeconds.minutesText, tint: AppColor.actionPrimary)
                                    MetricCard(title: "Completed", value: "\(detail.completedStageCount)", tint: AppColor.success)
                                    MetricCard(title: "Saved/Skipped", value: "\(detail.skippedStageCount + detail.abandonedStageCount)", tint: AppColor.warning)
                                }
                            }
                            ForEach(detail.stages) { stage in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(stage.title)
                                            .font(.callout.weight(.semibold))
                                            .foregroundStyle(AppColor.textPrimary)
                                        Text(stage.status ?? "recorded")
                                            .font(.caption)
                                            .foregroundStyle(AppColor.textSecondary)
                                    }
                                    Spacer()
                                    Text((stage.actualFocusSeconds ?? 0).minutesText)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AppColor.actionPrimary)
                                }
                                .padding(12)
                                .background(AppColor.surfaceCard.opacity(0.86), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(16)
                        .background(AppColor.actionContainer, in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Achievement garden")
                        .font(.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    if !model.pendingAchievements.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(model.pendingAchievements) { achievement in
                                HStack {
                                    Image(systemName: achievement.iconName)
                                        .foregroundStyle(AppColor.warning)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(achievement.title)
                                            .font(.headline)
                                            .foregroundStyle(AppColor.textPrimary)
                                        Text(achievement.message)
                                            .font(.callout)
                                            .foregroundStyle(AppColor.textSecondary)
                                    }
                                    Spacer()
                                    Button("Save") {
                                        model.dismissAchievement(achievement)
                                    }
                                    .buttonStyle(SecondaryButtonStyle())
                                }
                                .padding(14)
                                .background(AppColor.warning.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
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
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                Text("\(points.reduce(0) { $0 + $1.completedStageCount }) steps")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.actionPrimary)
            }
            if hasFocusData {
                Chart(points) { point in
                    BarMark(
                        x: .value("Day", dayLabel(point.localDay)),
                        y: .value("Minutes", Double(point.focusSeconds) / 60.0)
                    )
                    .foregroundStyle(AppColor.actionPrimary.gradient)
                    .cornerRadius(5)
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel()
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
                .frame(height: 150)
                .accessibilityLabel("Seven day focus trend")
                .accessibilityValue("\(points.reduce(0) { $0 + $1.completedStageCount }) completed steps")
            } else {
                Text("No focus minutes recorded yet.")
                    .font(.callout)
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 150, alignment: .center)
                    .background(AppColor.bgBase.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack(spacing: 8) {
                ForEach(points) { point in
                    VStack(spacing: 4) {
                        Text(dayLabel(point.localDay))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppColor.textSecondary)
                        Text("\(point.completedStageCount)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(point.completedStageCount > 0 ? AppColor.success : AppColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(18)
        .background(AppColor.surfaceCard, in: RoundedRectangle(cornerRadius: 8))
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
                    .font(.title3.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(unlocked ? AppColor.actionPrimary : AppColor.textSecondary)
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            Text(message)
                .font(.caption)
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background((unlocked ? AppColor.warning.opacity(0.22) : AppColor.surfaceCard.opacity(0.70)), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .topTrailing) {
            Image(systemName: unlocked ? "checkmark.circle.fill" : "lock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(unlocked ? AppColor.success : AppColor.textSecondary.opacity(0.7))
                .padding(10)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(unlocked ? "Unlocked" : "Locked"). \(message)")
    }
}
