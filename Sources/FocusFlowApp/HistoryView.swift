import FocusFlowCore
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: FocusFlowAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                naturalQueryBar
                filterBar
                historyList
                if let detail = model.selectedHistoryDetail {
                    HistoryDetailCard(detail: detail)
                }
            }
            .padding(42)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            try? await model.refreshHistory()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("History")
                    .font(AppFont.pageTitle)
                    .foregroundStyle(AppColor.textPrimary)
                Text("Search, filter, and revisit your learning sessions.")
                    .font(.title3)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
            Button {
                model.selectTab(.insights)
            } label: {
                Label("Back to insights", systemImage: "chevron.left")
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("history_back_button")
        }
    }

    private var naturalQueryBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ask in your own words")
                .font(.headline)
                .foregroundStyle(AppColor.textPrimary)
            AdaptiveButtonRow {
                TextField("Try: last week reading records", text: $model.naturalHistoryQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                Button("Ask history") {
                    model.applyNaturalHistoryQuery()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .focusCard()
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Filter")
                .font(.headline)
                .foregroundStyle(AppColor.textPrimary)
            AdaptiveButtonRow {
                TextField("Search task or stage", text: $model.historyKeyword)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
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
            }
        }
        .focusCard()
    }

    @ViewBuilder
    private var historyList: some View {
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
    }
}

struct HistoryDetailCard: View {
    @EnvironmentObject private var model: FocusFlowAppModel
    let detail: HistoryTaskDetail

    var body: some View {
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
                HStack { detailMetrics }
                VStack(spacing: 10) { detailMetrics }
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

    @ViewBuilder
    private var detailMetrics: some View {
        MetricCard(title: "Focus", value: detail.totalFocusSeconds.minutesText, tint: AppColor.actionPrimary)
        MetricCard(title: "Completed", value: "\(detail.completedStageCount)", tint: AppColor.success)
        MetricCard(title: "Saved/Skipped", value: "\(detail.skippedStageCount + detail.abandonedStageCount)", tint: AppColor.warning)
    }
}
