import FocusFlowCore
import SwiftUI

struct PlanPreviewView: View {
    @EnvironmentObject private var model: FocusFlowAppModel
    @State private var editingStageId: String?
    @State private var editTitle = ""
    @State private var editInstruction = ""
    @State private var editCriteria = ""
    @State private var editType: StageType = .other
    @State private var editMinutes = 5
    @State private var revisionPrompt = ""
    @State private var insertingBeforeStageId: String?
    @State private var insertTitle = ""
    @State private var insertInstruction = ""
    @State private var insertCriteria = ""
    @State private var insertType: StageType = .other
    @State private var insertMinutes = 5
    @State private var pendingDeleteStageId: String?

    private static let endInsertionScope = "__insert_end__"

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let task = model.currentTask {
                        planHeader(task)

                        if let agentMessage = model.agentProcessingMessage {
                            AgentPlanningStatusCard(text: agentMessage, isProcessing: true)
                        } else if let response = task.metadata["agent_response"], !response.isEmpty {
                            AgentPlanningStatusCard(text: response)
                        }

                        stageList(task)

                        if task.stages.count > 15 {
                            Label("This plan has more than 15 stages. Consider reducing steps before starting.", systemImage: "exclamationmark.triangle.fill")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(AppColor.warning)
                        }
                    } else {
                        Text("No plan yet.")
                    }
                }
                .padding(42)
                .padding(.bottom, 210)
            }

            if model.currentTask != nil {
                PlanAIRevisionPanel(
                    prompt: $revisionPrompt,
                    isWorking: model.isWorking,
                    isAgentWorking: model.agentProcessingMessage != nil,
                    onQuickPrompt: { prompt in
                        revisionPrompt = prompt
                    },
                    onSubmit: submitAIRevision
                )
                .padding(.horizontal, 42)
                .padding(.bottom, 18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func planHeader(_ task: TaskPlan) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(task.title)
                    .font(AppFont.pageTitle)
                    .foregroundStyle(AppColor.textPrimary)
                Text("\(task.taskType.readableName) · \(task.stages.count) stages · about \(task.estimatedTotalSeconds.minutesText)")
                    .font(.title3)
                    .foregroundStyle(AppColor.textSecondary)
                PlanningModeBadge(task: task)
            }
            Spacer(minLength: 16)
            Button {
                model.confirmAndStart()
            } label: {
                Label("Start the first step", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.isWorking)
            .accessibilityIdentifier("start_first_step_button")
        }
    }

    private func stageList(_ task: TaskPlan) -> some View {
        VStack(spacing: 10) {
            ForEach(task.stages.sorted(by: { $0.order < $1.order })) { stage in
                InsertStageDivider(label: "Add before step \(stage.order)") {
                    startInserting(before: stage)
                }
                if insertingBeforeStageId == stage.id {
                    StageEditor(
                        title: $insertTitle,
                        instruction: $insertInstruction,
                        criteria: $insertCriteria,
                        stageType: $insertType,
                        minutes: $insertMinutes,
                        isFirstStage: stage.order == 1,
                        onSave: {
                            model.insertStage(before: stage, patch: StagePlanPatch(
                                title: insertTitle,
                                instruction: insertInstruction,
                                completionCriteria: insertCriteria,
                                stageType: insertType,
                                estimatedSeconds: insertMinutes * 60
                            ))
                            resetInsertion()
                        },
                        onCancel: resetInsertion
                    )
                }

                StageRow(
                    stage: stage,
                    isEditing: editingStageId == stage.id,
                    canDelete: task.stages.count > 1,
                    onEdit: {
                        startEditing(stage)
                    },
                    onDelete: {
                        pendingDeleteStageId = stage.id
                    }
                )
                if pendingDeleteStageId == stage.id {
                    DeleteStageConfirmation(stage: stage) {
                        model.deleteStage(stage)
                        pendingDeleteStageId = nil
                        if editingStageId == stage.id {
                            editingStageId = nil
                        }
                    } onCancel: {
                        pendingDeleteStageId = nil
                    }
                }
                if editingStageId == stage.id {
                    StageEditor(
                        title: $editTitle,
                        instruction: $editInstruction,
                        criteria: $editCriteria,
                        stageType: $editType,
                        minutes: $editMinutes,
                        isFirstStage: stage.order == 1,
                        onSave: {
                            model.updateStage(stage, patch: StagePlanPatch(
                                title: editTitle,
                                instruction: editInstruction,
                                completionCriteria: editCriteria,
                                stageType: editType,
                                estimatedSeconds: editMinutes * 60
                            ))
                            editingStageId = nil
                        },
                        onCancel: {
                            editingStageId = nil
                        }
                    )
                }
            }
            InsertStageDivider(label: "Add stage at end") {
                startInserting(before: nil)
            }
            if insertingBeforeStageId == Self.endInsertionScope {
                StageEditor(
                    title: $insertTitle,
                    instruction: $insertInstruction,
                    criteria: $insertCriteria,
                    stageType: $insertType,
                    minutes: $insertMinutes,
                    isFirstStage: task.stages.isEmpty,
                    onSave: {
                        model.insertStage(before: nil, patch: StagePlanPatch(
                            title: insertTitle,
                            instruction: insertInstruction,
                            completionCriteria: insertCriteria,
                            stageType: insertType,
                            estimatedSeconds: insertMinutes * 60
                        ))
                        resetInsertion()
                    },
                    onCancel: resetInsertion
                )
            }
        }
    }

    private func startEditing(_ stage: StagePlan) {
        editingStageId = stage.id
        editTitle = stage.title
        editInstruction = stage.instruction
        editCriteria = stage.completionCriteria
        editType = stage.stageType
        editMinutes = max(stage.order == 1 ? 2 : 1, min(25, Int((Double(stage.estimatedSeconds) / 60.0).rounded())))
    }

    private func startInserting(before stage: StagePlan?) {
        insertingBeforeStageId = stage?.id ?? Self.endInsertionScope
        insertTitle = ""
        insertInstruction = ""
        insertCriteria = ""
        insertType = stage?.stageType ?? .other
        insertMinutes = stage?.order == 1 ? 2 : 5
        editingStageId = nil
    }

    private func resetInsertion() {
        insertingBeforeStageId = nil
        insertTitle = ""
        insertInstruction = ""
        insertCriteria = ""
        insertType = .other
        insertMinutes = 5
    }

    private func submitAIRevision() {
        let prompt = revisionPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !model.isWorking else { return }
        model.refinePlan(prompt)
        revisionPrompt = ""
    }
}

struct PlanningModeBadge: View {
    let task: TaskPlan

    private var isDeepSeek: Bool {
        task.metadata["planning_mode"] == "deepseek_v4_flash"
    }

    private var label: String {
        isDeepSeek ? "Planned by DeepSeek v4 flash" : "Planned by local fallback"
    }

    private var icon: String {
        isDeepSeek ? "sparkles" : "desktopcomputer"
    }

    var body: some View {
        Label(label, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(isDeepSeek ? AppColor.success : AppColor.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isDeepSeek ? AppColor.success.opacity(0.14) : AppColor.surfaceSubtle, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColor.borderSubtle.opacity(0.65)))
            .accessibilityLabel(label)
    }
}

struct AgentPlanningStatusCard: View {
    let text: String
    var isProcessing = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if isProcessing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "sparkles")
                        .foregroundStyle(AppColor.actionPrimary)
                }
            }
            .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(isProcessing ? "AI is thinking" : "Agent response")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppColor.textSecondary)
                Text(text)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(AppColor.surfaceCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColor.borderSubtle.opacity(0.65)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isProcessing ? "AI is thinking" : "Agent response"). \(text)")
    }
}

struct PlanAIRevisionPanel: View {
    @Binding var prompt: String
    let isWorking: Bool
    let isAgentWorking: Bool
    let onQuickPrompt: (String) -> Void
    let onSubmit: () -> Void

    private let quickPrompts: [(String, String, String)] = [
        ("Split smaller", "square.split.2x1", "Split the plan into smaller, more concrete steps."),
        ("Reduce steps", "minus.circle", "Reduce the plan to the fewest useful steps while keeping a tiny first step."),
        ("Add time", "clock.badge.plus", "Add a little more time to the work steps without making the plan feel heavier."),
        ("Regenerate", "arrow.clockwise", "Regenerate the whole plan with a fresh structure.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppColor.actionPrimary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Ask AI to revise the plan")
                        .font(.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Tell the agent what to change. Manual stage edits above save directly.")
                        .font(.callout)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    revisionField
                    submitButton
                }
                VStack(alignment: .leading, spacing: 10) {
                    revisionField
                    submitButton
                }
            }

            AdaptiveButtonRow {
                ForEach(quickPrompts, id: \.0) { title, icon, value in
                    Button {
                        onQuickPrompt(value)
                    } label: {
                        Label(title, systemImage: icon)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(isWorking)
                    .accessibilityIdentifier("\(title.lowercased().replacingOccurrences(of: " ", with: "_"))_prompt_button")
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.surfaceCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColor.borderSubtle.opacity(0.75)))
        .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
    }

    private var revisionField: some View {
        TextField("Tell AI what to change", text: $prompt, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(2...4)
            .frame(minWidth: 300)
            .frame(maxWidth: .infinity)
            .submitLabel(.send)
            .onSubmit {
                onSubmit()
            }
            .accessibilityIdentifier("plan_ai_revision_input")
    }

    private var submitButton: some View {
        Button {
            onSubmit()
        } label: {
            Label(isAgentWorking ? "AI is revising..." : "Ask AI", systemImage: "paperplane.fill")
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(isWorking || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityIdentifier("submit_plan_ai_revision_button")
    }
}

struct InsertStageDivider: View {
    let label: String
    let onInsert: () -> Void

    var body: some View {
        Button {
            onInsert()
        } label: {
            HStack(spacing: 10) {
                Rectangle()
                    .fill(AppColor.borderSubtle.opacity(0.72))
                    .frame(height: 1)
                Label(label, systemImage: "plus.circle")
                    .font(.caption.weight(.semibold))
                Rectangle()
                    .fill(AppColor.borderSubtle.opacity(0.72))
                    .frame(height: 1)
            }
            .foregroundStyle(AppColor.actionPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct DeleteStageConfirmation: View {
    let stage: StagePlan
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        AdaptiveButtonRow {
            Label("Delete step \(stage.order)?", systemImage: "exclamationmark.triangle")
                .font(.callout.weight(.semibold))
                .foregroundStyle(AppColor.warning)
            Button("Delete") {
                onConfirm()
            }
            .buttonStyle(SecondaryButtonStyle())
            Button("Cancel") {
                onCancel()
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppColor.textSecondary)
        }
        .padding(14)
        .background(AppColor.warning.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct StageRow: View {
    let stage: StagePlan
    let isEditing: Bool
    let canDelete: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(stage.order)")
                .font(.headline.weight(.bold))
                .foregroundStyle(AppColor.actionOnPrimary)
                .frame(width: 32, height: 32)
                .background(AppColor.actionPrimary, in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(stage.title)
                        .font(.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    Text(stage.estimatedSeconds.minutesText)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(AppColor.actionPrimary)
                    Button {
                        onEdit()
                    } label: {
                        Label(isEditing ? "Editing" : "Edit", systemImage: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("edit_stage_\(stage.order)_button")
                    Button {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(canDelete ? AppColor.warning : AppColor.textSecondary)
                    .disabled(!canDelete)
                    .accessibilityIdentifier("delete_stage_\(stage.order)_button")
                }
                Text(stage.instruction)
                    .font(.callout)
                    .foregroundStyle(AppColor.textPrimary)
                Text(stage.completionCriteria)
                    .font(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .padding(16)
        .background(AppColor.surfaceCard, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct StageEditor: View {
    @Binding var title: String
    @Binding var instruction: String
    @Binding var criteria: String
    @Binding var stageType: StageType
    @Binding var minutes: Int
    let isFirstStage: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Stage title", text: $title)
                .textFieldStyle(.roundedBorder)
            TextField("Instruction", text: $instruction, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
            TextField("Completion criteria", text: $criteria, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...3)
            ViewThatFits(in: .horizontal) {
                HStack {
                    Picker("Type", selection: $stageType) {
                        ForEach(StageType.allCases, id: \.self) { type in
                            Text(type.readableName).tag(type)
                        }
                    }
                    Stepper("Minutes: \(minutes)", value: $minutes, in: (isFirstStage ? 2 : 1)...25)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Type", selection: $stageType) {
                        ForEach(StageType.allCases, id: \.self) { type in
                            Text(type.readableName).tag(type)
                        }
                    }
                    Stepper("Minutes: \(minutes)", value: $minutes, in: (isFirstStage ? 2 : 1)...25)
                }
            }
            AdaptiveButtonRow {
                Button("Save stage") {
                    onSave()
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("save_stage_edit_button")
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(16)
        .background(AppColor.actionContainer, in: RoundedRectangle(cornerRadius: 8))
    }
}

extension EducationTaskType {
    var readableName: String {
        switch self {
        case .writing: "Writing"
        case .reading: "Reading"
        case .examReview: "Exam review"
        case .homework: "Homework"
        case .presentation: "Presentation"
        case .longTermProject: "Long-term project"
        case .unknown: "Learning"
        }
    }
}

extension StageType {
    var readableName: String {
        switch self {
        case .startup: "Startup"
        case .reading: "Reading"
        case .writing: "Writing"
        case .reviewing: "Reviewing"
        case .problemSolving: "Problem solving"
        case .organizing: "Organizing"
        case .presentationMaking: "Slides"
        case .breakTime: "Break"
        case .other: "Other"
        }
    }
}
