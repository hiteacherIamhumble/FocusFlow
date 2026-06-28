import AppKit
import FocusFlowCore
import SwiftUI
import UniformTypeIdentifiers

struct TaskInputView: View {
    @EnvironmentObject private var model: FocusFlowAppModel
    @FocusState private var taskEditorFocused: Bool
    @FocusState private var clarificationFocused: Bool

    private let templates = [
        "I need to start my essay",
        "Read one paper for class",
        "Review for my exam",
        "Prepare a group presentation"
    ]

    private var isClarifying: Bool {
        !model.clarificationQuestions.isEmpty
    }

    private var visibleTemplates: [String] {
        let trimmed = model.taskInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return templates.filter { $0.lowercased() != trimmed }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                headerSection

                if isClarifying {
                    taskSummarySection
                    if let question = model.clarificationQuestions.first {
                        ClarificationCard(
                            question: question,
                            turnIndex: model.clarificationTurnNumber,
                            isFocused: $clarificationFocused
                        )
                    }
                } else {
                    taskInputSection
                    if !visibleTemplates.isEmpty {
                        templateSection
                    }
                    primaryAction
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 48)
            .padding(.vertical, 36)
        }
        .scrollIndicators(.visible)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                if isClarifying {
                    clarificationFocused = true
                } else {
                    taskEditorFocused = true
                }
            }
        }
        .onChange(of: isClarifying) { _, clarifying in
            if clarifying {
                clarificationFocused = true
            } else {
                taskEditorFocused = true
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isClarifying ? "One quick follow-up" : "What learning task should we make smaller?")
                .font(AppFont.pageTitle)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(isClarifying
                ? "Answer in your own words. Short is fine, or attach a PDF if you have one."
                : "It does not need to be complete. Write the messy version, and FocusFlow will find the first tiny step.")
                .font(.title3)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var taskSummarySection: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "text.quote")
                .font(.title3)
                .foregroundStyle(AppColor.actionPrimary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("Your task")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.textSecondary)
                Text(model.taskInput.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.body.weight(.medium))
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button("Edit") {
                model.clearPlanningClarification()
                taskEditorFocused = true
            }
            .buttonStyle(.plain)
            .font(.callout.weight(.semibold))
            .foregroundStyle(AppColor.actionPrimary)
            .accessibilityIdentifier("edit_task_input_button")
        }
        .padding(16)
        .background(AppColor.surfaceCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColor.borderSubtle.opacity(0.7)))
    }

    private var taskInputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Task")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColor.textSecondary)

            TextEditor(text: $model.taskInput)
                .font(.title3)
                .foregroundStyle(AppColor.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(14)
                .frame(minHeight: 120, maxHeight: 160)
                .frame(maxWidth: .infinity)
                .focused($taskEditorFocused)
                .background(AppColor.surfaceCard, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(taskEditorFocused ? AppColor.focusRing : AppColor.borderSubtle.opacity(0.7), lineWidth: taskEditorFocused ? 2 : 1)
                )
                .accessibilityIdentifier("task_input_editor")

            if model.isListeningForVoice {
                Label(
                    "Listening: \(model.voiceTranscript.isEmpty ? "start speaking when ready" : model.voiceTranscript)",
                    systemImage: "waveform"
                )
                .font(.callout.weight(.semibold))
                .foregroundStyle(AppColor.actionPrimary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColor.actionContainer, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var templateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Examples")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColor.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(visibleTemplates, id: \.self) { template in
                        Button(template) {
                            model.taskInput = template
                            model.clearPlanningClarification()
                            taskEditorFocused = true
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

                    if !model.taskInput.isEmpty {
                        Button {
                            model.taskInput = ""
                            model.clearPlanningClarification()
                            taskEditorFocused = true
                        } label: {
                            Label("Clear", systemImage: "xmark.circle")
                        }
                        .buttonStyle(CompactSecondaryButtonStyle())
                        .accessibilityIdentifier("clear_task_input_button")
                    }
                }
            }
        }
    }

    private var primaryAction: some View {
        Button {
            model.createPlan()
        } label: {
            Label(model.isWorking ? "Planning..." : "Start planning", systemImage: "list.bullet.clipboard.fill")
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(model.isWorking || model.taskInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityIdentifier("start_planning_button")
    }
}

struct ClarificationCard: View {
    @EnvironmentObject private var model: FocusFlowAppModel
    let question: ClarificationQuestion
    let turnIndex: Int
    @FocusState.Binding var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Text("Question \(turnIndex)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppColor.actionOnContainer)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppColor.actionPrimary.opacity(0.18), in: Capsule())

                Spacer(minLength: 0)

                if model.isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text(question.question)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("Your answer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.textSecondary)

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $model.clarificationAnswerDraft)
                        .font(.body)
                        .foregroundStyle(AppColor.textPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .frame(minHeight: 96, maxHeight: 132)
                        .focused($isFocused)
                        .accessibilityIdentifier("clarification_answer_editor")

                    if model.clarificationAnswerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(question.placeholder ?? "Short answer is fine.")
                            .font(.body)
                            .foregroundStyle(AppColor.textSecondary.opacity(0.85))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }
                .background(AppColor.surfaceCard, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isFocused ? AppColor.focusRing : AppColor.borderSubtle.opacity(0.7), lineWidth: isFocused ? 2 : 1)
                )
            }

            if ClarificationHintRules.textHints(from: question.hintOptions).isEmpty == false || question.allowsFileUpload {
                quickActionsSection
            }

            if !model.planningAttachments.isEmpty {
                attachmentList
            }

            HStack(spacing: 12) {
                Button {
                    model.submitClarificationAnswer(skip: false)
                } label: {
                    Label(model.isWorking ? "Planning..." : "Continue planning", systemImage: "arrow.right.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.isWorking)
                .accessibilityIdentifier("submit_clarification_button")

                if question.skippable {
                    Button("Skip for now") {
                        model.submitClarificationAnswer(skip: true)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColor.textSecondary)
                    .accessibilityIdentifier("skip_clarification_button")
                }
            }
        }
        .padding(20)
        .background(AppColor.surfaceCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColor.actionPrimary.opacity(0.22), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var quickActionsSection: some View {
        let textHints = ClarificationHintRules.textHints(from: question.hintOptions)

        if !textHints.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Example answers")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.textSecondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(textHints, id: \.self) { hint in
                            Button(hint) {
                                model.applyClarificationHint(hint)
                                isFocused = true
                            }
                            .buttonStyle(CompactSecondaryButtonStyle())
                        }
                    }
                }
            }
        }

        if question.allowsFileUpload {
            VStack(alignment: .leading, spacing: 8) {
                Text("Add material")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.textSecondary)

                Button {
                    pickPDF()
                } label: {
                    Label("Attach assignment PDF", systemImage: "doc.badge.plus")
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("attach_planning_pdf_button")
            }
        }
    }

    @ViewBuilder
    private var attachmentList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attached")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColor.textSecondary)

            ForEach(model.planningAttachments) { attachment in
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(AppColor.actionPrimary)
                    Text(attachment.fileName)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Button {
                        model.removePlanningAttachment(attachment.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColor.textSecondary)
                    .accessibilityLabel("Remove \(attachment.fileName)")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AppColor.surfaceSubtle.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func pickPDF() {
        let panel = NSOpenPanel()
        panel.title = "Attach assignment PDF"
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.attachPlanningPDF(from: url)
    }
}
