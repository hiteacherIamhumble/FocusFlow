import FocusFlowCore
import Charts
import SwiftUI

struct PersonalCenterView: View {
    @EnvironmentObject private var model: FocusFlowAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if model.hasResumableTask {
                    resumeHero
                }
                coreMetrics
                FocusTrendView(points: model.dailyStats)
                achievementGarden
                agentObservation
                recentHistoryPreview
                dataPrivacyEntry
            }
            .padding(42)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            await model.refreshStats()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Insights")
                .font(AppFont.pageTitle)
                .foregroundStyle(AppColor.textPrimary)
            Text(model.stats?.gentleRhythmText ?? "FocusFlow is still learning your rhythm.")
                .font(.title3)
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    private var resumeHero: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Coming back also counts as progress.")
                    .font(.headline)
                    .foregroundStyle(AppColor.textPrimary)
                if let task = model.currentTask {
                    Text(task.title)
                        .font(.callout)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button {
                model.enterFocusFlow()
            } label: {
                Label("Continue last task", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("insights_continue_task_button")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.actionContainer, in: RoundedRectangle(cornerRadius: 12))
    }

    private var coreMetrics: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { coreMetricCards }
            VStack(spacing: 14) { coreMetricCards }
        }
    }

    @ViewBuilder
    private var coreMetricCards: some View {
        MetricCard(title: "Learning rhythm", value: "\(model.stats?.activeDays ?? 0) days", tint: AppColor.success)
        MetricCard(title: "This week focus", value: (model.stats?.totalFocusSeconds ?? 0).minutesText, tint: AppColor.actionPrimary)
        MetricCard(title: "Stages completed", value: "\(model.stats?.completedStageCount ?? 0)", tint: AppColor.peach)
    }

    private var achievementGarden: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Achievement garden")
                .font(.headline)
                .foregroundStyle(AppColor.textPrimary)
            if !model.pendingAchievements.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.pendingAchievements) { achievement in
                        HStack {
                            Image(systemName: achievement.iconName)
                                .foregroundStyle(AppColor.peach)
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
                        .background(AppColor.peach.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
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

    private var agentObservation: some View {
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
    }

    private var recentHistoryPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent history")
                    .font(.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                Button {
                    model.openHistory()
                } label: {
                    Label("View all history", systemImage: "chevron.right")
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("view_all_history_button")
            }
            if model.history.isEmpty {
                Text("No learning history yet. The first small step will show up here.")
                    .font(.body)
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColor.surfaceCard, in: RoundedRectangle(cornerRadius: 8))
            } else {
                ForEach(model.history.prefix(3)) { item in
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
                    }
                    .padding(16)
                    .background(AppColor.surfaceCard, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var dataPrivacyEntry: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .foregroundStyle(AppColor.actionPrimary)
            Text("Your data stays local. Manage privacy, export, and deletion in Settings.")
                .font(.callout)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button {
                model.selectTab(.settings)
            } label: {
                Label("Open settings", systemImage: "gearshape")
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("insights_open_settings_button")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.surfaceCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColor.borderSubtle.opacity(0.6)))
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
                    .foregroundStyle(unlocked ? AppColor.peach : AppColor.textSecondary)
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
        .background((unlocked ? AppColor.peach.opacity(0.20) : AppColor.surfaceCard.opacity(0.70)), in: RoundedRectangle(cornerRadius: 8))
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
