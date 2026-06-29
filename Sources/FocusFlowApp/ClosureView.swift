import FocusFlowCore
import SwiftUI

struct ClosureView: View {
    @EnvironmentObject private var model: FocusFlowAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
            if let summary = model.closureSummary {
                Text(closureTitle(for: summary.closureType))
                    .font(AppFont.pageTitle)
                    .foregroundStyle(AppColor.textPrimary)

                Text(summary.encouragementText ?? summary.soothingText ?? "You can come back to this gently.")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(summary.closureType == .completed ? AppColor.success.opacity(0.20) : AppColor.actionContainer, in: RoundedRectangle(cornerRadius: 8))

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) {
                        MetricCard(title: "Focus time", value: summary.totalFocusSeconds.minutesText, tint: AppColor.actionPrimary)
                        MetricCard(title: "Steps completed", value: "\(summary.completedStageCount)", tint: AppColor.success)
                        MetricCard(title: "Saved next", value: "\(summary.skippedStageCount + summary.abandonedStageCount)", tint: AppColor.warning)
                    }
                    VStack(spacing: 14) {
                        MetricCard(title: "Focus time", value: summary.totalFocusSeconds.minutesText, tint: AppColor.actionPrimary)
                        MetricCard(title: "Steps completed", value: "\(summary.completedStageCount)", tint: AppColor.success)
                        MetricCard(title: "Saved next", value: "\(summary.skippedStageCount + summary.abandonedStageCount)", tint: AppColor.warning)
                    }
                }

                CompletionTimeline(task: model.currentTask, summary: summary)

                EmotionMarkingCard(selectedEmotion: summary.emotionTag)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Light review")
                            .font(.headline)
                            .foregroundStyle(AppColor.textPrimary)
                        Spacer()
                        if model.reviewWasSkipped {
                            Label("Skipped", systemImage: "checkmark.circle")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppColor.textSecondary)
                        } else {
                            Button("Skip review") {
                                model.skipClosureReview()
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(AppColor.textSecondary)
                            .accessibilityIdentifier("skip_closure_review_button")
                        }
                    }
                    ForEach(summary.reviewItems) { item in
                        ReviewItemRow(
                            item: item,
                            response: item.userConfirmed ?? model.reviewResponses[item.id],
                            disabled: model.reviewWasSkipped
                        )
                    }
                    AdaptiveButtonRow {
                        TextField("One-line note", text: $model.closureReviewNote)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("closure_review_note_field")
                        Button("Save note") {
                            model.submitClosureReviewNote()
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("save_closure_review_note_button")
                    }
                }

                AdaptiveButtonRow {
                    Button(summary.closureType == .completed ? "Start another task" : "Archive and start new") {
                        model.archiveClosureAndStartNew()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("start_another_task_button")

                    Button(summary.closureType == .completed ? "View history" : "Archive in history") {
                        model.archiveClosureAndOpenPersonalCenter()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("view_history_button")
                }

                if summary.closureType != .completed {
                    AbandonedClosureActions()
                }
            } else {
                EmptyExecutionView()
            }
            }
            .padding(42)
        }
    }

    private func closureTitle(for type: TaskClosureType) -> String {
        switch type {
        case .completed:
            return "This loop is closed"
        case .gracefullyPaused:
            return "Progress is saved"
        case .abandoned:
            return "Task stopped for today"
        case .archivedOnly:
            return "Task archived"
        }
    }
}

struct CompletionTimeline: View {
    let task: TaskPlan?
    let summary: TaskClosureSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Completion timeline")
                .font(.headline)
                .foregroundStyle(AppColor.textPrimary)
            ForEach((task?.stages.sorted(by: { $0.order < $1.order }) ?? []).prefix(20)) { stage in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon(for: stage.status))
                        .foregroundStyle(color(for: stage.status))
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stage.title)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(AppColor.textPrimary)
                        Text("\(stage.status.rawValue) · \(stage.estimatedSeconds.minutesText)")
                            .font(.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(AppColor.surfaceCard, in: RoundedRectangle(cornerRadius: 8))
            }
            if !summary.keyBreakthroughs.isEmpty {
                Text("Breakthroughs: \(summary.keyBreakthroughs.joined(separator: ", "))")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(AppColor.success)
            }
        }
    }

    private func icon(for status: StageStatus) -> String {
        switch status {
        case .completed: "checkmark.circle.fill"
        case .skipped: "forward.circle.fill"
        case .abandoned: "moon.circle.fill"
        case .paused: "pause.circle.fill"
        case .running, .overtime: "timer.circle.fill"
        case .adjusted: "slider.horizontal.3"
        case .idle: "circle"
        }
    }

    private func color(for status: StageStatus) -> Color {
        switch status {
        case .completed: AppColor.success
        case .skipped, .abandoned, .paused: AppColor.warning
        case .running, .overtime: AppColor.actionPrimary
        default: AppColor.textSecondary
        }
    }
}

struct AbandonedClosureActions: View {
    @EnvironmentObject private var model: FocusFlowAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What next?")
                .font(.headline)
                .foregroundStyle(AppColor.textPrimary)
            AdaptiveButtonRow {
                Button("Archive in history") {
                    model.archiveClosureAndOpenPersonalCenter()
                }
                .buttonStyle(SecondaryButtonStyle())
                Button("Split smaller") {
                    model.route = .plan
                    model.message = "Review the plan and split one stage smaller."
                }
                .buttonStyle(SecondaryButtonStyle())
                Button("Rest") {
                    model.message = "Rest is a valid next step. Your progress is saved."
                }
                .buttonStyle(SecondaryButtonStyle())
                Button("Archive and start new") {
                    model.archiveClosureAndStartNew()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(18)
        .background(AppColor.actionContainer, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct EmotionMarkingCard: View {
    @EnvironmentObject private var model: FocusFlowAppModel
    let selectedEmotion: EmotionTag?

    private let options: [(EmotionTag, String, String)] = [
        (.calm, "Calm", "leaf"),
        (.happy, "Good", "sparkles"),
        (.tired, "Tired", "moon"),
        (.frustrated, "Frustrated", "scribble"),
        (.overwhelmed, "Overwhelmed", "waveform.path.ecg"),
        (.anxious, "Anxious", "heart")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("How are you leaving this task?")
                    .font(.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                Text("Optional")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.textSecondary)
            }
            AdaptiveButtonRow {
                ForEach(options, id: \.0) { emotion, title, icon in
                    Button {
                        model.markClosureEmotion(emotion)
                    } label: {
                        Label(title, systemImage: selectedEmotion == emotion ? "checkmark.circle.fill" : icon)
                            .lineLimit(1)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .overlay {
                        if selectedEmotion == emotion {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppColor.success.opacity(0.78), lineWidth: 1)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(AppColor.surfaceCard, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ReviewItemRow: View {
    @EnvironmentObject private var model: FocusFlowAppModel
    let item: ReviewItem
    let response: Bool?
    let disabled: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.type == .highlight ? "checkmark.seal" : "lightbulb")
                .foregroundStyle(item.type == .highlight ? AppColor.success : AppColor.warning)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 10) {
                Text(item.text)
                    .font(.body)
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                AdaptiveButtonRow(spacing: 8) {
                    Button {
                        model.submitReviewResponse(item: item, confirmed: true)
                    } label: {
                        Label(response == true ? "Agreed" : "Agree", systemImage: response == true ? "checkmark.circle.fill" : "checkmark.circle")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(disabled)

                    Button {
                        model.submitReviewResponse(item: item, confirmed: false)
                    } label: {
                        Label(response == false ? "Noted" : "Not quite", systemImage: response == false ? "xmark.circle.fill" : "xmark.circle")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(disabled)
                }
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.surfaceCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            if let response {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(response ? AppColor.success.opacity(0.70) : AppColor.warning.opacity(0.70), lineWidth: 1)
            }
        }
    }
}
