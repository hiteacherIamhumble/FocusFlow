import FocusFlowCore
import SwiftUI

struct TaskInputView: View {
    @EnvironmentObject private var model: FocusFlowAppModel
    @FocusState private var taskEditorFocused: Bool

    private let templates = [
        "I need to start my essay",
        "Read one paper for class",
        "Review for my exam",
        "Prepare a group presentation"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer(minLength: 20)
            VStack(alignment: .leading, spacing: 10) {
                Text("What learning task should we make smaller?")
                    .font(AppFont.pageTitle)
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("It does not need to be complete. Write the messy version, and FocusFlow will find the first tiny step.")
                    .font(.title3)
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(maxWidth: 650, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 14) {
                TextEditor(text: $model.taskInput)
                    .font(.title3)
                    .foregroundStyle(AppColor.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(14)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .focused($taskEditorFocused)
                    .background(AppColor.surfaceCard, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(taskEditorFocused ? AppColor.focusRing : AppColor.actionPrimary.opacity(0.18), lineWidth: taskEditorFocused ? 2 : 1)
                    )
                    .onTapGesture {
                        taskEditorFocused = true
                    }
                    .accessibilityIdentifier("task_input_editor")

                if model.isListeningForVoice {
                    Label("Listening: \(model.voiceTranscript.isEmpty ? "start speaking when ready" : model.voiceTranscript)", systemImage: "waveform")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(AppColor.actionPrimary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppColor.actionContainer, in: RoundedRectangle(cornerRadius: 8))
                }

                AdaptiveButtonRow {
                    ForEach(templates, id: \.self) { template in
                        Button(template) {
                            model.taskInput = template
                            model.pendingPlanDraft = nil
                            model.clarificationQuestions = []
                        }
                        .buttonStyle(.plain)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(AppColor.actionPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppColor.surfaceCard, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColor.borderSubtle.opacity(0.7)))
                        .accessibilityIdentifier("task_template_\(template.lowercased().replacingOccurrences(of: " ", with: "_"))")
                    }
                    Button {
                        model.taskInput = ""
                        model.pendingPlanDraft = nil
                        model.clarificationQuestions = []
                        taskEditorFocused = true
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .opacity(model.taskInput.isEmpty ? 0 : 1)
                    .disabled(model.taskInput.isEmpty)
                    .accessibilityHidden(model.taskInput.isEmpty)
                }
                .frame(minHeight: 42, alignment: .leading)

                if let question = model.clarificationQuestions.first {
                    ClarificationCard(question: question)
                }
            }
            .frame(maxWidth: 760)

            Button {
                model.createPlan()
            } label: {
                Label(model.isWorking ? "Making steps..." : "Make it smaller", systemImage: "wand.and.stars")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.isWorking)
            .accessibilityIdentifier("make_it_smaller_button")
            Spacer()
        }
        .padding(48)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                taskEditorFocused = true
            }
        }
    }
}

struct ClarificationCard: View {
    @EnvironmentObject private var model: FocusFlowAppModel
    let question: ClarificationQuestion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "questionmark.bubble.fill")
                    .foregroundStyle(AppColor.actionPrimary)
                Text(question.question)
                    .font(.headline)
                    .foregroundStyle(AppColor.textPrimary)
            }
            AdaptiveButtonRow {
                ForEach(question.options.prefix(4), id: \.self) { option in
                    Button(option) {
                        model.answerClarification(option)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                if question.skippable {
                    Button("Skip") {
                        model.answerClarification(nil)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
        .padding(18)
        .background(AppColor.actionContainer, in: RoundedRectangle(cornerRadius: 8))
    }
}
