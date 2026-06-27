import FocusFlowCore
import SwiftUI

struct ExecutionCenterView: View {
    @EnvironmentObject private var model: FocusFlowAppModel
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

    private var isCollectingFeedback: Bool {
        !model.feedbackOptions.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let task = model.currentTask, let stage = currentStage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(task.title)
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(FFColors.ink)
                        Text("Stage \(stage.order) of \(task.stages.count)")
                            .font(.title3)
                            .foregroundStyle(FFColors.softGray)
                    }

                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 18) {
                            Text(stage.title)
                                .font(.title.weight(.bold))
                                .foregroundStyle(FFColors.ink)
                            Text(stage.instruction)
                                .font(.title3)
                                .foregroundStyle(FFColors.ink)
                            Text("Stop when: \(stage.completionCriteria)")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(FFColors.softGray)

                            TimerReadout(seconds: model.remainingSeconds ?? stage.estimatedSeconds)

                            if isCollectingFeedback {
                                HStack(spacing: 10) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundStyle(FFColors.mint)
                                    Text("Step saved. Answer the quick check-in below before moving on.")
                                        .font(.headline)
                                        .foregroundStyle(FFColors.ink)
                                }
                                .padding(14)
                                .background(FFColors.mint.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                            } else {
                                HStack {
                                    Button {
                                        if stage.status == .running || stage.status == .paused || stage.status == .overtime {
                                            model.pauseOrResume()
                                        } else {
                                            model.startNextStage()
                                        }
                                    } label: {
                                        Label(stage.status == .paused ? "Continue" : stage.status == .running ? "Pause" : "Start", systemImage: stage.status == .paused ? "play.fill" : "pause.fill")
                                    }
                                    .buttonStyle(SecondaryButtonStyle())
                                    .accessibilityIdentifier("stage_pause_resume_button")

                                    Button {
                                        model.completeStage()
                                    } label: {
                                        Label("I finished this step", systemImage: "checkmark.circle.fill")
                                    }
                                    .buttonStyle(PrimaryButtonStyle())
                                    .accessibilityIdentifier("stage_complete_button")

                                    Button {
                                        model.requestStuckHelp()
                                    } label: {
                                        Label("I'm stuck", systemImage: "lifepreserver")
                                    }
                                    .buttonStyle(SecondaryButtonStyle())
                                    .accessibilityIdentifier("stage_stuck_button")

                                    Button {
                                        model.extendCurrentStageByFiveMinutes()
                                    } label: {
                                        Label("+5 min", systemImage: "plus.circle")
                                    }
                                    .buttonStyle(SecondaryButtonStyle())
                                    .accessibilityIdentifier("extend_stage_button")
                                }
                            }

                            if !isCollectingFeedback {
                                HStack {
                                    Button("Skip for now") { model.skipStage() }
                                        .buttonStyle(SecondaryButtonStyle())
                                        .accessibilityIdentifier("stage_skip_button")
                                    Button("Pause task gently") { model.abandonTaskGracefully() }
                                        .buttonStyle(SecondaryButtonStyle())
                                        .accessibilityIdentifier("pause_task_gently_button")
                                    Button("Complete task now") { model.completeTaskNow() }
                                        .buttonStyle(SecondaryButtonStyle())
                                        .accessibilityIdentifier("complete_task_now_button")
                                    Button("End task") { model.abandonCurrentTask(reason: "You chose to end this task from the execution center.") }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(FFColors.softGray)
                                        .accessibilityIdentifier("end_task_button")
                                }
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))

                        FloatingCapsulePreview(stage: stage, seconds: model.remainingSeconds ?? stage.estimatedSeconds)
                            .frame(width: 250)
                    }

                    if let stuck = model.stuckHelp {
                        StuckHelpCard(response: stuck)
                    }

                    if let fallback = model.notificationFallbackMessage {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "bell.slash")
                                .foregroundStyle(FFColors.peach)
                            Text(fallback)
                                .font(.callout.weight(.medium))
                                .foregroundStyle(FFColors.ink)
                            Spacer()
                        }
                        .padding(16)
                        .background(FFColors.peach.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                    }

                    if model.interventionPanelVisible {
                        InterventionPanel()
                    }

                    if let breakRemaining = model.breakRemainingSeconds, breakRemaining > 0 {
                        HStack {
                            Image(systemName: "cup.and.saucer")
                                .foregroundStyle(FFColors.peach)
                            Text("Break")
                                .font(.headline)
                                .foregroundStyle(FFColors.ink)
                            Spacer()
                            Text(String(format: "%02d:%02d", breakRemaining / 60, breakRemaining % 60))
                                .font(.system(.title3, design: .rounded).weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(FFColors.blue)
                        }
                        .padding(18)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                    }

                    if !model.feedbackOptions.isEmpty {
                        FeedbackSheet(options: model.feedbackOptions)
                    }

                    if let pendingUpdate = model.pendingStageUpdate {
                        PlanAdjustmentPreviewCard(update: pendingUpdate)
                    }

                    if let postFeedbackMessage = model.postFeedbackMessage {
                        PostFeedbackCard(message: postFeedbackMessage)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
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
                        .foregroundStyle(FFColors.ink)
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
                                            .foregroundStyle(FFColors.ink)
                                        Text(item.estimatedSeconds.minutesText)
                                            .font(.caption)
                                            .foregroundStyle(FFColors.softGray)
                                    }
                                    Spacer()
                                    Text(item.status.rawValue)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(FFColors.softGray)
                                }
                                .padding(12)
                                .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                } else {
                    EmptyExecutionView()
                }
            }
            .padding(42)
        }
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
        case .completed: FFColors.mint
        case .running, .overtime: FFColors.blue
        case .paused: FFColors.peach
        default: FFColors.softGray
        }
    }
}

struct InterventionPanel: View {
    @EnvironmentObject private var model: FocusFlowAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("We can make this gentler")
                .font(.title2.weight(.bold))
                .foregroundStyle(FFColors.ink)
            Text(model.interventionReason)
                .font(.body)
                .foregroundStyle(FFColors.ink)
            HStack {
                Button("Save progress") {
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
                Button("Switch task") {
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
                .foregroundStyle(FFColors.softGray)
            }
        }
        .padding(20)
        .background(FFColors.lavender, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct TimerReadout: View {
    let seconds: Int

    var body: some View {
        let display = max(0, seconds)
        Text(String(format: "%02d:%02d", display / 60, display % 60))
            .font(.system(size: 72, weight: .bold, design: .rounded))
            .foregroundStyle(display <= 120 ? FFColors.peach : FFColors.blue)
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FloatingCapsulePreview: View {
    @EnvironmentObject private var model: FocusFlowAppModel
    let stage: StagePlan
    let seconds: Int

    var body: some View {
        VStack(spacing: 18) {
            Text("Floating timer")
                .font(.caption.weight(.bold))
                .foregroundStyle(FFColors.softGray)
            TimerReadout(seconds: seconds)
                .scaleEffect(0.56)
                .frame(height: 70)
            Button("I'm stuck") {
                model.requestStuckHelp()
            }
                .buttonStyle(SecondaryButtonStyle())
            Button("+5 min") {
                model.extendCurrentStageByFiveMinutes()
            }
                .buttonStyle(SecondaryButtonStyle())
            Button("Done") {
                model.completeStage()
            }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(20)
        .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(FFColors.blue.opacity(0.16)))
    }
}

struct FeedbackSheet: View {
    @EnvironmentObject private var model: FocusFlowAppModel
    let options: [FeedbackOption]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How did this step feel?")
                .font(.title2.weight(.bold))
                .foregroundStyle(FFColors.ink)
            HStack {
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
                    .accessibilityIdentifier("feedback_option_\(option.intent.rawValue)")
                }
            }
            HStack {
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
                .accessibilityIdentifier("feedback_voice_button")
                if !model.voiceTranscript.isEmpty {
                    Text(model.voiceTranscript)
                        .font(.callout)
                        .foregroundStyle(FFColors.softGray)
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
                .accessibilityIdentifier("submit_other_feedback_button")
            }
            Button("Skip feedback") {
                model.skipFeedbackAndContinue()
            }
            .buttonStyle(.plain)
            .foregroundStyle(FFColors.softGray)
            .accessibilityIdentifier("skip_feedback_button")
            Button("Stop here") {
                model.submitFeedback(FeedbackOption(label: "Stop here", emoji: "🌙", intent: .wantToQuit))
            }
            .buttonStyle(.plain)
            .foregroundStyle(FFColors.softGray)
            .accessibilityIdentifier("stop_here_feedback_button")
        }
        .padding(20)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
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
                    .foregroundStyle(FFColors.blue)
                    .frame(width: 36, height: 36)
                    .background(FFColors.blue.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 5) {
                    Text("Suggested plan adjustment")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(FFColors.ink)
                    Text(update.reason)
                        .font(.callout)
                        .foregroundStyle(FFColors.softGray)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            HStack(alignment: .top, spacing: 14) {
                StagePreviewColumn(
                    title: "Original",
                    tint: FFColors.softGray,
                    stages: originalStages
                )
                Image(systemName: "arrow.right")
                    .font(.headline)
                    .foregroundStyle(FFColors.softGray)
                    .padding(.top, 34)
                StagePreviewColumn(
                    title: "Suggested",
                    tint: FFColors.mint,
                    stages: proposedStages
                )
            }

            HStack {
                Button {
                    model.keepOriginalPlanAfterFeedback()
                } label: {
                    Label("Keep original", systemImage: "arrow.uturn.left")
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    model.applyPendingStageUpdate()
                } label: {
                    Label("Apply adjustment", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(20)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(FFColors.blue.opacity(0.14)))
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
                    .foregroundStyle(FFColors.softGray)
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
                    .background(FFColors.canvas.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
            } else {
                ForEach(stages) { stage in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stage.title)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(FFColors.ink)
                            .lineLimit(2)
                        Text(stage.estimatedSeconds.minutesText)
                            .font(.caption)
                            .foregroundStyle(FFColors.softGray)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
                    .background(FFColors.canvas.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
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
                .foregroundStyle(FFColors.blue)
                .frame(width: 36, height: 36)
                .background(FFColors.blue.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text("Feedback applied")
                    .font(.headline)
                    .foregroundStyle(FFColors.ink)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(FFColors.softGray)
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
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct StuckHelpCard: View {
    @EnvironmentObject private var model: FocusFlowAppModel
    let response: StuckHelpResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(response.comfortText)
                .font(.headline)
                .foregroundStyle(FFColors.ink)
            Text(response.nextSmallStep)
                .font(.title3.weight(.semibold))
                .foregroundStyle(FFColors.ink)
            HStack {
                ForEach(response.actions) { action in
                    Button(action.title) {
                        model.handleStuckAction(action)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .padding(20)
        .background(FFColors.lavender, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct EmptyExecutionView: View {
    @EnvironmentObject private var model: FocusFlowAppModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkles")
                .font(.system(size: 52))
                .foregroundStyle(FFColors.blue)
            Text("No active task yet")
                .font(.title.weight(.bold))
                .foregroundStyle(FFColors.ink)
            Text("Start with one messy learning task, and FocusFlow will make the first step clear.")
                .font(.title3)
                .foregroundStyle(FFColors.softGray)
            Button("Create a task") {
                model.route = .input
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(60)
    }
}
