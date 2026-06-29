import FocusFlowCore
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: FocusFlowAppModel
    @State private var messageDismissTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColor.bgBase)
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                Circle()
                    .fill(model.remoteAgentStatus.contains("enabled") || model.remoteAgentStatus.contains("saved") ? AppColor.success : AppColor.warning)
                    .frame(width: 8, height: 8)
                Text(model.remoteAgentStatus.contains("enabled") || model.remoteAgentStatus.contains("saved") ? "Remote agent ready" : "Local fallback ready")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppColor.surfaceCard.opacity(0.88), in: RoundedRectangle(cornerRadius: 8))
            .padding(18)
        }
        .overlay(alignment: .top) {
            if let achievement = model.pendingAchievements.first, model.settings.achievementsToastEnabled {
                HStack(spacing: 12) {
                    Image(systemName: achievement.iconName)
                        .foregroundStyle(AppColor.warning)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(achievement.title)
                            .font(.headline)
                            .foregroundStyle(AppColor.textPrimary)
                        Text(achievement.message)
                            .font(.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Button("Save") {
                        model.dismissAchievement(achievement)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityHint("Saves this achievement to the achievement garden.")
                }
                .padding(14)
                .background(AppColor.surfaceCard.opacity(0.96), in: RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
                .padding(.top, 18)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Achievement unlocked: \(achievement.title). \(achievement.message)")
            }
        }
        .overlay(alignment: .bottom) {
            if let message = model.message {
                Text(message)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(AppColor.textPrimary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(AppColor.surfaceCard.opacity(0.94), in: RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
                    .padding(.bottom, 18)
                    .accessibilityLabel(message)
            }
        }
        .overlay {
            if let step = model.onboardingStep {
                OnboardingOverlay(step: step)
                    .environmentObject(model)
            }
        }
        .onChange(of: model.message) { _, message in
            scheduleMessageDismiss(for: message)
        }
        .onChange(of: model.isWorking) { _, isWorking in
            if !isWorking {
                scheduleMessageDismiss(for: model.message)
            }
        }
        .onDisappear {
            messageDismissTask?.cancel()
        }
    }

    private func scheduleMessageDismiss(for message: String?) {
        messageDismissTask?.cancel()
        guard let message, !model.isWorking else { return }
        messageDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_600_000_000)
            if model.message == message, !model.isWorking {
                model.message = nil
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.route {
        case .home:
            HomeView()
        case .input, .plan, .execution, .closure:
            VStack(spacing: 0) {
                FlowStepIndicator(currentRoute: model.route) { step in
                    model.goToFlowStep(step)
                }
                Divider()
                flowBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .personalCenter:
            PersonalCenterView()
        case .history:
            HistoryView()
        case .settings:
            SettingsView()
        }
    }

    @ViewBuilder
    private var flowBody: some View {
        switch model.route {
        case .plan:
            PlanPreviewView()
        case .execution:
            ExecutionCenterView()
        case .closure:
            ClosureView()
        default:
            TaskInputView()
        }
    }
}

struct Sidebar: View {
    @EnvironmentObject private var model: FocusFlowAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("FocusFlow")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppColor.textPrimary)
                Text("Learning agent")
                    .font(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            .padding(.bottom, 12)

            NavButton(title: "Home", systemImage: "house", tab: .home)
            NavButton(title: "Focus", systemImage: "timer", tab: .focus)
            NavButton(title: "Insights", systemImage: "chart.line.uptrend.xyaxis", tab: .insights)
            NavButton(title: "Settings", systemImage: "gearshape", tab: .settings)

            Spacer()
            Button {
                model.startOnboarding()
            } label: {
                Label("Guide", systemImage: "questionmark.circle")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppColor.surfaceSubtle, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppColor.textPrimary)
            .accessibilityIdentifier("open_onboarding_guide_button")

            Text("Local-first. No diagnosis. No shame loops.")
                .font(.caption)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(width: 210)
        .background(AppColor.surfaceCard)
    }
}

struct OnboardingOverlay: View {
    @EnvironmentObject private var model: FocusFlowAppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let step: FocusFlowAppModel.OnboardingStep

    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(step.numberText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppColor.actionPrimary)
                    Spacer()
                    Button("Skip") {
                        model.completeOnboarding()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColor.textSecondary)
                    .accessibilityIdentifier("skip_onboarding_button")
                }

                Label(copy.title, systemImage: copy.icon)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppColor.textPrimary)

                Text(copy.body)
                    .font(.body)
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(copy.pointingText)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColor.actionContainer, in: RoundedRectangle(cornerRadius: 8))

                HStack {
                    Button("Back") {
                        model.goBackOnboarding()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(step.rawValue == 0)
                    .accessibilityIdentifier("onboarding_back_button")

                    Spacer()

                    Button(step == .settings ? "Done" : "Next") {
                        model.advanceOnboarding()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("onboarding_next_button")
                }
            }
            .padding(22)
            .frame(width: 390)
            .background(AppColor.surfaceCard, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColor.focusRing.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.98).combined(with: .opacity))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(copy.title). \(copy.body)")
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: step.rawValue)
    }

    private var copy: OnboardingCopy {
        switch step {
        case .welcome:
            return OnboardingCopy(
                icon: "house",
                title: "Start from Home",
                body: "Home shows your current task and any unfinished tasks saved for later.",
                pointingText: "Use Continue or the Unfinished tasks list when you want to return to work."
            )
        case .startFocus:
            return OnboardingCopy(
                icon: "wand.and.stars",
                title: "Name one learning task",
                body: "In Focus, write the messy version of what you need to do. The agent turns it into small stages.",
                pointingText: "The task box is where the main flow begins."
            )
        case .planReview:
            return OnboardingCopy(
                icon: "list.bullet.clipboard",
                title: "Review before starting",
                body: "After planning, you can edit stages by hand or ask AI to revise the plan before starting.",
                pointingText: "The top step indicator shows where you are in the flow."
            )
        case .focusSession:
            return OnboardingCopy(
                icon: "timer",
                title: "Work one stage at a time",
                body: "This preview task shows the real session controls without saving anything to your history.",
                pointingText: "During a session, use Pause timer, +5, Stuck, Skip, or finish only the current step."
            )
        case .saveForLater:
            return OnboardingCopy(
                icon: "tray.and.arrow.down",
                title: "Switch without losing your place",
                body: "This same screen lets real tasks pause cleanly when you need to switch context.",
                pointingText: "Use More > Save for later to return tasks to Home under Unfinished tasks."
            )
        case .insights:
            return OnboardingCopy(
                icon: "chart.line.uptrend.xyaxis",
                title: "Check learning patterns",
                body: "Insights shows history, stats, achievements, and what the assistant is learning locally.",
                pointingText: "Open Insights from the sidebar after a few sessions."
            )
        case .settings:
            return OnboardingCopy(
                icon: "gearshape",
                title: "Adjust support anytime",
                body: "Settings controls notifications, floating timer behavior, voice, shortcuts, privacy, and the saved API key.",
                pointingText: "Use the Guide button in the sidebar to replay this tour."
            )
        }
    }

}

private struct OnboardingCopy {
    let icon: String
    let title: String
    let body: String
    let pointingText: String
}

struct NavButton: View {
    @EnvironmentObject private var model: FocusFlowAppModel
    let title: String
    let systemImage: String
    let tab: FocusFlowAppModel.NavTab

    private var isActive: Bool { model.activeTab == tab }

    var body: some View {
        Button {
            model.selectTab(tab)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(isActive ? AppColor.actionPrimary.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(isActive ? AppColor.actionPrimary : AppColor.textPrimary)
        .accessibilityIdentifier("nav_\(title.lowercased())")
    }
}
