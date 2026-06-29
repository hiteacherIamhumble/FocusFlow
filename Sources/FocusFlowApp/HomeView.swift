import FocusFlowCore
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: FocusFlowAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                heroCard
                unfinishedTasksSection
                bentoRow
                Spacer(minLength: 0)
            }
            .padding(42)
            .frame(maxWidth: 880, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            Task { await model.refreshStats() }
        }
    }

    private var visibleUnfinishedTasks: [TaskPlan] {
        let currentId = model.currentTask?.id
        return Array(model.uncompletedTasks.filter { $0.id != currentId }.prefix(5))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greeting)
                .font(AppFont.pageTitle)
                .foregroundStyle(AppColor.textPrimary)
            Text("Local-first. One small step at a time.")
                .font(.title3)
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.hasResumableTask, let task = model.currentTask {
                Text("Coming back also counts as progress.")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Text(task.title)
                    .font(.title3)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(2)
                HStack(spacing: 12) {
                    Button {
                        model.enterFocusFlow()
                    } label: {
                        Label("Continue last task", systemImage: "play.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("home_continue_task_button")

                    Button {
                        model.beginNewTask()
                    } label: {
                        Label("New task", systemImage: "plus")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("home_new_task_button")
                }
            } else {
                Text("Let's make one learning task smaller.")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Text("You don't need the full plan. Just name what to do, and we'll find the first tiny step.")
                    .font(.title3)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    model.beginNewTask()
                } label: {
                    Label("Start a new task", systemImage: "wand.and.stars")
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("home_start_new_task_button")
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.actionContainer, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColor.actionPrimary.opacity(0.15)))
    }

    private var bentoRow: some View {
        Button {
            model.selectTab(.insights)
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { bentoCards }
                VStack(spacing: 14) { bentoCards }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home_open_insights_button")
        .accessibilityLabel("Open insights")
    }

    @ViewBuilder
    private var unfinishedTasksSection: some View {
        if !visibleUnfinishedTasks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Unfinished tasks")
                            .font(.headline)
                            .foregroundStyle(AppColor.textPrimary)
                        Text("Paused, planned, and in-progress")
                            .font(.callout)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Spacer()
                    Button {
                        Task { await model.refreshUncompletedTasks() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColor.textSecondary)
                    .accessibilityLabel("Refresh unfinished tasks")
                }

                VStack(spacing: 10) {
                    ForEach(visibleUnfinishedTasks) { task in
                        UnfinishedTaskRow(task: task) {
                            model.resumeTask(task)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var bentoCards: some View {
        MetricCard(
            title: "Learning rhythm",
            value: "\(model.stats?.activeDays ?? 0) days",
            tint: AppColor.success
        )
        MetricCard(
            title: "This week focus",
            value: (model.stats?.totalFocusSeconds ?? 0).minutesText,
            tint: AppColor.actionPrimary
        )
        MetricCard(
            title: "Recent badges",
            value: "\(model.achievements.count)",
            tint: AppColor.peach
        )
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }
}

struct UnfinishedTaskRow: View {
    let task: TaskPlan
    let onResume: () -> Void

    private var completedCount: Int {
        task.stages.filter { $0.status == .completed }.count
    }

    private var nextStage: StagePlan? {
        let stages = task.stages.sorted { $0.order < $1.order }
        return stages.first { [.running, .paused, .overtime].contains($0.status) }
            ?? stages.first { [.idle, .adjusted].contains($0.status) }
    }

    private var statusLabel: String {
        switch task.status {
        case .draft, .planned:
            return "Plan ready"
        case .active:
            return "In progress"
        case .paused, .gracefullyPaused:
            return "Paused"
        default:
            return task.status.rawValue
        }
    }

    private var actionLabel: String {
        switch task.status {
        case .draft, .planned:
            return "Open plan"
        default:
            return "Resume"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: task.status == .paused || task.status == .gracefullyPaused ? "pause.circle.fill" : "circle.dotted")
                .font(.title3)
                .foregroundStyle(task.status == .paused || task.status == .gracefullyPaused ? AppColor.warning : AppColor.actionPrimary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                Text(nextStage.map { "Next: \($0.title)" } ?? "\(completedCount) of \(task.stages.count) steps done")
                    .font(.callout)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(1)
                Text("\(statusLabel) · \(completedCount) of \(task.stages.count) steps · about \(task.estimatedTotalSeconds.minutesText)")
                    .font(.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Button(actionLabel) {
                onResume()
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("resume_task_\(task.id)")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.surfaceCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColor.borderSubtle.opacity(0.7)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(task.title). \(statusLabel). \(completedCount) of \(task.stages.count) steps complete.")
    }
}
