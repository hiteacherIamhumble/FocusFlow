import FocusFlowCore
import SwiftUI

struct FlowStepIndicator: View {
    let currentRoute: FocusFlowAppModel.Route
    var onStepTap: (FocusFlowAppModel.Route) -> Void

    private struct Step: Identifiable {
        let id: Int
        let label: String
        let route: FocusFlowAppModel.Route
    }

    private let steps: [Step] = [
        Step(id: 1, label: "Say it", route: .input),
        Step(id: 2, label: "Confirm", route: .plan),
        Step(id: 3, label: "Focus", route: .execution),
        Step(id: 4, label: "Wrap up", route: .closure)
    ]

    private var currentIndex: Int {
        steps.firstIndex(where: { $0.route == currentRoute }) ?? 0
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                stepPill(step, index: index)
                if index < steps.count - 1 {
                    Rectangle()
                        .fill(index < currentIndex ? AppColor.actionPrimary.opacity(0.5) : AppColor.borderSubtle)
                        .frame(height: 2)
                        .frame(maxWidth: 36)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 42)
        .padding(.vertical, 14)
        .background(AppColor.bgBase)
    }

    @ViewBuilder
    private func stepPill(_ step: Step, index: Int) -> some View {
        let isCurrent = index == currentIndex
        let isDone = index < currentIndex
        let canTap = isDone && currentRoute == .plan && step.route == .input

        Button {
            if canTap { onStepTap(step.route) }
        } label: {
            HStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(isCurrent ? AppColor.actionPrimary : (isDone ? AppColor.success : AppColor.surfaceSubtle))
                        .frame(width: 22, height: 22)
                    if isDone {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppColor.actionOnPrimary)
                    } else {
                        Text("\(step.id)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(isCurrent ? AppColor.actionOnPrimary : AppColor.textSecondary)
                    }
                }
                Text(step.label)
                    .font(.caption.weight(isCurrent ? .bold : .medium))
                    .foregroundStyle(isCurrent ? AppColor.textPrimary : AppColor.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(!canTap)
        .accessibilityLabel("Step \(step.id): \(step.label)\(isCurrent ? ", current" : isDone ? ", done" : "")")
    }
}
