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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let task = model.currentTask {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(task.title)
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(FFColors.ink)
                        Text("\(task.taskType.readableName) · \(task.stages.count) stages · about \(task.estimatedTotalSeconds.minutesText)")
                            .font(.title3)
                            .foregroundStyle(FFColors.softGray)
                    }

                    if let first = task.stages.first {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("First tiny step")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(FFColors.blue)
                            Text(first.title)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(FFColors.ink)
                            Text(first.instruction)
                                .font(.body)
                                .foregroundStyle(FFColors.ink)
                            Text("Stop when: \(first.completionCriteria)")
                                .font(.callout)
                                .foregroundStyle(FFColors.softGray)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(FFColors.lavender, in: RoundedRectangle(cornerRadius: 8))
                    }

                    VStack(spacing: 10) {
                        ForEach(task.stages) { stage in
                            StageRow(stage: stage, isEditing: editingStageId == stage.id) {
                                startEditing(stage)
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
                    }
                    if task.stages.count > 15 {
                        Label("This plan has more than 15 stages. Consider reducing steps before starting.", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(FFColors.peach)
                    }

                    HStack {
                        Button {
                            model.confirmAndStart()
                        } label: {
                            Label("Start the first step", systemImage: "play.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("start_first_step_button")

                        Button("Split smaller") {
                            model.refinePlan("split smaller")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("split_smaller_button")

                        Button("Reduce steps") {
                            model.refinePlan("reduce steps")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("reduce_steps_button")

                        Button("Add time") {
                            model.refinePlan("more time")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("add_time_button")

                        Button {
                            model.regeneratePlan()
                        } label: {
                            Label("Regenerate", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("regenerate_plan_button")
                    }
                } else {
                    Text("No plan yet.")
                }
            }
            .padding(42)
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
}

struct StageRow: View {
    let stage: StagePlan
    let isEditing: Bool
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(stage.order)")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(FFColors.blue, in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(stage.title)
                        .font(.headline)
                        .foregroundStyle(FFColors.ink)
                    Spacer()
                    Text(stage.estimatedSeconds.minutesText)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(FFColors.blue)
                    Button {
                        onEdit()
                    } label: {
                        Label(isEditing ? "Editing" : "Edit", systemImage: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("edit_stage_\(stage.order)_button")
                }
                Text(stage.instruction)
                    .font(.callout)
                    .foregroundStyle(FFColors.ink)
                Text(stage.completionCriteria)
                    .font(.caption)
                    .foregroundStyle(FFColors.softGray)
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
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
            HStack {
                Picker("Type", selection: $stageType) {
                    ForEach(StageType.allCases, id: \.self) { type in
                        Text(type.readableName).tag(type)
                    }
                }
                Stepper("Minutes: \(minutes)", value: $minutes, in: (isFirstStage ? 2 : 1)...25)
            }
            HStack {
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
        .background(FFColors.lavender, in: RoundedRectangle(cornerRadius: 8))
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
