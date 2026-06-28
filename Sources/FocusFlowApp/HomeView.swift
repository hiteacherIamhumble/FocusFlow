import FocusFlowCore
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: FocusFlowAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                heroCard
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
