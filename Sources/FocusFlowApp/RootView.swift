import FocusFlowCore
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: FocusFlowAppModel

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(FFColors.canvas)
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                Circle()
                    .fill(model.remoteAgentStatus.contains("enabled") || model.remoteAgentStatus.contains("saved") ? FFColors.mint : FFColors.peach)
                    .frame(width: 8, height: 8)
                Text(model.remoteAgentStatus.contains("enabled") || model.remoteAgentStatus.contains("saved") ? "Remote agent ready" : "Local fallback ready")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FFColors.ink)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 8))
            .padding(18)
        }
        .overlay(alignment: .top) {
            if let achievement = model.pendingAchievements.first, model.settings.achievementsToastEnabled {
                HStack(spacing: 12) {
                    Image(systemName: achievement.iconName)
                        .foregroundStyle(FFColors.peach)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(achievement.title)
                            .font(.headline)
                            .foregroundStyle(FFColors.ink)
                        Text(achievement.message)
                            .font(.caption)
                            .foregroundStyle(FFColors.softGray)
                    }
                    Button("Save") {
                        model.dismissAchievement(achievement)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(14)
                .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
                .padding(.top, 18)
            }
        }
        .overlay(alignment: .bottom) {
            if let message = model.message {
                Text(message)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(FFColors.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
                    .padding(.bottom, 18)
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
                    .foregroundStyle(FFColors.ink)
                Text("Learning agent")
                    .font(.caption)
                    .foregroundStyle(FFColors.softGray)
            }
            .padding(.bottom, 12)

            NavButton(title: "Start", systemImage: "sparkle.magnifyingglass", route: .input)
            NavButton(title: "Current", systemImage: "timer", route: .execution)
            NavButton(title: "Personal", systemImage: "chart.line.uptrend.xyaxis", route: .personalCenter)
            NavButton(title: "Settings", systemImage: "gearshape", route: .settings)

            Spacer()
            Text("Local-first. No diagnosis. No shame loops.")
                .font(.caption)
                .foregroundStyle(FFColors.softGray)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(width: 210)
        .background(Color.white)
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
                .background(model.route == route ? FFColors.blue.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .foregroundStyle(model.route == route ? FFColors.blue : FFColors.ink)
        .accessibilityIdentifier("nav_\(title.lowercased())")
    }
}

enum FFColors {
    static let canvas = Color(red: 247 / 255, green: 244 / 255, blue: 237 / 255)
    static let blue = Color(red: 91 / 255, green: 124 / 255, blue: 250 / 255)
    static let mint = Color(red: 123 / 255, green: 201 / 255, blue: 154 / 255)
    static let peach = Color(red: 255 / 255, green: 184 / 255, blue: 107 / 255)
    static let ink = Color(red: 47 / 255, green: 52 / 255, blue: 64 / 255)
    static let softGray = Color(red: 138 / 255, green: 143 / 255, blue: 152 / 255)
    static let lavender = Color(red: 238 / 255, green: 233 / 255, blue: 255 / 255)
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(FFColors.blue.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(FFColors.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color.white.opacity(configuration.isPressed ? 0.70 : 0.95), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(FFColors.softGray)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(FFColors.ink)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
    }
}
