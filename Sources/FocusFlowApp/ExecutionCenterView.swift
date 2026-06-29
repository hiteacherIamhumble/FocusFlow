import FocusFlowCore
import SwiftUI

struct ExecutionCenterView: View {
    @EnvironmentObject private var model: FocusFlowAppModel

    var body: some View {
        if model.currentTask == nil {
            EmptyExecutionView()
        } else {
            ExecutionCompanionView()
        }
    }
}

/// Full execution UI: stage card, controls, banners, overlays. Lives in the floating window.
struct ExecutionWorkspaceView: View {
    @EnvironmentObject private var model: FocusFlowAppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stageListExpanded = false

    private var currentStage: StagePlan? {
        if !model.feedbackOptions.isEmpty,
           let result = model.activeResult,
           let completedStage = model.currentTask?.stages.first(where: { $0.id == result.stageId }) {
            return completedStage
        }
        return model.currentTask?.stages.sorted(by: { $0.order < $1.order }).first {
            $0.status == .running || $0.status == .paused || $0.status == .overtime
        } ?? model.currentTask?.stages.sorted(by: { $0.order < $1.order }).first {
            $0.status == .idle || $0.status == .adjusted
        }
    }

    private var overlayActive: Bool {
        model.agentProcessingMessage != nil
            || model.interventionPanelVisible
            || !model.feedbackOptions.isEmpty
            || model.pendingStageUpdate != nil
            || model.postFeedbackMessage != nil
            || model.timeoutDifficultyPrompt != nil
            || model.stuckHelp != nil
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let task = model.currentTask, let stage = currentStage {
                        stageHeader(task: task, stage: stage)
                        focusCard(stage: stage)
                        ambientBanners
                        stageListSection(task: task)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .blur(radius: overlayActive ? 2 : 0)
            .disabled(overlayActive)

            if overlayActive {
                gentleOverlay
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: overlayActive)
    }
}

struct ExecutionCompanionView: View {
    @EnvironmentObject private var model: FocusFlowAppModel

    private var currentStage: StagePlan? {
        model.currentTask?.stages.sorted(by: { $0.order < $1.order }).first {
            $0.status == .running || $0.status == .paused || $0.status == .overtime
        } ?? model.currentTask?.stages.sorted(by: { $0.order < $1.order }).first {
            $0.status == .idle || $0.status == .adjusted
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 36))
                    .foregroundStyle(AppColor.actionPrimary)

                Text("Your focus session lives in the floating window")
                    .font(AppFont.pageTitle)
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Drag it anywhere while you work in other apps. Stuck help, feedback, and timers all stay there.")
                    .font(.title3)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let task = model.currentTask, let stage = currentStage {
                    Text("\(task.title) · Stage \(stage.order) of \(task.stages.count)")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                }

                Button {
                    model.bringFloatingWindowToFront()
                } label: {
                    Label("Bring floating window to front", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: 320)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("bring_floating_window_button")
            }
            .padding(32)
            .frame(maxWidth: 560, alignment: .leading)
            .background(AppColor.surfaceCard, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColor.borderSubtle.opacity(0.6)))

            Spacer(minLength: 0)
        }
        .padding(42)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private extension ExecutionWorkspaceView {

    private func stageHeader(task: TaskPlan, stage: StagePlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task.title)
                .font(AppFont.pageTitle)
                .foregroundStyle(AppColor.textPrimary)
            Text("Stage \(stage.order) of \(task.stages.count)")
                .font(.title3)
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    private func focusCard(stage: StagePlan) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(stage.title)
                .font(.title.weight(.bold))
                .foregroundStyle(AppColor.textPrimary)
            Text(stage.instruction)
                .font(.title3)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Stop when: \(stage.completionCriteria)")
                .font(.callout.weight(.medium))
                .foregroundStyle(AppColor.textSecondary)

            TimerReadout(seconds: model.remainingSeconds ?? stage.estimatedSeconds)

            primaryAction(stage: stage)
            secondaryActionRow(stage: stage)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.surfaceCard, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColor.borderSubtle.opacity(0.6)))
    }

    @ViewBuilder
    private func primaryAction(stage: StagePlan) -> some View {
        let isRunning = stage.status == .running || stage.status == .paused || stage.status == .overtime
        if isRunning {
            Button {
                model.completeStage()
            } label: {
                Label("I finished this step", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.isWorking)
            .accessibilityIdentifier("stage_complete_button")
        } else {
            Button {
                model.startNextStage()
            } label: {
                Label("Start this step", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.isWorking)
            .accessibilityIdentifier("stage_start_button")
        }
    }

    @ViewBuilder
    private func secondaryActionRow(stage: StagePlan) -> some View {
        let isRunning = stage.status == .running || stage.status == .paused || stage.status == .overtime
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if isRunning {
                    executionControlButton(
                        title: stage.status == .paused ? "Resume timer" : "Pause timer",
                        systemImage: stage.status == .paused ? "play.fill" : "pause.fill",
                        accessibilityIdentifier: "stage_pause_resume_button"
                    ) {
                        model.pauseOrResume()
                    }
                }

                executionControlButton(
                    title: "+5",
                    systemImage: "plus.circle",
                    accessibilityIdentifier: "extend_stage_button"
                ) {
                    model.extendCurrentStageByFiveMinutes()
                }

                executionControlButton(
                    title: "Stuck",
                    systemImage: "lifepreserver",
                    accessibilityIdentifier: "stage_stuck_button"
                ) {
                    model.requestStuckHelp()
                }

                executionControlButton(
                    title: "Skip",
                    systemImage: "forward",
                    accessibilityIdentifier: "stage_skip_button"
                ) {
                    model.skipStage()
                }

                Menu {
                    Button("Save for later") {
                        model.saveCurrentTaskForLater()
                    }
                    .accessibilityIdentifier("save_task_for_later_button")
                    Button("Switch to new task") {
                        model.saveCurrentTaskForLater(openNewTask: true)
                    }
                    .accessibilityIdentifier("switch_to_new_task_button")
                    Button("Complete task now") { model.completeTaskNow() }
                        .accessibilityIdentifier("complete_task_now_button")
                    Button("End task", role: .destructive) {
                        model.abandonCurrentTask(reason: "You chose to end this task from the execution center.")
                    }
                    .accessibilityIdentifier("end_task_button")
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                        .labelStyle(.titleAndIcon)
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(CompactSecondaryButtonStyle())
                .disabled(model.isWorking)
                .fixedSize()
                .accessibilityIdentifier("execution_more_menu")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func executionControlButton(
        title: String,
        systemImage: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .buttonStyle(CompactSecondaryButtonStyle())
        .disabled(model.isWorking)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder
    private var ambientBanners: some View {
        if let fallback = model.notificationFallbackMessage {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bell.slash")
                    .foregroundStyle(AppColor.warning)
                Text(fallback)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
            }
            .padding(16)
            .background(AppColor.warning.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
        }

        if let breakRemaining = model.breakRemainingSeconds, breakRemaining > 0 {
            HStack {
                Image(systemName: "cup.and.saucer")
                    .foregroundStyle(AppColor.warning)
                Text("Break")
                    .font(.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                Text(String(format: "%02d:%02d", breakRemaining / 60, breakRemaining % 60))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(AppColor.actionPrimary)
            }
            .padding(18)
            .background(AppColor.surfaceCard, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func stageListSection(task: TaskPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                    stageListExpanded.toggle()
                }
            } label: {
                HStack {
                    Label("Stage list", systemImage: stageListExpanded ? "chevron.down.circle" : "chevron.right.circle")
                        .font(.headline)
                    Spacer()
                    Text("\(task.stages.count) stages")
                        .font(.caption.weight(.semibold))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppColor.textPrimary)
            .accessibilityIdentifier("toggle_stage_list_button")

            if stageListExpanded {
                ForEach(task.stages.sorted(by: { $0.order < $1.order })) { item in
                    HStack {
                        Image(systemName: icon(for: item.status))
                            .foregroundStyle(color(for: item.status))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(AppColor.textPrimary)
                            Text(item.estimatedSeconds.minutesText)
                                .font(.caption)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                        Spacer()
                        Text(item.status.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    .padding(12)
                    .background(AppColor.surfaceCard.opacity(0.82), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    @ViewBuilder
    private var gentleOverlay: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { /* modal scrim: ignore taps */ }

            ScrollView {
                Group {
                    if let agentMessage = model.agentProcessingMessage {
                        AgentProcessingCard(message: agentMessage)
                    } else if model.interventionPanelVisible {
                        InterventionPanel()
                    } else if !model.feedbackOptions.isEmpty {
                        FeedbackSheet(options: model.feedbackOptions)
                    } else if let pendingUpdate = model.pendingStageUpdate {
                        PlanAdjustmentPreviewCard(update: pendingUpdate)
                    } else if let timeoutPrompt = model.timeoutDifficultyPrompt {
                        TimeoutDifficultyCard(prompt: timeoutPrompt)
                    } else if let postFeedbackMessage = model.postFeedbackMessage {
                        PostFeedbackCard(message: postFeedbackMessage)
                    } else if let stuck = model.stuckHelp {
                        StuckHelpCard(response: stuck)
                    }
                }
                .frame(maxWidth: 560)
                .shadow(color: .black.opacity(0.18), radius: 26, y: 12)
                .padding(40)
                .frame(maxWidth: .infinity)
            }
        }
        .transition(.opacity)
    }

    private func icon(for status: StageStatus) -> String {
        switch status {
        case .completed: "checkmark.circle.fill"
        case .running, .overtime: "timer.circle.fill"
        case .paused: "pause.circle.fill"
        case .skipped: "forward.circle.fill"
        case .abandoned: "moon.circle.fill"
        case .adjusted: "slider.horizontal.3"
        case .idle: "circle"
        }
    }

    private func color(for status: StageStatus) -> Color {
        switch status {
        case .completed: AppColor.success
        case .running, .overtime: AppColor.actionPrimary
        case .paused: AppColor.warning
        default: AppColor.textSecondary
        }
    }
}

struct InterventionPanel: View {
    @EnvironmentObject private var model: FocusFlowAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("We can make this gentler")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppColor.textPrimary)
            Text(model.interventionReason)
                .font(.body)
                .foregroundStyle(AppColor.textPrimary)
            AdaptiveButtonRow {
                Button("Save for later") {
                    model.saveProgressFromIntervention()
                }
                .buttonStyle(SecondaryButtonStyle())
                Button("Split smaller") {
                    model.splitActiveStageSmaller()
                }
                .buttonStyle(SecondaryButtonStyle())
                Button("Rest 10 min") {
                    model.takeTenMinuteRest()
                }
                .buttonStyle(SecondaryButtonStyle())
                Button("Switch to new task") {
                    model.switchTaskFromIntervention()
                }
                .buttonStyle(SecondaryButtonStyle())
                Button("End task") {
                    model.abandonCurrentTask(reason: "You chose to stop from the intervention panel.")
                }
                .buttonStyle(SecondaryButtonStyle())
                Button("Close") {
                    model.interventionPanelVisible = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColor.textSecondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.calmLavender, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColor.focusRing.opacity(0.18)))
    }
}

struct TimerReadout: View {
    let seconds: Int

    var body: some View {
        let display = max(0, seconds)
        Text(String(format: "%02d:%02d", display / 60, display % 60))
            .font(.system(.largeTitle, design: .rounded).weight(.bold))
            .foregroundStyle(display <= 120 ? AppColor.warning : AppColor.actionPrimary)
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .leading)
            .minimumScaleFactor(0.75)
            .accessibilityLabel("\(display / 60) minutes \(display % 60) seconds remaining")
    }
}

struct AgentProcessingCard: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ProgressView()
                .controlSize(.regular)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 6) {
                Text("AI is thinking")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppColor.textPrimary)
                Text("\(message) Controls are paused to prevent duplicate actions.")
                    .font(.callout)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.surfaceCard, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColor.borderSubtle.opacity(0.6)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AI is thinking. \(message) Controls are paused to prevent duplicate actions.")
    }
}

struct FeedbackSheet: View {
    @EnvironmentObject private var model: FocusFlowAppModel
    let options: [FeedbackOption]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How did this step feel?")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppColor.textPrimary)
            AdaptiveButtonRow {
                ForEach(options) { option in
                    Button {
                        model.submitFeedback(option)
                    } label: {
                        VStack(spacing: 8) {
                            Text(option.emoji ?? "")
                                .font(.largeTitle)
                            Text(option.label)
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("feedback_option_\(option.intent.rawValue)")
                    .accessibilityLabel(option.label)
                    .accessibilityHint("Submits feedback for this completed step.")
                }
            }
            AdaptiveButtonRow {
                Button {
                    if model.isListeningForVoice {
                        model.stopVoiceInput()
                    } else {
                        model.beginVoiceInput()
                    }
                } label: {
                    Label(model.isListeningForVoice ? "Stop voice" : "Voice note", systemImage: "waveform")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(model.isWorking)
                .accessibilityIdentifier("feedback_voice_button")
                if !model.voiceTranscript.isEmpty {
                    Text(model.voiceTranscript)
                        .font(.callout)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(2)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                TextField("Other situation", text: $model.feedbackOtherText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .accessibilityIdentifier("other_feedback_text")
                Button {
                    model.submitOtherFeedback()
                } label: {
                    Label("Submit other", systemImage: "square.and.pencil")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(model.isWorking)
                .accessibilityIdentifier("submit_other_feedback_button")
            }
            Button("Skip feedback") {
                model.skipFeedbackAndContinue()
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppColor.textSecondary)
            .disabled(model.isWorking)
            .accessibilityIdentifier("skip_feedback_button")
            Button("Stop here") {
                model.submitFeedback(FeedbackOption(label: "Stop here", emoji: "🌙", intent: .wantToQuit))
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppColor.textSecondary)
            .disabled(model.isWorking)
            .accessibilityIdentifier("stop_here_feedback_button")
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.surfaceCard, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColor.borderSubtle.opacity(0.6)))
        .accessibilityElement(children: .contain)
    }
}

struct PlanAdjustmentPreviewCard: View {
    @EnvironmentObject private var model: FocusFlowAppModel
    let update: StageUpdate

    private var originalStages: [StagePlan] {
        model.originalStages(for: update)
    }

    private var proposedStages: [StagePlan] {
        model.proposedStages(for: update)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.title2)
                    .foregroundStyle(AppColor.actionPrimary)
                    .frame(width: 36, height: 36)
                    .background(AppColor.actionPrimary.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 5) {
                    Text("Suggested plan adjustment")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppColor.textPrimary)
                    Text(update.reason)
                        .font(.callout)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            HStack(alignment: .top, spacing: 14) {
                StagePreviewColumn(
                    title: "Original",
                    tint: AppColor.textSecondary,
                    stages: originalStages
                )
                Image(systemName: "arrow.right")
                    .font(.headline)
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.top, 34)
                StagePreviewColumn(
                    title: "Suggested",
                    tint: AppColor.success,
                    stages: proposedStages
                )
            }

            AdaptiveButtonRow {
                Button {
                    model.keepOriginalPlanAfterFeedback()
                } label: {
                    Label("Keep original", systemImage: "arrow.uturn.left")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(model.isWorking)

                Button {
                    model.applyPendingStageUpdate()
                } label: {
                    Label("Apply adjustment", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.isWorking)
            }
        }
        .padding(20)
        .background(AppColor.surfaceCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColor.actionPrimary.opacity(0.14)))
    }
}

struct StagePreviewColumn: View {
    let title: String
    let tint: Color
    let stages: [StagePlan]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
            if stages.isEmpty {
                Text("No remaining step will change.")
                    .font(.callout)
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
                    .background(AppColor.bgBase.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
            } else {
                ForEach(stages) { stage in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stage.title)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(AppColor.textPrimary)
                            .lineLimit(2)
                        Text(stage.estimatedSeconds.minutesText)
                            .font(.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
                    .background(AppColor.bgBase.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct PostFeedbackCard: View {
    @EnvironmentObject private var model: FocusFlowAppModel
    let message: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(AppColor.actionPrimary)
                .frame(width: 36, height: 36)
                .background(AppColor.actionPrimary.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text("Feedback applied")
                    .font(.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if model.canUndoLastStageUpdate {
                Button {
                    model.undoLastStageUpdate()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.left")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            Button {
                model.continueAfterFeedback()
            } label: {
                Label(model.readyToContinueAfterFeedback ? "Start next step" : "View summary", systemImage: model.readyToContinueAfterFeedback ? "arrow.right.circle.fill" : "checkmark.seal.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(20)
        .background(AppColor.surfaceCard, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct TimeoutDifficultyCard: View {
    @EnvironmentObject private var model: FocusFlowAppModel
    let prompt: DifficultyPrompt

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Time's up on this step")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppColor.textPrimary)
            Text(prompt.promptText)
                .font(.body)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            AdaptiveButtonRow {
                ForEach(prompt.options) { option in
                    Button {
                        model.respondToTimeoutDifficulty(option)
                    } label: {
                        VStack(spacing: 8) {
                            Text(option.emoji ?? "")
                                .font(.title2)
                            Text(option.label)
                                .font(.headline)
                        }
                        .frame(minWidth: 96)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(model.isWorking)
                }
            }

            Button("Close for now") {
                model.dismissTimeoutDifficultyPrompt()
            }
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(AppColor.textSecondary)
            .disabled(model.isWorking)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.actionContainer, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColor.borderSubtle, lineWidth: 1))
    }
}

struct StuckHelpCard: View {
    @EnvironmentObject private var model: FocusFlowAppModel
    let response: StuckHelpResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            firstMove
            if !model.stuckHintEntries.isEmpty {
                entriesList
            }
            if model.stuckHintLoading {
                loadingRow
            }
            actionButtons
            if model.stuckEscalationVisible {
                escalationRow
            }
            Button("Close for now") {
                model.dismissStuckHelp()
            }
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(AppColor.textSecondary)
            .disabled(model.isWorking)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.actionContainer, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColor.borderSubtle, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(response.comfortText)
                .font(.headline)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let stageTitle = model.activeStageTitle {
                Text("You're on: \(stageTitle)")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var firstMove: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Smallest next move", systemImage: "arrow.turn.down.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColor.actionPrimary)
            Text(response.nextSmallStep)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.calmLavender, in: RoundedRectangle(cornerRadius: 10))
    }

    private var entriesList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(model.stuckHintEntries) { entry in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: entry.symbol)
                        .font(.callout)
                        .foregroundStyle(AppColor.actionPrimary)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColor.textSecondary)
                        Text(entry.text)
                            .font(.body)
                            .foregroundStyle(AppColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.bgBase, in: RoundedRectangle(cornerRadius: 10))
    }

    private var loadingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Finding a gentle next step…")
                .font(.callout)
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    private var actionButtons: some View {
        AdaptiveButtonRow {
            ForEach(uniqueActions) { action in
                Button(actionTitle(for: action)) {
                    model.handleStuckAction(action)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isDisabled(action))
            }
        }
    }

    private var uniqueActions: [StuckHelpAction] {
        var seen = Set<StuckActionType>()
        return response.actions.filter { seen.insert($0.actionType).inserted }
    }

    private var escalationRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Still hard after a few tries? That's okay.")
                .font(.callout)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try another way") {
                model.escalateStuckHelp()
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(model.isWorking)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.calmLavender, in: RoundedRectangle(cornerRadius: 10))
    }

    private func actionTitle(for action: StuckHelpAction) -> String {
        switch action.actionType {
        case .hint:
            if !model.canDeepenHint { return "More help" }
            return model.stuckHintEntries.contains(where: { $0.kind == .hint }) ? "Deeper hint" : "Get a hint"
        case .example:
            return "See an example"
        case .splitSmaller:
            return "Split smaller"
        case .shortBreak:
            return "Short break"
        }
    }

    private func isDisabled(_ action: StuckHelpAction) -> Bool {
        if model.isWorking { return true }
        if model.stuckHintLoading { return true }
        if action.actionType == .hint, !model.canDeepenHint { return true }
        return false
    }
}

struct EmptyExecutionView: View {
    @EnvironmentObject private var model: FocusFlowAppModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(AppColor.actionPrimary)
            Text("No active task yet")
                .font(.title.weight(.bold))
                .foregroundStyle(AppColor.textPrimary)
            Text("Start with one messy learning task, and FocusFlow will make the first step clear.")
                .font(.title3)
                .foregroundStyle(AppColor.textSecondary)
            Button("Create a task") {
                model.beginNewTask()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(60)
    }
}
