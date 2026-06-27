import FocusFlowCore
import SwiftUI

struct TaskInputView: View {
    @EnvironmentObject private var model: FocusFlowAppModel

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
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(FFColors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("It does not need to be complete. Write the messy version, and FocusFlow will find the first tiny step.")
                    .font(.title3)
                    .foregroundStyle(FFColors.softGray)
                    .frame(maxWidth: 650, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 14) {
                TextEditor(text: $model.taskInput)
                    .font(.title3)
                    .foregroundStyle(FFColors.ink)
                    .scrollContentBackground(.hidden)
                    .padding(14)
                    .frame(minHeight: 150)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(FFColors.blue.opacity(0.18), lineWidth: 1)
                    )
                    .accessibilityIdentifier("task_input_editor")

                if model.isListeningForVoice {
                    Label("Listening: \(model.voiceTranscript.isEmpty ? "start speaking when ready" : model.voiceTranscript)", systemImage: "waveform")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(FFColors.blue)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(FFColors.lavender, in: RoundedRectangle(cornerRadius: 8))
                }

                HStack {
                    ForEach(templates, id: \.self) { template in
                        Button(template) {
                            model.taskInput = template
                            model.pendingPlanDraft = nil
                            model.clarificationQuestions = []
                        }
                        .buttonStyle(.plain)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(FFColors.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityIdentifier("task_template_\(template.lowercased().replacingOccurrences(of: " ", with: "_"))")
                    }
                }

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
    }
}

struct ClarificationCard: View {
    @EnvironmentObject private var model: FocusFlowAppModel
    let question: ClarificationQuestion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "questionmark.bubble.fill")
                    .foregroundStyle(FFColors.blue)
                Text(question.question)
                    .font(.headline)
                    .foregroundStyle(FFColors.ink)
            }
            HStack {
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
                    .foregroundStyle(FFColors.softGray)
                }
            }
        }
        .padding(18)
        .background(FFColors.lavender, in: RoundedRectangle(cornerRadius: 8))
    }
}
