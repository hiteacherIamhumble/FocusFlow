import Foundation

public struct TaskBreakdownAgent: Sendable {
    private let llmClient: (any LLMClient)?

    public init(llmClient: (any LLMClient)? = nil) {
        self.llmClient = llmClient
    }

    public func makeDraftUsingLLM(from request: TaskInputRequest, privacyMode: PrivacyMode = .remoteLLMAllowedForCurrentContext) async -> TaskPlanDraft {
        let rawInput = request.rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard rawInput.isEmpty || isProbablyEducational(rawInput) else {
            return emptyDraft(for: rawInput, profile: request.userProfileSnapshot)
        }
        guard let llmClient else {
            return (try? makeDraft(from: request)) ?? emptyDraft(for: request.rawInput, profile: request.userProfileSnapshot)
        }
        do {
            let content = try await llmClient.complete(
                messages: [
                    LLMMessage(role: "system", content: taskPlanningSystemPrompt),
                    LLMMessage(role: "user", content: taskPlanningUserPrompt(for: request))
                ],
                privacyMode: privacyMode,
                responseFormat: .jsonObject
            )
            return try decodeLLMDraft(content, request: request)
        } catch {
            let fallback = (try? makeDraft(from: request)) ?? emptyDraft(for: request.rawInput, profile: request.userProfileSnapshot)
            var task = fallback.task
            task.metadata["planning_mode"] = "local_rules"
            task.metadata["agent_fallback_reason"] = error.localizedDescription
            return TaskPlanDraft(
                task: task,
                confidence: fallback.confidence,
                clarificationQuestions: fallback.clarificationQuestions
            )
        }
    }

    public func makeDraft(from request: TaskInputRequest) throws -> TaskPlanDraft {
        let rawInput = request.rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawInput.isEmpty else {
            return emptyDraft(for: rawInput, profile: request.userProfileSnapshot)
        }

        let taskType = classify(rawInput)
        guard taskType != .unknown || looksEducational(rawInput) else {
            throw FocusFlowError.nonEducationalTask
        }

        let taskId = FocusFlowID.make("task")
        let title = makeTitle(from: rawInput, type: taskType)
        let stages = makeStages(taskId: taskId, input: rawInput, taskType: taskType, profile: request.userProfileSnapshot)
        let task = TaskPlan(
            id: taskId,
            originalInput: rawInput,
            title: title,
            taskType: taskType,
            status: .draft,
            estimatedTotalSeconds: stages.reduce(0) { $0 + $1.estimatedSeconds },
            stages: stages,
            metadata: ["planning_mode": "local_rules"]
        )
        let questions = clarificationQuestions(for: rawInput, type: taskType)
        return TaskPlanDraft(task: task, confidence: questions.isEmpty ? 0.78 : 0.52, clarificationQuestions: questions)
    }

    public func refine(_ task: TaskPlan, instruction: String) -> TaskPlan {
        let lower = instruction.lowercased()
        var refined = task
        if lower.contains("smaller") || lower.contains("split") || lower.contains("拆小") {
            refined.stages = splitLongestStage(in: refined)
            refined.metadata["last_refinement"] = "split_smaller"
        } else if lower.contains("regenerate") {
            if let draft = try? makeDraft(from: TaskInputRequest(
                rawInput: task.originalInput,
                userProfileSnapshot: nil,
                agentContext: nil
            )) {
                refined.title = draft.task.title
                refined.taskType = draft.task.taskType
                refined.stages = draft.task.stages.enumerated().map { offset, stage in
                    StagePlan(
                        taskId: task.id,
                        order: offset + 1,
                        title: stage.title,
                        instruction: stage.instruction,
                        completionCriteria: stage.completionCriteria,
                        stageType: stage.stageType,
                        estimatedSeconds: stage.estimatedSeconds,
                        status: .idle,
                        createdBy: .module1TaskPlanning,
                        metadata: ["regenerated_from": stage.id]
                    )
                }
            }
            refined.metadata["last_refinement"] = "regenerate"
        } else if lower.contains("shorter") || lower.contains("less") || lower.contains("减少") {
            refined.stages = Array(refined.stages.prefix(max(3, refined.stages.count - 1)))
            refined.metadata["last_refinement"] = "reduce_steps"
        } else if lower.contains("more time") || lower.contains("longer") || lower.contains("时间") {
            refined.stages = refined.stages.map { stage in
                var copy = stage
                if copy.stageType != .startup {
                    copy.estimatedSeconds = min(1_500, copy.estimatedSeconds + 300)
                }
                return copy
            }
            refined.metadata["last_refinement"] = "extend_time"
        }
        refined.estimatedTotalSeconds = refined.stages.reduce(0) { $0 + $1.estimatedSeconds }
        refined.updatedAt = Date()
        return refined
    }

    public func refineUsingLLM(
        _ task: TaskPlan,
        instruction: String,
        agentContext: AgentContext?,
        privacyMode: PrivacyMode = .remoteLLMAllowedForCurrentContext
    ) async -> TaskPlan {
        guard let llmClient else {
            return normalized(refine(task, instruction: instruction), mode: "local_rules", fallbackReason: nil)
        }
        do {
            let content = try await llmClient.complete(
                messages: [
                    LLMMessage(role: "system", content: taskRefinementSystemPrompt),
                    LLMMessage(role: "user", content: taskRefinementUserPrompt(task: task, instruction: instruction, context: agentContext))
                ],
                privacyMode: privacyMode,
                responseFormat: .jsonObject
            )
            return try decodeLLMRefinement(content, existingTask: task, instruction: instruction)
        } catch {
            let fallback = refine(task, instruction: instruction)
            return normalized(fallback, mode: "local_rules", fallbackReason: error.localizedDescription)
        }
    }

    private func emptyDraft(for input: String, profile: UserProfileSnapshot?) -> TaskPlanDraft {
        let task = TaskPlan(
            originalInput: input,
            title: "New learning task",
            taskType: .unknown,
            estimatedTotalSeconds: 0,
            stages: []
        )
        return TaskPlanDraft(
            task: task,
            confidence: 0,
            clarificationQuestions: [
                ClarificationQuestion(
                    question: "What learning task would you like to start with?",
                    options: ["An assignment", "Reading", "Exam review", "Presentation"],
                    skippable: false
                )
            ]
        )
    }

    private var taskPlanningSystemPrompt: String {
        """
        You are FocusFlow's TaskBreakdownAgent for a macOS educational agent.
        Output ONLY valid JSON.
        The product helps students with ADHD traits start education tasks.
        Do not diagnose. Do not shame. Do not use words like lazy, failure, should, or must.
        Accept only learning-related tasks: writing, reading, examReview, homework, presentation, longTermProject, unknown.
        Create short, concrete stages. The first stage must be 120-300 seconds.
        Normal stages should be <= 1500 seconds. Each stage needs title, instruction, completionCriteria, stageType, estimatedSeconds.
        Stage types: startup, reading, writing, reviewing, problemSolving, organizing, presentationMaking, breakTime, other.
        UI copy must be English, warm, direct, and low-pressure.
        JSON schema:
        {
          "title": "string",
          "task_type": "writing|reading|examReview|homework|presentation|longTermProject|unknown",
          "confidence": 0.0,
          "clarification_questions": [{"question":"string","options":["string"],"skippable":true}],
          "stages": [
            {"title":"string","instruction":"string","completion_criteria":"string","stage_type":"startup","estimated_seconds":180}
          ]
        }
        """
    }

    private var taskRefinementSystemPrompt: String {
        """
        You are FocusFlow's TaskBreakdownAgent revising an existing ADHD-friendly educational task plan.
        Output ONLY valid JSON.
        Preserve the user's learning goal and keep copy English, warm, direct, and low-pressure.
        Follow the user adjustment exactly:
        - split smaller: make one or more large/vague stages smaller and more concrete.
        - reduce steps: remove or merge lower-value stages while preserving a tiny first step and a usable path.
        - more time: add time to non-startup work without making any stage exceed 1500 seconds.
        - regenerate: produce a fresh, coherent plan from the original goal and current context.
        Return the complete revised plan, not a patch.
        The first stage must remain 120-300 seconds. All later stages must be 60-1500 seconds.
        Stage order is implied by array order and must be coherent.
        Do not diagnose. Do not shame. Avoid words like lazy, failure, should, or must.
        JSON schema:
        {
          "title": "string",
          "task_type": "writing|reading|examReview|homework|presentation|longTermProject|unknown",
          "agent_response": "short user-visible explanation of what changed",
          "stages": [
            {"title":"string","instruction":"string","completion_criteria":"string","stage_type":"startup","estimated_seconds":180}
          ]
        }
        """
    }

    private func taskPlanningUserPrompt(for request: TaskInputRequest) -> String {
        let context = request.agentContext
        let profile = context?.userProfileSnapshot ?? request.userProfileSnapshot
        let stats = context?.recentStatsSummary
        let recentNotes = context?.recentSimilarTaskNotes.prefix(5).joined(separator: "\n- ") ?? ""
        return """
        Raw user input:
        \(request.rawInput)

        Local profile snapshot, already privacy-filtered:
        preferred_stage_duration_seconds=\(profile?.preferredStageDurationSeconds.map(String.init) ?? "unknown")
        recommended_first_stage_seconds=\(profile?.recommendedFirstStageSeconds.map(String.init) ?? "180")
        difficult_stage_types=\((profile?.difficultStageTypes ?? []).map(\.rawValue).joined(separator: ","))
        encouragement_style=\(profile?.encouragementStyle.rawValue ?? "gentleDirect")

        Recent local stats summary:
        active_days=\(stats?.activeDays.description ?? "unknown")
        completed_stage_count=\(stats?.completedStageCount.description ?? "unknown")
        total_focus_seconds=\(stats?.totalFocusSeconds.description ?? "unknown")

        Recent privacy-filtered history notes:
        \(recentNotes.isEmpty ? "none" : "- \(recentNotes)")

        Return a plan with 4-8 stages unless the task is tiny. Keep all text English.
        """
    }

    private func taskRefinementUserPrompt(task: TaskPlan, instruction: String, context: AgentContext?) -> String {
        let stagesJSON = task.stages.sorted { $0.order < $1.order }.map { stage in
            """
            {"order":\(stage.order),"title":\(stage.title.jsonEscaped),"instruction":\(stage.instruction.jsonEscaped),"completion_criteria":\(stage.completionCriteria.jsonEscaped),"stage_type":\(stage.stageType.rawValue.jsonEscaped),"estimated_seconds":\(stage.estimatedSeconds),"status":\(stage.status.rawValue.jsonEscaped)}
            """
        }.joined(separator: ",")
        let profile = context?.userProfileSnapshot
        let stats = context?.recentStatsSummary
        return """
        User adjustment:
        \(instruction)

        Original learning input:
        \(task.originalInput)

        Current task:
        {"title":\(task.title.jsonEscaped),"task_type":\(task.taskType.rawValue.jsonEscaped),"estimated_total_seconds":\(task.estimatedTotalSeconds),"stages":[\(stagesJSON)]}

        Privacy-filtered profile:
        preferred_stage_duration_seconds=\(profile?.preferredStageDurationSeconds.map(String.init) ?? "unknown")
        recommended_first_stage_seconds=\(profile?.recommendedFirstStageSeconds.map(String.init) ?? "180")
        difficult_stage_types=\((profile?.difficultStageTypes ?? []).map(\.rawValue).joined(separator: ","))

        Recent local stats:
        active_days=\(stats?.activeDays.description ?? "unknown")
        completed_stage_count=\(stats?.completedStageCount.description ?? "unknown")
        total_focus_seconds=\(stats?.totalFocusSeconds.description ?? "unknown")

        Return a complete revised plan with 3-8 stages unless the task truly needs fewer.
        """
    }

    private func decodeLLMDraft(_ content: String, request: TaskInputRequest) throws -> TaskPlanDraft {
        let data = Data(content.utf8)
        let decoded = try FocusFlowJSON.decoder.decode(LLMTaskPlanDraft.self, from: data)
        let taskType = EducationTaskType(rawValue: decoded.taskType) ?? .unknown
        guard taskType != .unknown || looksEducational(request.rawInput) else {
            throw FocusFlowError.nonEducationalTask
        }
        let taskId = FocusFlowID.make("task")
        var stages = decoded.stages.enumerated().map { index, stage in
            StagePlan(
                taskId: taskId,
                order: index + 1,
                title: stage.title.cleanAgentText(fallback: "Small learning step"),
                instruction: stage.instruction.cleanAgentText(fallback: "Do one visible part of this step."),
                completionCriteria: stage.completionCriteria.cleanAgentText(fallback: "One visible part is done."),
                stageType: StageType(rawValue: stage.stageType) ?? .other,
                estimatedSeconds: min(1_500, max(120, stage.estimatedSeconds))
            )
        }
        if stages.isEmpty {
            return try makeDraft(from: request)
        }
        stages[0].estimatedSeconds = min(300, max(120, stages[0].estimatedSeconds))
        stages = stages.enumerated().map { offset, stage in
            var copy = stage
            copy.order = offset + 1
            return copy
        }
        let task = TaskPlan(
            id: taskId,
            originalInput: request.rawInput,
            title: decoded.title.cleanAgentText(fallback: makeTitle(from: request.rawInput, type: taskType)),
            taskType: taskType,
            status: .draft,
            estimatedTotalSeconds: stages.reduce(0) { $0 + $1.estimatedSeconds },
            stages: stages,
            metadata: ["planning_mode": "deepseek_v4_flash"]
        )
        let questions = decoded.clarificationQuestions.prefix(3).map {
            ClarificationQuestion(
                question: $0.question.cleanAgentText(fallback: "Which part should we start with?"),
                options: Array($0.options.prefix(4)),
                skippable: $0.skippable
            )
        }
        return TaskPlanDraft(task: task, confidence: min(1, max(0, decoded.confidence)), clarificationQuestions: Array(questions))
    }

    private func decodeLLMRefinement(_ content: String, existingTask: TaskPlan, instruction: String) throws -> TaskPlan {
        let data = Data(content.utf8)
        let decoded = try FocusFlowJSON.decoder.decode(LLMTaskPlanRefinement.self, from: data)
        let taskType = EducationTaskType(rawValue: decoded.taskType) ?? existingTask.taskType
        var stages = decoded.stages.enumerated().map { index, stage in
            StagePlan(
                taskId: existingTask.id,
                order: index + 1,
                title: stage.title.cleanAgentText(fallback: "Small learning step"),
                instruction: stage.instruction.cleanAgentText(fallback: "Do one visible part of this step."),
                completionCriteria: stage.completionCriteria.cleanAgentText(fallback: "One visible part is done."),
                stageType: StageType(rawValue: stage.stageType) ?? .other,
                estimatedSeconds: min(1_500, max(index == 0 ? 120 : 60, stage.estimatedSeconds)),
                status: .idle,
                createdBy: .module1TaskPlanning,
                metadata: ["refined_by": "deepseek_v4_flash"]
            )
        }
        guard !stages.isEmpty else {
            throw FocusFlowError.invalidState("DeepSeek returned an empty revised plan.")
        }
        stages[0].estimatedSeconds = min(300, max(120, stages[0].estimatedSeconds))
        var refined = TaskPlan(
            id: existingTask.id,
            originalInput: existingTask.originalInput,
            title: decoded.title.cleanAgentText(fallback: existingTask.title),
            taskType: taskType,
            status: existingTask.status,
            createdAt: existingTask.createdAt,
            updatedAt: Date(),
            deadline: existingTask.deadline,
            estimatedTotalSeconds: stages.reduce(0) { $0 + $1.estimatedSeconds },
            stages: stages,
            metadata: existingTask.metadata.merging([
                "last_refinement": refinementKind(for: instruction),
                "planning_mode": "deepseek_v4_flash",
                "agent_response": decoded.agentResponse.cleanAgentText(fallback: "I revised the plan into smaller, clearer steps."),
                "refined_at": ISO8601DateFormatter().string(from: Date())
            ]) { _, new in new }
        )
        refined = normalized(refined, mode: "deepseek_v4_flash", fallbackReason: nil)
        return refined
    }

    private func classify(_ input: String) -> EducationTaskType {
        let lower = input.lowercased()
        if containsAny(lower, ["essay", "paper", "report", "write", "writing", "文", "论文", "报告", "写"]) { return .writing }
        if containsAny(lower, ["read", "reading", "pdf", "article", "paper abstract", "论文", "阅读", "读"]) { return .reading }
        if containsAny(lower, ["exam", "quiz", "test", "review", "midterm", "final", "复习", "考试", "测验"]) { return .examReview }
        if containsAny(lower, ["homework", "assignment", "problem set", "worksheet", "作业", "题"]) { return .homework }
        if containsAny(lower, ["presentation", "slides", "ppt", "talk", "展示", "演讲", "汇报"]) { return .presentation }
        if containsAny(lower, ["thesis", "portfolio", "project", "capstone", "毕业", "项目"]) { return .longTermProject }
        return .unknown
    }

    private func looksEducational(_ input: String) -> Bool {
        containsAny(input.lowercased(), ["class", "course", "study", "school", "lecture", "learn", "homework", "assignment", "学习", "课程", "课", "作业"])
    }

    private func isProbablyEducational(_ input: String) -> Bool {
        classify(input) != .unknown || looksEducational(input)
    }

    private func containsAny(_ input: String, _ terms: [String]) -> Bool {
        terms.contains { input.contains($0) }
    }

    private func makeTitle(from input: String, type: EducationTaskType) -> String {
        if input.count <= 48 { return input.capitalizedFirstSentence }
        switch type {
        case .writing: return "Writing task"
        case .reading: return "Reading task"
        case .examReview: return "Exam review"
        case .homework: return "Homework session"
        case .presentation: return "Presentation prep"
        case .longTermProject: return "Long-term learning project"
        case .unknown: return "Learning task"
        }
    }

    private func makeStages(taskId: String, input: String, taskType: EducationTaskType, profile: UserProfileSnapshot?) -> [StagePlan] {
        let firstSeconds = min(300, max(120, profile?.recommendedFirstStageSeconds ?? 180))
        let preferred = min(1_500, max(480, profile?.preferredStageDurationSeconds ?? 720))
        let definitions: [(String, String, String, StageType, Int)]

        switch taskType {
        case .writing:
            definitions = [
                ("Open the requirement", "Open the assignment page and find the topic, format, and deadline.", "Requirement page is open and the deadline is visible.", .startup, firstSeconds),
                ("Create a rough document", "Create a blank document and write the working title at the top.", "A document exists with a rough title.", .writing, 300),
                ("List three points", "Write three messy bullet points you may include.", "Three bullets are on the page.", .organizing, 480),
                ("Draft one small section", "Write one imperfect paragraph or outline block.", "One paragraph or block exists.", .writing, preferred),
                ("Mark the next source", "Write down one source or note you need next.", "One next source or note is listed.", .reviewing, 480)
            ]
        case .reading:
            definitions = [
                ("Open the reading", "Open the PDF, article, or chapter and look only at the title and headings.", "The reading is open and the main title is identified.", .startup, firstSeconds),
                ("Read the abstract or intro", "Read the abstract or first page without taking detailed notes.", "You know the basic topic.", .reading, min(preferred, 600)),
                ("Find the main claim", "Highlight or write one sentence for what the author is trying to do.", "One main-claim note exists.", .reading, min(preferred, 720)),
                ("Capture three keywords", "Write three terms, names, or ideas worth remembering.", "Three keywords are written down.", .organizing, 360),
                ("Choose the next section", "Pick one section to read next, not the whole paper.", "The next section is chosen.", .reviewing, 240)
            ]
        case .examReview:
            definitions = [
                ("Find the scope", "Open the syllabus, review guide, or first lecture deck.", "The exam scope or first material is visible.", .startup, firstSeconds),
                ("Make a tiny map", "Write the first three topics that may appear on the exam.", "Three topics are listed.", .organizing, 420),
                ("Review one topic", "Review notes for just one topic and mark confusing parts.", "One topic has been reviewed.", .reviewing, preferred),
                ("Do three questions", "Answer three practice questions or examples.", "Three questions are attempted.", .problemSolving, min(preferred, 900)),
                ("Save the next target", "Write what to review next time.", "One next review target is saved.", .reviewing, 240)
            ]
        case .homework:
            definitions = [
                ("Open the homework", "Open the assignment and count how many questions there are.", "The question count is known.", .startup, firstSeconds),
                ("Pick the easiest item", "Choose one question that looks most approachable.", "One starting question is selected.", .organizing, 240),
                ("Attempt one question", "Work on only the selected question.", "One question is attempted.", .problemSolving, preferred),
                ("Check the next blocker", "Write what is confusing or what resource is needed.", "A blocker or next step is written.", .reviewing, 300),
                ("Set the next question", "Pick the next question to attempt later.", "The next question is selected.", .organizing, 180)
            ]
        case .presentation:
            definitions = [
                ("Find the presentation brief", "Open the course page and find the topic, time limit, and due date.", "The brief is visible.", .startup, firstSeconds),
                ("Create the slide file", "Create a new slide deck and write the working title.", "A slide file exists with a title.", .presentationMaking, 300),
                ("List three talking points", "Write three rough points you might cover.", "Three talking points are listed.", .organizing, 480),
                ("Draft the first slide", "Make one simple slide with a title and one sentence.", "One slide has content.", .presentationMaking, preferred),
                ("Practice the opening", "Say the first 30 seconds out loud once.", "The opening has been tried once.", .reviewing, 300)
            ]
        case .longTermProject:
            definitions = [
                ("Open the project notes", "Open the main project document, brief, or folder.", "The project material is open.", .startup, firstSeconds),
                ("Write today's target", "Write one outcome that would make today feel useful.", "One target is written.", .organizing, 240),
                ("Choose a tiny deliverable", "Pick one small artifact to create or improve.", "One tiny deliverable is selected.", .organizing, 360),
                ("Work one short block", "Spend one focused block on that deliverable.", "The deliverable moved forward.", .other, preferred),
                ("Save a handoff note", "Write where to continue next time.", "A next-time note is saved.", .reviewing, 240)
            ]
        case .unknown:
            definitions = [
                ("Name the learning task", "Write the course, assignment, or material you want to handle.", "The learning target is named.", .startup, firstSeconds),
                ("Find the starting material", "Open one relevant file, page, note, or problem.", "One starting material is open.", .organizing, 300),
                ("Do the smallest visible action", "Complete one action that takes less than ten minutes.", "One small action is done.", .other, 480)
            ]
        }

        return definitions.enumerated().map { index, item in
            StagePlan(
                taskId: taskId,
                order: index + 1,
                title: item.0,
                instruction: item.1,
                completionCriteria: item.2,
                stageType: item.3,
                estimatedSeconds: min(1_500, item.4)
            )
        }
    }

    private func clarificationQuestions(for input: String, type: EducationTaskType) -> [ClarificationQuestion] {
        guard input.split(separator: " ").count <= 3 || input.count < 12 || type == .unknown else { return [] }
        return [
            ClarificationQuestion(
                question: "Which part should we make easier to start?",
                options: ["The most urgent", "The easiest", "The most stressful", "Choose for me"],
                skippable: true
            )
        ]
    }

    private func splitLongestStage(in task: TaskPlan) -> [StagePlan] {
        guard let longest = task.stages.max(by: { $0.estimatedSeconds < $1.estimatedSeconds }),
              let index = task.stages.firstIndex(where: { $0.id == longest.id }),
              longest.estimatedSeconds > 420 else {
            return task.stages
        }
        var first = longest
        first.title = "Start: \(longest.title)"
        first.instruction = "Do only the first visible piece of this step."
        first.completionCriteria = "The first piece is started."
        first.estimatedSeconds = max(180, longest.estimatedSeconds / 2)
        first.parentStageId = longest.id
        first.createdBy = .module3FeedbackOptimization

        var second = longest
        second.title = "Continue: \(longest.title)"
        second.instruction = longest.instruction
        second.estimatedSeconds = max(180, longest.estimatedSeconds - first.estimatedSeconds)
        second.parentStageId = longest.id
        second.createdBy = .module3FeedbackOptimization

        var stages = task.stages
        stages.remove(at: index)
        stages.insert(contentsOf: [first, second], at: index)
        return stages.enumerated().map { offset, stage in
            var copy = stage
            copy.order = offset + 1
            return copy
        }
    }

    private func normalized(_ task: TaskPlan, mode: String, fallbackReason: String?) -> TaskPlan {
        var copy = task
        copy.stages = copy.stages.enumerated().map { offset, stage in
            var stageCopy = stage
            stageCopy.order = offset + 1
            stageCopy.estimatedSeconds = min(1_500, max(offset == 0 ? 120 : 60, stageCopy.estimatedSeconds))
            if offset == 0 {
                stageCopy.estimatedSeconds = min(300, stageCopy.estimatedSeconds)
            }
            return stageCopy
        }
        copy.estimatedTotalSeconds = copy.stages.reduce(0) { $0 + $1.estimatedSeconds }
        copy.updatedAt = Date()
        copy.metadata["planning_mode"] = mode
        copy.metadata["refined_at"] = ISO8601DateFormatter().string(from: Date())
        copy.metadata["agent_response"] = mode == "deepseek_v4_flash"
            ? (copy.metadata["agent_response"] ?? "I revised the plan into smaller, clearer steps.")
            : fallbackAgentResponse(for: copy.metadata["last_refinement"])
        if let fallbackReason {
            copy.metadata["agent_fallback_reason"] = fallbackReason
        } else {
            copy.metadata.removeValue(forKey: "agent_fallback_reason")
        }
        return copy
    }

    private func refinementKind(for instruction: String) -> String {
        let lower = instruction.lowercased()
        if lower.contains("regenerate") { return "regenerate" }
        if lower.contains("smaller") || lower.contains("split") || lower.contains("拆小") { return "split_smaller" }
        if lower.contains("shorter") || lower.contains("less") || lower.contains("reduce") || lower.contains("减少") { return "reduce_steps" }
        if lower.contains("more time") || lower.contains("longer") || lower.contains("时间") { return "extend_time" }
        return "agent_refine"
    }

    private func fallbackAgentResponse(for refinement: String?) -> String {
        switch refinement {
        case "split_smaller":
            return "I split the largest step and renumbered the plan."
        case "reduce_steps":
            return "I reduced the plan to the most useful next steps."
        case "extend_time":
            return "I added time to the work steps while keeping the first step small."
        case "regenerate":
            return "I regenerated the plan with a fresh local fallback."
        default:
            return "I revised the plan locally."
        }
    }
}

private extension String {
    var capitalizedFirstSentence: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }

    func cleanAgentText(fallback: String) -> String {
        let banned = ["lazy", "failure", "you should", "you must", "failed"]
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        guard !banned.contains(where: { trimmed.lowercased().contains($0) }) else { return fallback }
        return trimmed
    }

    var jsonEscaped: String {
        if let data = try? JSONEncoder().encode(self),
           let value = String(data: data, encoding: .utf8) {
            return value
        }
        return "\"\""
    }
}

private struct LLMTaskPlanDraft: Decodable {
    let title: String
    let taskType: String
    let confidence: Double
    let clarificationQuestions: [LLMClarificationQuestion]
    let stages: [LLMStage]
}

private struct LLMClarificationQuestion: Decodable {
    let question: String
    let options: [String]
    let skippable: Bool
}

private struct LLMStage: Decodable {
    let title: String
    let instruction: String
    let completionCriteria: String
    let stageType: String
    let estimatedSeconds: Int
}

private struct LLMTaskPlanRefinement: Decodable {
    let title: String
    let taskType: String
    let agentResponse: String
    let stages: [LLMStage]
}
