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
        case .input:
            TaskInputView()
        case .plan:
            PlanPreviewView()
        case .execution:
            ExecutionCenterView()
        case .closure:
            ClosureView()
        case .personalCenter:
            PersonalCenterView()
        case .settings:
            SettingsView()
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

            NavButton(title: "Start", systemImage: "sparkle.magnifyingglass", route: .input)
            NavButton(title: "Current", systemImage: "timer", route: .execution)
            NavButton(title: "Personal", systemImage: "chart.line.uptrend.xyaxis", route: .personalCenter)
            NavButton(title: "Settings", systemImage: "gearshape", route: .settings)

            Spacer()
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

struct NavButton: View {
    @EnvironmentObject private var model: FocusFlowAppModel
    let title: String
    let systemImage: String
    let route: FocusFlowAppModel.Route

    var body: some View {
        Button {
            model.route = route
            if route == .personalCenter {
                Task { await model.refreshStats() }
            }
        } label: {
            Label(title, systemImage: systemImage)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(model.route == route ? AppColor.actionPrimary.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .foregroundStyle(model.route == route ? AppColor.actionPrimary : AppColor.textPrimary)
        .accessibilityIdentifier("nav_\(title.lowercased())")
    }
}
