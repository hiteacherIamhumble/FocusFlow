import XCTest
@testable import FocusFlowCore

final class FocusFlowCoreTests: XCTestCase {
    func testTaskBreakdownCreatesTinyFirstStep() throws {
        let agent = TaskBreakdownAgent()
        let draft = try agent.makeDraft(from: TaskInputRequest(
            rawInput: "I need to prepare a group presentation for class",
            userProfileSnapshot: .empty
        ))

        XCTAssertEqual(draft.task.taskType, .presentation)
        XCTAssertFalse(draft.task.stages.isEmpty)
        XCTAssertGreaterThanOrEqual(draft.task.stages[0].estimatedSeconds, 120)
        XCTAssertLessThanOrEqual(draft.task.stages[0].estimatedSeconds, 300)
        XCTAssertTrue(draft.task.stages.allSatisfy { $0.estimatedSeconds <= 1_500 })
    }

    func testTaskPlanningDraftClarificationIsAcceptedBeforePersistence() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let dataCenter = LocalDataCenterService(directory: root)
        let repository = LocalTaskRepository(directory: root)
        let eventBus = AppEventBus(dataCenter: dataCenter)
        let service = TaskPlanningService(repository: repository, eventBus: eventBus)

        let draft = try await service.createDraft(from: "study", agentContext: nil)
        let beforeAcceptJSON = try await dataCenter.exportEventsJSON()
        let tasksBeforeAccept = try await repository.listTasks()

        XCTAssertFalse(draft.clarificationQuestions.isEmpty)
        XCTAssertTrue(draft.task.stages.isEmpty)
        XCTAssertEqual(tasksBeforeAccept.count, 0)
        XCTAssertFalse(beforeAcceptJSON.contains("taskCreated"))

        let continued = try await service.continuePlanning(
            context: TaskPlanningContext(
                rawInput: "study",
                turns: [TaskPlanningTurn(question: draft.clarificationQuestions[0].question, answer: "The easiest")]
            ),
            agentContext: nil
        )
        let task = try await service.acceptDraft(continued, clarificationAnswer: "The easiest")
        let afterAcceptJSON = try await dataCenter.exportEventsJSON()
        let tasksAfterAccept = try await repository.listTasks()

        XCTAssertEqual(task.metadata["clarification_answer"], "The easiest")
        XCTAssertEqual(tasksAfterAccept.count, 1)
        XCTAssertTrue(afterAcceptJSON.contains("\"event_type\":\"taskCreated\"") || afterAcceptJSON.contains("\"event_type\" : \"taskCreated\""))
        XCTAssertTrue(afterAcceptJSON.contains("The easiest"))
    }

    func testTaskPlanningRecordsAgentRunEvents() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let dataCenter = LocalDataCenterService(directory: root)
        let repository = LocalTaskRepository(directory: root)
        let eventBus = AppEventBus(dataCenter: dataCenter)
        let service = TaskPlanningService(repository: repository, eventBus: eventBus)

        let draft = try await service.createDraft(
            from: "Read Smith 2024 paper on neural networks for BIO 101 due Friday",
            agentContext: nil
        )
        let json = try await dataCenter.exportEventsJSON()

        XCTAssertFalse(draft.task.stages.isEmpty)
        XCTAssertTrue(json.contains("\"event_type\":\"agentRunStarted\"") || json.contains("\"event_type\" : \"agentRunStarted\""))
        XCTAssertTrue(json.contains("\"event_type\":\"agentRunCompleted\"") || json.contains("\"event_type\" : \"agentRunCompleted\""))
        XCTAssertTrue(json.contains("TaskBreakdownAgent"))
        XCTAssertTrue(json.contains("create_task_plan_draft"))
        XCTAssertFalse(json.contains("Read a paper for class"))
    }

    func testTaskPlanningRejectsNonEducationalInputBeforePersistence() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let dataCenter = LocalDataCenterService(directory: root)
        let repository = LocalTaskRepository(directory: root)
        let eventBus = AppEventBus(dataCenter: dataCenter)
        let service = TaskPlanningService(repository: repository, eventBus: eventBus)

        do {
            _ = try await service.createDraft(from: "buy groceries and clean the kitchen", agentContext: nil)
            XCTFail("Expected non-educational input to be rejected.")
        } catch FocusFlowError.nonEducationalTask {
            let tasks = try await repository.listTasks()
            XCTAssertEqual(tasks.count, 0)
            let json = try await dataCenter.exportEventsJSON()
            XCTAssertFalse(json.contains("taskCreated"))
        }
    }

    func testTaskPlanRefineMoreTimeExtendsNonStartupStages() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let dataCenter = LocalDataCenterService(directory: root)
        let repository = LocalTaskRepository(directory: root)
        let eventBus = AppEventBus(dataCenter: dataCenter)
        let service = TaskPlanningService(repository: repository, eventBus: eventBus)
        let task = TaskPlan(
            id: "task_more_time",
            originalInput: "Read a paper",
            title: "Read a paper",
            taskType: .reading,
            status: .draft,
            estimatedTotalSeconds: 900,
            stages: [
                StagePlan(
                    id: "stage_startup_more_time",
                    taskId: "task_more_time",
                    order: 1,
                    title: "Open the paper",
                    instruction: "Open the PDF.",
                    completionCriteria: "The PDF is open.",
                    stageType: .startup,
                    estimatedSeconds: 180
                ),
                StagePlan(
                    id: "stage_read_more_time",
                    taskId: "task_more_time",
                    order: 2,
                    title: "Read the abstract",
                    instruction: "Read the abstract and mark one sentence.",
                    completionCriteria: "One sentence is marked.",
                    stageType: .reading,
                    estimatedSeconds: 720
                )
            ]
        )
        try await repository.save(task)

        let refined = try await service.refinePlan(task, userInstruction: "more time")

        XCTAssertEqual(refined.metadata["last_refinement"], "extend_time")
        XCTAssertEqual(refined.stages[0].estimatedSeconds, task.stages[0].estimatedSeconds)
        XCTAssertGreaterThan(refined.stages[1].estimatedSeconds, task.stages[1].estimatedSeconds)
        XCTAssertTrue(refined.stages.allSatisfy { $0.estimatedSeconds <= 1_500 })
    }

    func testTaskPlanRegenerateKeepsTaskIdAndPublishesUpdate() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let dataCenter = LocalDataCenterService(directory: root)
        let repository = LocalTaskRepository(directory: root)
        let eventBus = AppEventBus(dataCenter: dataCenter)
        let service = TaskPlanningService(repository: repository, eventBus: eventBus)
        let task = sampleTask()
        try await repository.save(task)

        let regenerated = try await service.regeneratePlan(task, agentContext: nil)
        let stored = try await repository.getTask(task.id)
        let json = try await dataCenter.exportEventsJSON()

        XCTAssertEqual(regenerated.id, task.id)
        XCTAssertEqual(stored.id, task.id)
        XCTAssertEqual(regenerated.metadata["last_refinement"], "regenerate")
        XCTAssertTrue(regenerated.stages.allSatisfy { $0.taskId == task.id })
        XCTAssertTrue(json.contains("\"event_type\":\"taskPlanUpdated\"") || json.contains("\"event_type\" : \"taskPlanUpdated\""))
        XCTAssertTrue(json.contains("\"instruction\":\"regenerate\"") || json.contains("\"instruction\" : \"regenerate\""))
    }

    func testTaskPlanRefineUsesLLMAndRenumbersStages() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let dataCenter = LocalDataCenterService(directory: root)
        let repository = LocalTaskRepository(directory: root)
        let eventBus = AppEventBus(dataCenter: dataCenter)
        let agent = TaskBreakdownAgent(llmClient: FakeLLMClient(response: """
        {
          "title": "Read one paper",
          "task_type": "reading",
          "agent_response": "I split the reading into smaller checkpoints.",
          "stages": [
            {
              "title": "Open the PDF",
              "instruction": "Open the paper and look at the title.",
              "completion_criteria": "The paper is open.",
              "stage_type": "startup",
              "estimated_seconds": 180
            },
            {
              "title": "Read the abstract",
              "instruction": "Read only the abstract and write one note.",
              "completion_criteria": "One abstract note exists.",
              "stage_type": "reading",
              "estimated_seconds": 420
            },
            {
              "title": "Mark one next section",
              "instruction": "Choose the next section to read.",
              "completion_criteria": "One section is chosen.",
              "stage_type": "organizing",
              "estimated_seconds": 240
            }
          ]
        }
        """))
        let service = TaskPlanningService(agent: agent, repository: repository, eventBus: eventBus)
        let task = sampleTask()
        try await repository.save(task)

        let refined = try await service.refinePlan(task, userInstruction: "split smaller")
        let stored = try await repository.getTask(task.id)
        let json = try await dataCenter.exportEventsJSON()

        XCTAssertEqual(refined.id, task.id)
        XCTAssertEqual(stored.stages.map(\.order), [1, 2, 3])
        XCTAssertEqual(refined.metadata["planning_mode"], "deepseek_v4_flash")
        XCTAssertEqual(refined.metadata["agent_response"], "I split the reading into smaller checkpoints.")
        XCTAssertTrue(json.contains("refine_task_plan"))
        XCTAssertTrue(json.contains("deepseek_v4_flash"))
    }

    func testRepeatedLocalRefineKeepsStageOrderContiguous() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let dataCenter = LocalDataCenterService(directory: root)
        let repository = LocalTaskRepository(directory: root)
        let eventBus = AppEventBus(dataCenter: dataCenter)
        let service = TaskPlanningService(repository: repository, eventBus: eventBus)
        let task = sampleTask()
        try await repository.save(task)

        let splitOnce = try await service.refinePlan(task, userInstruction: "split smaller")
        let splitTwice = try await service.refinePlan(splitOnce, userInstruction: "split smaller")
        let reduced = try await service.refinePlan(splitTwice, userInstruction: "reduce steps")

        XCTAssertEqual(splitOnce.stages.map(\.order), Array(1...splitOnce.stages.count))
        XCTAssertEqual(splitTwice.stages.map(\.order), Array(1...splitTwice.stages.count))
        XCTAssertEqual(reduced.stages.map(\.order), Array(1...reduced.stages.count))
        XCTAssertEqual(reduced.metadata["planning_mode"], "local_rules")
        XCTAssertNotNil(reduced.metadata["agent_response"])
    }

    func testManualInsertAndDeleteStageKeepsOrderWithoutAgentResponse() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let dataCenter = LocalDataCenterService(directory: root)
        let repository = LocalTaskRepository(directory: root)
        let eventBus = AppEventBus(dataCenter: dataCenter)
        let service = TaskPlanningService(repository: repository, eventBus: eventBus)
        var task = sampleTask()
        task.metadata["agent_response"] = "Old AI response"
        try await repository.save(task)

        let inserted = try await service.insertStage(
            taskId: task.id,
            beforeStageId: task.stages[0].id,
            patch: StagePlanPatch(
                title: "Manual checkpoint",
                instruction: "Write a checkpoint note.",
                completionCriteria: "One checkpoint note exists.",
                stageType: .organizing,
                estimatedSeconds: 180
            )
        )
        let insertedStage = try XCTUnwrap(inserted.stages.first(where: { $0.title == "Manual checkpoint" }))

        XCTAssertEqual(inserted.stages.map(\.order), Array(1...inserted.stages.count))
        XCTAssertEqual(inserted.metadata["last_manual_edit"], "insert_stage")
        XCTAssertNil(inserted.metadata["agent_response"])

        let deleted = try await service.deleteStage(taskId: task.id, stageId: insertedStage.id)
        let json = try await dataCenter.exportEventsJSON()

        XCTAssertEqual(deleted.stages.map(\.order), Array(1...deleted.stages.count))
        XCTAssertFalse(deleted.stages.contains(where: { $0.id == insertedStage.id }))
        XCTAssertEqual(deleted.metadata["last_manual_edit"], "delete_stage")
        XCTAssertTrue(json.contains("manual_insert_stage"))
        XCTAssertTrue(json.contains("manual_delete_stage"))
    }

    func testManualDeleteKeepsAtLeastOneStage() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let dataCenter = LocalDataCenterService(directory: root)
        let repository = LocalTaskRepository(directory: root)
        let eventBus = AppEventBus(dataCenter: dataCenter)
        let service = TaskPlanningService(repository: repository, eventBus: eventBus)
        let task = TaskPlan(
            id: "task_single_stage",
            originalInput: "Read one note for class",
            title: "Read one note",
            taskType: .reading,
            estimatedTotalSeconds: 180,
            stages: [
                StagePlan(
                    id: "stage_single",
                    taskId: "task_single_stage",
                    order: 1,
                    title: "Open the note",
                    instruction: "Open the note.",
                    completionCriteria: "The note is open.",
                    stageType: .startup,
                    estimatedSeconds: 180
                )
            ]
        )
        try await repository.save(task)

        do {
            _ = try await service.deleteStage(taskId: task.id, stageId: "stage_single")
            XCTFail("Expected deleting the only stage to fail.")
        } catch FocusFlowError.invalidState {
            let stored = try await repository.getTask(task.id)
            XCTAssertEqual(stored.stages.count, 1)
        }
    }

    func testDataCenterWritesJsonlAndDeduplicatesEvents() async throws {
        let directory = try temporaryDirectory()
        let dataCenter = LocalDataCenterService(directory: LocalDataDirectory(root: directory))
        let event = LearningEvent(
            id: "evt_test_duplicate",
            eventType: .taskCreated,
            sourceModule: .module1TaskPlanning,
            taskId: "task_test",
            taskTitle: "Read one paper",
            taskType: .reading,
            status: "draft"
        )

        try await dataCenter.recordEvent(event)
        try await dataCenter.recordEvent(event)

        let eventFiles = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("events"), includingPropertiesForKeys: nil)
        let contents = try eventFiles.map { try String(contentsOf: $0) }.joined()
        XCTAssertEqual(contents.components(separatedBy: "evt_test_duplicate").count - 1, 1)
        XCTAssertTrue(contents.contains("\"event_type\":\"taskCreated\"") || contents.contains("\"event_type\" : \"taskCreated\""))
    }

    func testLocalDataCenterEncryptsEventsAndExportsPlainJSON() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let encryption = LocalEncryptionService(keyProvider: StaticLocalEncryptionKeyProvider(seed: "focusflow-encryption-test-key-0001"))
        let dataCenter = LocalDataCenterService(directory: root, encryptionService: encryption)
        await dataCenter.setLocalEncryptionEnabled(true)
        let event = LearningEvent(
            id: "evt_encrypted_storage",
            eventType: .manualCheckIn,
            sourceModule: .module5DataCenter,
            taskId: "task_secure",
            taskTitle: "Read secure notes",
            status: "secure_probe"
        )

        try await dataCenter.recordEvent(event)

        let eventFiles = try FileManager.default.contentsOfDirectory(at: root.events, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }
        let eventFile = try XCTUnwrap(eventFiles.first)
        let rawData = try Data(contentsOf: eventFile)
        let rawText = String(data: rawData, encoding: .utf8) ?? ""
        let json = try await dataCenter.exportEventsJSON()
        let restarted = LocalDataCenterService(directory: root, encryptionService: encryption)
        await restarted.setLocalEncryptionEnabled(true)
        let restartedJSON = try await restarted.exportEventsJSON()

        XCTAssertTrue(LocalEncryptionService.isEncrypted(rawData))
        XCTAssertFalse(rawText.contains("evt_encrypted_storage"))
        XCTAssertTrue(json.contains("evt_encrypted_storage"))
        XCTAssertTrue(restartedJSON.contains("evt_encrypted_storage"))
    }

    func testTaskRepositoryEncryptsTaskFilesWhenEnabled() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let encryption = LocalEncryptionService(keyProvider: StaticLocalEncryptionKeyProvider(seed: "focusflow-plan-encryption-key-0001"))
        let repository = LocalTaskRepository(directory: root, encryptionService: encryption)
        await repository.setLocalEncryptionEnabled(true)
        let stage = StagePlan(
            taskId: "task_encrypted",
            order: 1,
            title: "Open the PDF",
            instruction: "Open the assigned article.",
            completionCriteria: "The PDF is visible.",
            stageType: .reading,
            estimatedSeconds: 180
        )
        let task = TaskPlan(
            id: "task_encrypted",
            originalInput: "Read an article",
            title: "Read an article",
            taskType: .reading,
            estimatedTotalSeconds: 180,
            stages: [stage]
        )

        try await repository.save(task)

        let rawData = try Data(contentsOf: root.tasks.appendingPathComponent("task_encrypted.json"))
        let rawText = String(data: rawData, encoding: .utf8) ?? ""
        let restarted = LocalTaskRepository(directory: root, encryptionService: encryption)
        await restarted.setLocalEncryptionEnabled(true)
        let loaded = try await restarted.getTask("task_encrypted")
        let listed = try await restarted.listTasks()

        XCTAssertTrue(LocalEncryptionService.isEncrypted(rawData))
        XCTAssertFalse(rawText.contains("Read an article"))
        XCTAssertEqual(loaded.title, "Read an article")
        XCTAssertEqual(listed.map(\.id), ["task_encrypted"])
    }

    func testRuntimeStoreEncryptsActiveRuntimeWhenEnabled() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let encryption = LocalEncryptionService(keyProvider: StaticLocalEncryptionKeyProvider(seed: "focusflow-runtime-encryption-key1"))
        let store = LocalRuntimeStore(directory: root, encryptionService: encryption)
        await store.setLocalEncryptionEnabled(true)
        let runtime = StageRuntime(
            taskId: "task_runtime_encrypted",
            stageId: "stage_runtime_encrypted",
            status: .running,
            startedAt: Date(timeIntervalSince1970: 100),
            plannedSeconds: 300,
            lastTickAt: Date(timeIntervalSince1970: 110),
            monotonicAnchor: 42
        )

        try await store.save(runtime)

        let rawData = try Data(contentsOf: root.runtime.appendingPathComponent("active_stage.json"))
        let rawText = String(data: rawData, encoding: .utf8) ?? ""
        let restarted = LocalRuntimeStore(directory: root, encryptionService: encryption)
        await restarted.setLocalEncryptionEnabled(true)
        let loaded = try await restarted.loadActiveRuntime()

        XCTAssertTrue(LocalEncryptionService.isEncrypted(rawData))
        XCTAssertFalse(rawText.contains("task_runtime_encrypted"))
        XCTAssertEqual(loaded, runtime)
    }

    func testFiveModuleLearningLoopRunsEndToEnd() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let dataCenter = LocalDataCenterService(directory: root)
        let repository = LocalTaskRepository(directory: root)
        let runtimeStore = LocalRuntimeStore(directory: root)
        let eventBus = AppEventBus(dataCenter: dataCenter)
        let planning = TaskPlanningService(repository: repository, eventBus: eventBus)
        let execution = ExecutionService(repository: repository, runtimeStore: runtimeStore, eventBus: eventBus)
        let feedback = FeedbackOptimizationService(repository: repository, eventBus: eventBus)
        let closure = TaskClosureService(repository: repository, dataCenter: dataCenter, eventBus: eventBus)

        let draft = try await planning.createDraft(
            from: "Read Smith 2024 paper on neural networks for BIO 101 due Friday",
            agentContext: nil
        )
        let task = try await planning.acceptDraft(draft, clarificationAnswer: nil)
        try await planning.confirmPlan(task)
        try await execution.startTask(task.id)
        let started = try await repository.getTask(task.id)
        let runningStage = try XCTUnwrap(started.stages.first(where: { $0.status == .running }))

        let result = try await execution.completeCurrentStage(trigger: .user)
        let options = try await feedback.prepareFeedbackOptions(taskId: result.taskId, stageId: result.stageId)
        let selected = options.first(where: { $0.intent == .completed }) ?? FeedbackOption(label: "Done enough", emoji: nil, intent: .completed)
        let optimization = try await feedback.submitFeedback(StageFeedback(
            taskId: result.taskId,
            stageId: result.stageId,
            executionResultId: result.id,
            selectedLabel: selected.label,
            voiceTranscript: "Done enough",
            intent: selected.intent,
            skipped: false
        ))
        let summary = try await closure.presentGracefulPause(taskId: task.id, reason: "End-to-end test stop.")
        let review = try XCTUnwrap(summary.reviewItems.first)
        try await closure.markEmotion(summary: summary, emotion: .calm)
        try await closure.submitReview(summary: summary, item: review, confirmed: true)

        let history = try await dataCenter.queryHistory(HistoryQuery(dateRange: .allTime, keyword: task.title))
        let detail = try await dataCenter.getHistoryDetail(taskId: task.id)
        let stats = try await dataCenter.getStats(range: .allTime)
        let profile = try await dataCenter.getUserProfileSnapshot()
        let json = try await dataCenter.exportEventsJSON()

        XCTAssertEqual(runningStage.id, result.stageId)
        XCTAssertNil(optimization.interventionRequest)
        XCTAssertEqual(summary.closureType, .gracefullyPaused)
        XCTAssertFalse(history.isEmpty)
        XCTAssertEqual(detail.completedStageCount, 1)
        XCTAssertGreaterThanOrEqual(stats.completedStageCount, 1)
        XCTAssertGreaterThanOrEqual(profile.confidence, 0)
        XCTAssertTrue(json.contains("\"event_type\":\"taskCreated\"") || json.contains("\"event_type\" : \"taskCreated\""))
        XCTAssertTrue(json.contains("\"event_type\":\"taskPlanConfirmed\"") || json.contains("\"event_type\" : \"taskPlanConfirmed\""))
        XCTAssertTrue(json.contains("\"event_type\":\"stageStarted\"") || json.contains("\"event_type\" : \"stageStarted\""))
        XCTAssertTrue(json.contains("\"event_type\":\"stageCompleted\"") || json.contains("\"event_type\" : \"stageCompleted\""))
        XCTAssertTrue(json.contains("\"event_type\":\"stageFeedbackSubmitted\"") || json.contains("\"event_type\" : \"stageFeedbackSubmitted\""))
        XCTAssertTrue(json.contains("\"event_type\":\"taskGracefullyPaused\"") || json.contains("\"event_type\" : \"taskGracefullyPaused\""))
        XCTAssertTrue(json.contains("\"event_type\":\"emotionMarked\"") || json.contains("\"event_type\" : \"emotionMarked\""))
        XCTAssertTrue(json.contains("\"event_type\":\"reviewSubmitted\"") || json.contains("\"event_type\" : \"reviewSubmitted\""))
    }

    func testExecutionPauseTimeDoesNotCountAsFocus() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let dataCenter = LocalDataCenterService(directory: root)
        let repository = LocalTaskRepository(directory: root)
        let runtimeStore = LocalRuntimeStore(directory: root)
        let eventBus = AppEventBus(dataCenter: dataCenter)
        let service = ExecutionService(repository: repository, runtimeStore: runtimeStore, eventBus: eventBus)

        let task = sampleTask()
        try await repository.save(task)
        let started = Date().addingTimeInterval(-120)
        let runtime = StageRuntime(
            taskId: task.id,
            stageId: task.stages[0].id,
            status: .paused,
            startedAt: started,
            pauseStartedAt: Date().addingTimeInterval(-60),
            pauseTotalSeconds: 30,
            plannedSeconds: 300,
            pauseCount: 1
        )
        try await runtimeStore.save(runtime)
        let result = try await service.completeCurrentStage(trigger: .user)

        XCTAssertLessThan(result.actualFocusSeconds, 100)
        XCTAssertGreaterThanOrEqual(result.pauseTotalSeconds, 90)
    }

    func testTimeoutDifficultyPublishesTimeoutPromptEvent() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let dataCenter = LocalDataCenterService(directory: root)
        let repository = LocalTaskRepository(directory: root)
        let runtimeStore = LocalRuntimeStore(directory: root)
        let eventBus = AppEventBus(dataCenter: dataCenter)
        let service = ExecutionService(repository: repository, runtimeStore: runtimeStore, eventBus: eventBus)
        let task = sampleTask()
        try await repository.save(task)
        try await runtimeStore.save(StageRuntime(
            taskId: task.id,
            stageId: task.stages[0].id,
            status: .running,
            startedAt: Date().addingTimeInterval(-360),
            pauseStartedAt: nil,
            pauseTotalSeconds: 0,
            plannedSeconds: 300
        ))

        let request = try await service.requestDifficulty(trigger: .timeoutNoAction)
        let runtime = try await runtimeStore.loadActiveRuntime()
        let json = try await dataCenter.exportEventsJSON()

        XCTAssertEqual(request.trigger, .timeoutNoAction)
        XCTAssertEqual(runtime?.timeoutPrompted, true)
        XCTAssertTrue(json.contains("\"event_type\":\"stageTimeoutPrompted\"") || json.contains("\"event_type\" : \"stageTimeoutPrompted\""))
        XCTAssertTrue(json.contains("\"trigger\":\"timeoutNoAction\"") || json.contains("\"trigger\" : \"timeoutNoAction\""))
    }

    func testTooHardFeedbackCreatesStageUpdate() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let dataCenter = LocalDataCenterService(directory: root)
        let repository = LocalTaskRepository(directory: root)
        let eventBus = AppEventBus(dataCenter: dataCenter)
        let service = FeedbackOptimizationService(repository: repository, eventBus: eventBus)
        let task = sampleTask()
        try await repository.save(task)

        let feedback = StageFeedback(
            taskId: task.id,
            stageId: task.stages[0].id,
            executionResultId: "result_test",
            selectedLabel: "Too big",
            intent: .tooHard,
            difficulty: .hard,
            granularity: .tooLarge
        )
        let result = try await service.submitFeedback(feedback)

        XCTAssertNotNil(result.stageUpdate)
        XCTAssertEqual(result.stageUpdate?.updateScope, .currentStageOnly)
        XCTAssertEqual(result.stageUpdate?.updatedStages.count, 2)
        XCTAssertEqual(result.stageUpdate?.requiresUserConfirmation, true)
    }

    func testNeedBreakFeedbackOnlyInsertsBreakBeforeUnchangedRemainingStages() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let dataCenter = LocalDataCenterService(directory: root)
        let repository = LocalTaskRepository(directory: root)
        let eventBus = AppEventBus(dataCenter: dataCenter)
        let service = FeedbackOptimizationService(repository: repository, eventBus: eventBus)
        let task = multiStageTask()
        try await repository.save(task)

        let feedback = StageFeedback(
            taskId: task.id,
            stageId: task.stages[0].id,
            executionResultId: "result_need_break",
            selectedLabel: "Need a break",
            intent: .needBreak
        )
        let result = try await service.submitFeedback(feedback)

        let update = try XCTUnwrap(result.stageUpdate)
        XCTAssertEqual(update.updateScope, .remainingStages)
        XCTAssertEqual(update.updatedStages.count, 3)
        XCTAssertEqual(update.updatedStages[0].stageType, .breakTime)
        XCTAssertEqual(update.updatedStages[1].title, task.stages[1].title)
        XCTAssertEqual(update.updatedStages[2].title, task.stages[2].title)
        XCTAssertEqual(update.removedStageIds, [task.stages[1].id, task.stages[2].id])

        let execution = ExecutionService(
            repository: repository,
            runtimeStore: LocalRuntimeStore(directory: root),
            eventBus: eventBus
        )
        try await execution.applyStageUpdate(update)
        let updatedTask = try await repository.getTask(task.id)

        XCTAssertEqual(updatedTask.stages.map(\.title), [
            task.stages[0].title,
            update.updatedStages[0].title,
            task.stages[1].title,
            task.stages[2].title
        ])
    }

    func testNeedBreakLLMCanChooseBreakTimeButCannotRewriteRemainingStages() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let dataCenter = LocalDataCenterService(directory: root)
        let repository = LocalTaskRepository(directory: root)
        let eventBus = AppEventBus(dataCenter: dataCenter)
        let service = FeedbackOptimizationService(
            repository: repository,
            eventBus: eventBus,
            optimizationAgent: PlanOptimizationAgent(llmClient: FakeLLMClient(response: """
            {
              "shouldUpdate": true,
              "updateScope": "remainingStages",
              "reason": "Take a reset before continuing.",
              "updatedStages": [
                {
                  "title": "Four-minute reset",
                  "instruction": "Drink water and rest your eyes.",
                  "completionCriteria": "Four minutes have passed.",
                  "stageType": "breakTime",
                  "estimatedSeconds": 240
                },
                {
                  "title": "Rewritten next stage that should be ignored",
                  "instruction": "This should not replace the real plan.",
                  "completionCriteria": "Ignored.",
                  "stageType": "writing",
                  "estimatedSeconds": 600
                }
              ]
            }
            """))
        )
        let task = multiStageTask()
        try await repository.save(task)

        let feedback = StageFeedback(
            taskId: task.id,
            stageId: task.stages[0].id,
            executionResultId: "result_need_break_llm",
            selectedLabel: "Need a break",
            intent: .needBreak
        )
        let result = try await service.submitFeedback(feedback)

        let update = try XCTUnwrap(result.stageUpdate)
        XCTAssertEqual(update.updatedStages.count, 3)
        XCTAssertEqual(update.updatedStages[0].title, "Four-minute reset")
        XCTAssertEqual(update.updatedStages[0].estimatedSeconds, 240)
        XCTAssertEqual(update.updatedStages[1].title, task.stages[1].title)
        XCTAssertEqual(update.updatedStages[2].title, task.stages[2].title)
        XCTAssertFalse(update.updatedStages.map(\.title).contains("Rewritten next stage that should be ignored"))
    }

    func testFeedbackOptimizationRecordsAgentRunEvents() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let dataCenter = LocalDataCenterService(directory: root)
        let repository = LocalTaskRepository(directory: root)
        let eventBus = AppEventBus(dataCenter: dataCenter)
        let service = FeedbackOptimizationService(repository: repository, eventBus: eventBus)
        let task = sampleTask()
        try await repository.save(task)

        let feedback = StageFeedback(
            taskId: task.id,
            stageId: task.stages[0].id,
            executionResultId: "result_agent_log",
            selectedLabel: "Too big",
            intent: .tooHard,
            difficulty: .hard,
            granularity: .tooLarge
        )
        _ = try await service.submitFeedback(feedback)
        let json = try await dataCenter.exportEventsJSON()

        XCTAssertTrue(json.contains("\"event_type\":\"agentRunStarted\"") || json.contains("\"event_type\" : \"agentRunStarted\""))
        XCTAssertTrue(json.contains("\"event_type\":\"agentRunCompleted\"") || json.contains("\"event_type\" : \"agentRunCompleted\""))
        XCTAssertTrue(json.contains("PlanOptimizationAgent"))
        XCTAssertTrue(json.contains("optimize_after_stage_feedback"))
        XCTAssertTrue(json.contains("stage_update=true"))
    }

    func testExecutionCanUndoAppliedStageUpdate() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let dataCenter = LocalDataCenterService(directory: root)
        let repository = LocalTaskRepository(directory: root)
        let runtimeStore = LocalRuntimeStore(directory: root)
        let eventBus = AppEventBus(dataCenter: dataCenter)
        let service = ExecutionService(repository: repository, runtimeStore: runtimeStore, eventBus: eventBus)
        let task = sampleTask()
        try await repository.save(task)
        let replacement = StagePlan(
            taskId: task.id,
            order: 1,
            title: "Tiny replacement",
            instruction: "Do a smaller reading action.",
            completionCriteria: "One smaller action is visible.",
            stageType: .reading,
            estimatedSeconds: 180,
            status: .adjusted,
            createdBy: .module3FeedbackOptimization,
            parentStageId: task.stages[0].id
        )
        let update = StageUpdate(
            taskId: task.id,
            sourceStageId: task.stages[0].id,
            updateScope: .currentStageOnly,
            updatedStages: [replacement],
            removedStageIds: [task.stages[0].id],
            reason: "Make the step smaller.",
            requiresUserConfirmation: true
        )

        try await service.applyStageUpdate(update)
        let adjusted = try await repository.getTask(task.id)
        XCTAssertEqual(adjusted.stages.first?.title, "Tiny replacement")

        try await service.revertStageUpdate(previousTask: task, update: update)
        let reverted = try await repository.getTask(task.id)
        let json = try await dataCenter.exportEventsJSON()

        XCTAssertEqual(reverted.stages.first?.title, task.stages.first?.title)
        XCTAssertTrue(json.contains("\"instruction\":\"undo_stage_update\"") || json.contains("\"instruction\" : \"undo_stage_update\""))
        XCTAssertTrue(json.contains(update.id))
    }

    func testSkippedFeedbackRecordsEventWithoutStageUpdate() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let dataCenter = LocalDataCenterService(directory: root)
        let repository = LocalTaskRepository(directory: root)
        let eventBus = AppEventBus(dataCenter: dataCenter)
        let service = FeedbackOptimizationService(repository: repository, eventBus: eventBus)
        let task = sampleTask()
        try await repository.save(task)

        let feedback = StageFeedback(
            taskId: task.id,
            stageId: task.stages[0].id,
            executionResultId: "result_skip_feedback",
            selectedLabel: "Skipped feedback",
            intent: .skippedFeedback,
            skipped: true
        )
        let result = try await service.submitFeedback(feedback)
        let json = try await dataCenter.exportEventsJSON()

        XCTAssertNil(result.stageUpdate)
        XCTAssertTrue(json.contains("skipped_feedback"))
        XCTAssertTrue(json.contains("\"skipped\":\"true\"") || json.contains("\"skipped\" : \"true\""))
    }

    func testWantToQuitFeedbackCreatesHighUrgencyIntervention() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let dataCenter = LocalDataCenterService(directory: root)
        let repository = LocalTaskRepository(directory: root)
        let eventBus = AppEventBus(dataCenter: dataCenter)
        let service = FeedbackOptimizationService(repository: repository, eventBus: eventBus)
        let task = sampleTask()
        try await repository.save(task)

        let feedback = StageFeedback(
            taskId: task.id,
            stageId: task.stages[0].id,
            executionResultId: "result_quit_feedback",
            selectedLabel: "Stop here",
            intent: .wantToQuit,
            emotionTag: .overwhelmed
        )
        let result = try await service.submitFeedback(feedback)
        let json = try await dataCenter.exportEventsJSON()

        XCTAssertNil(result.stageUpdate)
        XCTAssertEqual(result.interventionRequest?.interruptionType, .activeQuit)
        XCTAssertEqual(result.interventionRequest?.urgency, .high)
        XCTAssertTrue(json.contains("\"event_type\":\"interventionTriggered\"") || json.contains("\"event_type\" : \"interventionTriggered\""))
        XCTAssertTrue(json.contains("\"type\":\"activeQuit\"") || json.contains("\"type\" : \"activeQuit\""))
    }

    func testTaskBreakdownCanDecodeLLMPlan() async throws {
        let agent = TaskBreakdownAgent(llmClient: FakeLLMClient(response: """
        {
          "title": "Prepare biology presentation",
          "task_type": "presentation",
          "confidence": 0.91,
          "clarification_questions": [],
          "stages": [
            {
              "title": "Open the brief",
              "instruction": "Open the course page and find the presentation requirements.",
              "completion_criteria": "The brief is visible.",
              "stage_type": "startup",
              "estimated_seconds": 240
            },
            {
              "title": "Create slides",
              "instruction": "Create a slide file and write the working title.",
              "completion_criteria": "A slide file exists with a title.",
              "stage_type": "presentationMaking",
              "estimated_seconds": 420
            }
          ]
        }
        """))

        let draft = await agent.makeDraftUsingLLM(from: TaskInputRequest(
            rawInput: "I need to prepare a biology presentation",
            userProfileSnapshot: .empty
        ))

        XCTAssertEqual(draft.task.metadata["planning_mode"], "deepseek_v4_flash")
        XCTAssertEqual(draft.task.taskType, .presentation)
        XCTAssertEqual(draft.task.stages.count, 2)
        XCTAssertLessThanOrEqual(draft.task.stages[0].estimatedSeconds, 300)
    }

    func testTaskBreakdownPromptIncludesAgentContextNotes() async throws {
        let recorder = LLMMessageRecorder(response: """
        {
          "title": "Plan essay",
          "task_type": "writing",
          "confidence": 0.82,
          "clarification_questions": [],
          "stages": [
            {
              "title": "Open document",
              "instruction": "Open the essay document and place the cursor at the next blank line.",
              "completion_criteria": "The document is open.",
              "stage_type": "startup",
              "estimated_seconds": 180
            }
          ]
        }
        """)
        let agent = TaskBreakdownAgent(llmClient: recorder)
        let context = AgentContext(
            userProfileSnapshot: UserProfileSnapshot(preferredStageDurationSeconds: 420, confidence: 0.5),
            recentStatsSummary: StatsSummary(
                range: .last7Days,
                activeDays: 2,
                strictStreakDays: 1,
                gentleRhythmText: "You returned twice.",
                totalFocusSeconds: 900,
                completedStageCount: 3,
                stageCompletionRate: nil,
                taskCompletionRate: nil,
                recoveryCount: 0
            ),
            recentSimilarTaskNotes: ["writing: 2 completed steps, 12 focus minutes, latest status completed."],
            privacyMode: .remoteLLMAllowedForCurrentContext
        )

        _ = await agent.makeDraftUsingLLM(from: TaskInputRequest(
            rawInput: "Write my history essay",
            userProfileSnapshot: context.userProfileSnapshot,
            agentContext: context
        ))
        let prompt = await recorder.lastUserMessage()

        XCTAssertTrue(prompt.contains("active_days=2"))
        XCTAssertTrue(prompt.contains("completed_stage_count=3"))
        XCTAssertTrue(prompt.contains("writing: 2 completed steps"))
    }

    func testFeedbackAgentCanDecodeLLMOptions() async throws {
        let agent = FeedbackAgent(llmClient: FakeLLMClient(response: """
        {
          "options": [
            {"label": "Done", "emoji": "✅", "intent": "completed"},
            {"label": "Too dense", "emoji": "🔍", "intent": "tooHard"},
            {"label": "Need time", "emoji": "⏱", "intent": "needMoreTime"}
          ]
        }
        """))
        let task = sampleTask()
        let options = await agent.optionsUsingLLM(for: task, stage: task.stages[0])

        XCTAssertEqual(options.count, 3)
        XCTAssertEqual(options[1].intent, .tooHard)
    }

    func testPrivacyGatedLLMClientBlocksRemoteCallsWhenDisabled() async throws {
        let recorder = LLMCallRecorder()
        let gate = RemoteAgentGate(enabled: false)
        let client = PrivacyGatedLLMClient(base: CountingLLMClient(recorder: recorder), gate: gate)

        do {
            _ = try await client.complete(
                messages: [LLMMessage(role: "user", content: "hello")],
                privacyMode: .remoteLLMAllowedForCurrentContext,
                responseFormat: nil
            )
            XCTFail("Disabled remote gate should reject LLM calls.")
        } catch {
            let blockedCount = await recorder.value()
            XCTAssertEqual(blockedCount, 0)
        }

        await gate.setEnabled(true)
        let response = try await client.complete(
            messages: [LLMMessage(role: "user", content: "hello")],
            privacyMode: .remoteLLMAllowedForCurrentContext,
            responseFormat: nil
        )

        XCTAssertEqual(response, "{\"ok\":true}")
        let allowedCount = await recorder.value()
        XCTAssertEqual(allowedCount, 1)
    }

    func testSettingsPersistToLocalJson() async throws {
        let directory = try temporaryDirectory()
        let service = LocalSettingsService(directory: LocalDataDirectory(root: directory))
        var settings = FocusFlowSettings.defaults
        settings.notificationsEnabled = false
        settings.floatingTimerOpacity = 0.62
        settings.floatingTimerOriginX = 1440.5
        settings.floatingTimerOriginY = 820.0
        settings.voiceIdentifier = "com.apple.voice.compact.en-US.Samantha"
        settings.globalShortcutsEnabled = false
        settings.shortcutKeys = FocusFlowShortcutSettings(
            pauseResume: "R",
            skip: "K",
            voiceInput: "V",
            markDistraction: "X",
            help: "Y"
        )
        settings.remoteAgentEnabled = false
        settings.localEncryptionEnabled = true

        try await service.saveSettings(settings)
        let loaded = try await service.loadSettings()

        XCTAssertEqual(loaded.notificationsEnabled, false)
        XCTAssertEqual(loaded.floatingTimerOpacity, 0.62)
        XCTAssertEqual(loaded.floatingTimerOriginX, 1440.5)
        XCTAssertEqual(loaded.floatingTimerOriginY, 820.0)
        XCTAssertEqual(loaded.voiceIdentifier, "com.apple.voice.compact.en-US.Samantha")
        XCTAssertEqual(loaded.globalShortcutsEnabled, false)
        XCTAssertEqual(loaded.shortcutKeys.pauseResume, "R")
        XCTAssertEqual(loaded.shortcutKeys.skip, "K")
        XCTAssertEqual(loaded.shortcutKeys.voiceInput, "V")
        XCTAssertEqual(loaded.shortcutKeys.markDistraction, "X")
        XCTAssertEqual(loaded.shortcutKeys.help, "Y")
        XCTAssertEqual(loaded.remoteAgentEnabled, false)
        XCTAssertEqual(loaded.localEncryptionEnabled, true)
    }

    func testSettingsDecodeLegacyFileWithDefaultShortcuts() throws {
        let json = """
        {
          "notifications_enabled": false,
          "floating_timer_opacity": 0.7,
          "voice_prompts_enabled": true,
          "global_shortcuts_enabled": true,
          "profile_learning_enabled": true,
          "remote_agent_enabled": false,
          "local_encryption_enabled": false,
          "privacy_mode": "localOnly"
        }
        """

        let loaded = try FocusFlowJSON.decoder.decode(FocusFlowSettings.self, from: Data(json.utf8))

        XCTAssertEqual(loaded.notificationsEnabled, false)
        XCTAssertEqual(loaded.floatingTimerOpacity, 0.7)
        XCTAssertEqual(loaded.shortcutKeys, .defaults)
        XCTAssertEqual(loaded.privacyMode, .localOnly)
        XCTAssertEqual(loaded.localEncryptionEnabled, false)
    }

    func testSettingsDefaultLocalEncryptionEnabledWhenFieldIsMissing() throws {
        let json = """
        {
          "notifications_enabled": true,
          "floating_timer_opacity": 0.85,
          "profile_learning_enabled": true,
          "remote_agent_enabled": true,
          "privacy_mode": "remoteLLMAllowedForCurrentContext"
        }
        """

        let loaded = try FocusFlowJSON.decoder.decode(FocusFlowSettings.self, from: Data(json.utf8))

        XCTAssertFalse(FocusFlowSettings.defaults.localEncryptionEnabled)
        XCTAssertFalse(loaded.localEncryptionEnabled)
    }

    func testAppReadinessReportFlagsRequiredAndOptionalCapabilities() throws {
        let service = AppReadinessService()
        var settings = FocusFlowSettings.defaults
        settings.remoteAgentEnabled = true
        settings.notificationsEnabled = true
        settings.voiceInputEnabled = true
        settings.voicePromptsEnabled = true
        settings.globalShortcutsEnabled = true
        settings.localEncryptionEnabled = true

        let report = service.report(for: AppReadinessInputs(
            settings: settings,
            hasDeepSeekAPIKey: false,
            notificationAuthorized: false,
            dataDirectoryWritable: true,
            hotKeyFailedRegistrationCount: 1,
            englishVoiceAvailable: true,
            speechRecognitionAvailable: false
        ), generatedAt: Date(timeIntervalSince1970: 1))

        XCTAssertTrue(report.isPrototypeReady)
        XCTAssertEqual(report.requiredAttentionCount, 0)
        XCTAssertGreaterThanOrEqual(report.attentionCount, 4)
        XCTAssertEqual(report.items.first(where: { $0.id == "local_data" })?.state, .ready)
        XCTAssertEqual(report.items.first(where: { $0.id == "deepseek" })?.state, .needsAttention)
        XCTAssertEqual(report.items.first(where: { $0.id == "local_encryption" })?.state, .off)
        XCTAssertEqual(report.items.first(where: { $0.id == "notifications" })?.state, .needsAttention)
        XCTAssertEqual(report.items.first(where: { $0.id == "shortcuts" })?.state, .needsAttention)
        XCTAssertEqual(report.items.first(where: { $0.id == "voice_input" })?.state, .needsAttention)
    }

    func testAppReadinessReportBlocksWhenRequiredLocalSystemsFail() throws {
        let service = AppReadinessService()
        var settings = FocusFlowSettings.defaults
        settings.remoteAgentEnabled = false
        settings.notificationsEnabled = false
        settings.profileLearningEnabled = false
        settings.globalShortcutsEnabled = false
        settings.localEncryptionEnabled = false

        let report = service.report(for: AppReadinessInputs(
            settings: settings,
            hasDeepSeekAPIKey: false,
            notificationAuthorized: nil,
            dataDirectoryWritable: false,
            hotKeyFailedRegistrationCount: 0,
            englishVoiceAvailable: true,
            speechRecognitionAvailable: true
        ), generatedAt: Date(timeIntervalSince1970: 2))

        XCTAssertFalse(report.isPrototypeReady)
        XCTAssertEqual(report.requiredAttentionCount, 1)
        XCTAssertEqual(report.items.first(where: { $0.id == "local_data" })?.state, .needsAttention)
        XCTAssertEqual(report.items.first(where: { $0.id == "floating_timer" })?.state, .ready)
        XCTAssertEqual(report.items.first(where: { $0.id == "deepseek" })?.state, .off)
        XCTAssertEqual(report.items.first(where: { $0.id == "notifications" })?.state, .off)
        XCTAssertEqual(report.items.first(where: { $0.id == "profile_learning" })?.state, .off)
        XCTAssertEqual(report.items.first(where: { $0.id == "local_encryption" })?.state, .off)
        XCTAssertTrue(report.summaryText.contains("required"))
    }

    func testShortcutSettingsNormalizeKeysAndDetectDuplicates() {
        let shortcuts = FocusFlowShortcutSettings(
            pauseResume: "r",
            skip: "r",
            voiceInput: "!",
            markDistraction: "x",
            help: "help"
        )

        XCTAssertEqual(shortcuts.pauseResume, "R")
        XCTAssertEqual(shortcuts.skip, "R")
        XCTAssertEqual(shortcuts.voiceInput, "M")
        XCTAssertEqual(shortcuts.markDistraction, "X")
        XCTAssertEqual(shortcuts.help, "H")
        XCTAssertEqual(shortcuts.duplicateKeys, ["R"])
    }

    func testVoiceCommandParserMapsCommonPhrases() {
        XCTAssertEqual(VoiceCommandParser.parse("I finished this step"), .complete)
        XCTAssertEqual(VoiceCommandParser.parse("I'm stuck, help me"), .help)
        XCTAssertEqual(VoiceCommandParser.parse("I need a break"), .shortBreak)
        XCTAssertEqual(VoiceCommandParser.parse("This is too hard"), .tooHard)
        XCTAssertEqual(VoiceCommandParser.parse("I need more time"), .moreTime)
        XCTAssertEqual(VoiceCommandParser.parse("I got distracted"), .distracted)
        XCTAssertEqual(VoiceCommandParser.parse("skip this one"), .skip)
        XCTAssertEqual(VoiceCommandParser.parse("continue to the next step"), .continueNext)
        XCTAssertEqual(VoiceCommandParser.parse("pause please"), .pauseOrResume)
        XCTAssertEqual(VoiceCommandParser.parse("I want to stop task"), .stopTask)
        XCTAssertNil(VoiceCommandParser.parse("I am thinking about the article"))
    }

    func testNotificationFallbackMessageNamesFloatingTimer() {
        XCTAssertEqual(
            NotificationFallbackPolicy.floatingTimerMessage(stageTitle: "Read the abstract"),
            "System notifications are unavailable. The floating timer will keep Read the abstract visible."
        )
        XCTAssertEqual(
            NotificationFallbackPolicy.floatingTimerMessage(stageTitle: "  "),
            "System notifications are unavailable. The floating timer will keep the current stage visible."
        )
    }

    func testCorruptSettingsFileFallsBackAndIsQuarantined() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        try root.prepare()
        let settingsURL = root.settings.appendingPathComponent("privacy.json")
        try "{not json".write(to: settingsURL, atomically: true, encoding: .utf8)
        let service = LocalSettingsService(directory: root)

        let loaded = try await service.loadSettings()

        XCTAssertEqual(loaded, .defaults)
        XCTAssertFalse(FileManager.default.fileExists(atPath: settingsURL.path))
        XCTAssertTrue(try hasQuarantinedFile(named: "privacy.json", under: directory))
    }

    func testCorruptRuntimeReturnsNilAndIsQuarantined() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        try root.prepare()
        let runtimeURL = root.runtime.appendingPathComponent("active_stage.json")
        try "broken runtime".write(to: runtimeURL, atomically: true, encoding: .utf8)
        let store = LocalRuntimeStore(directory: root)

        let runtime = try await store.loadActiveRuntime()

        XCTAssertNil(runtime)
        XCTAssertFalse(FileManager.default.fileExists(atPath: runtimeURL.path))
        XCTAssertTrue(try hasQuarantinedFile(named: "active_stage.json", under: directory))
    }

    func testCorruptTaskFileIsSkippedAndQuarantined() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let repository = LocalTaskRepository(directory: root)
        let valid = sampleTask()
        try await repository.save(valid)
        try "not a task".write(
            to: root.tasks.appendingPathComponent("task_broken.json"),
            atomically: true,
            encoding: .utf8
        )

        let tasks = try await repository.listTasks()

        XCTAssertEqual(tasks.map(\.id), [valid.id])
        XCTAssertTrue(try hasQuarantinedFile(named: "task_broken.json", under: directory))
    }

    func testCorruptProfileAndAchievementsFallBack() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        try root.prepare()
        try "bad profile".write(to: root.profile.appendingPathComponent("user_profile.json"), atomically: true, encoding: .utf8)
        try "bad achievements".write(to: root.achievements.appendingPathComponent("unlocked.json"), atomically: true, encoding: .utf8)
        let dataCenter = LocalDataCenterService(directory: root)

        let profile = try await dataCenter.getUserProfileSnapshot()
        let achievements = try await dataCenter.getUnlockedAchievements()

        XCTAssertEqual(profile, .empty)
        XCTAssertTrue(achievements.isEmpty)
        XCTAssertTrue(try hasQuarantinedFile(named: "user_profile.json", under: directory))
        XCTAssertTrue(try hasQuarantinedFile(named: "unlocked.json", under: directory))
    }

    func testLocalDataDirectoryCanUseEnvironmentRoot() throws {
        let directory = try temporaryDirectory()
        setenv("FOCUSFLOW_DATA_ROOT", directory.path, 1)
        defer { unsetenv("FOCUSFLOW_DATA_ROOT") }

        let root = LocalDataDirectory()

        XCTAssertEqual(root.root.path, directory.path)
    }

    func testAchievementsUnlockAndQueueAfterEvents() async throws {
        let directory = try temporaryDirectory()
        let dataCenter = LocalDataCenterService(directory: LocalDataDirectory(root: directory))

        try await dataCenter.recordEvent(LearningEvent(
            eventType: .taskCreated,
            sourceModule: .module1TaskPlanning,
            taskId: "task_achievement",
            taskTitle: "Read a chapter",
            taskType: .reading
        ))

        let unlocked = try await dataCenter.getUnlockedAchievements()
        let pending = try await dataCenter.getPendingAchievements()
        XCTAssertTrue(unlocked.contains { $0.id == "tiny_start" })
        XCTAssertTrue(pending.contains { $0.id == "tiny_start" })

        try await dataCenter.markAchievementDisplayed("tiny_start")
        let afterDismiss = try await dataCenter.getPendingAchievements()
        XCTAssertFalse(afterDismiss.contains { $0.id == "tiny_start" })
    }

    func testDataExportsJsonAndCSV() async throws {
        let directory = try temporaryDirectory()
        let dataCenter = LocalDataCenterService(directory: LocalDataDirectory(root: directory))
        try await dataCenter.recordEvent(LearningEvent(
            eventType: .stageCompleted,
            sourceModule: .module2Execution,
            taskId: "task_export",
            stageId: "stage_export",
            taskTitle: "Read, then note",
            taskType: .reading,
            stageTitle: "Read abstract",
            stageType: .reading,
            status: "completed",
            actualFocusSeconds: 300
        ))

        let json = try await dataCenter.exportEventsJSON()
        let csv = try await dataCenter.exportEventsCSV()

        XCTAssertTrue(json.contains("task_export"))
        XCTAssertTrue(csv.contains("event_type"))
        XCTAssertTrue(csv.contains("\"Read, then note\""))
    }

    func testDailyStatsIncludesEmptyDaysAndAggregatesFocus() async throws {
        let directory = try temporaryDirectory()
        let dataCenter = LocalDataCenterService(directory: LocalDataDirectory(root: directory))
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let todayKey = FocusFlowCalendar.localDay(for: today, calendar: calendar)
        let yesterdayKey = FocusFlowCalendar.localDay(for: yesterday, calendar: calendar)

        try await dataCenter.recordEvent(LearningEvent(
            eventType: .stageCompleted,
            sourceModule: .module2Execution,
            timestamp: yesterday,
            localDay: yesterdayKey,
            taskId: "task_daily_stats",
            stageId: "stage_yesterday",
            taskTitle: "Daily stats",
            taskType: .reading,
            status: "completed",
            actualFocusSeconds: 900
        ))
        try await dataCenter.recordEvent(LearningEvent(
            eventType: .stageResumed,
            sourceModule: .module2Execution,
            timestamp: yesterday.addingTimeInterval(60),
            localDay: yesterdayKey,
            taskId: "task_daily_stats",
            stageId: "stage_yesterday",
            taskTitle: "Daily stats",
            taskType: .reading,
            status: "running"
        ))
        try await dataCenter.recordEvent(LearningEvent(
            eventType: .stageCompleted,
            sourceModule: .module2Execution,
            timestamp: today,
            localDay: todayKey,
            taskId: "task_daily_stats",
            stageId: "stage_today",
            taskTitle: "Daily stats",
            taskType: .reading,
            status: "completed",
            actualFocusSeconds: 300
        ))

        let points = try await dataCenter.getDailyStats(range: .last7Days)
        let yesterdayPoint = try XCTUnwrap(points.first { $0.localDay == yesterdayKey })
        let todayPoint = try XCTUnwrap(points.first { $0.localDay == todayKey })

        XCTAssertEqual(points.count, 7)
        XCTAssertEqual(yesterdayPoint.focusSeconds, 900)
        XCTAssertEqual(yesterdayPoint.completedStageCount, 1)
        XCTAssertEqual(yesterdayPoint.recoveryCount, 1)
        XCTAssertEqual(todayPoint.focusSeconds, 300)
        XCTAssertTrue(points.contains { $0.focusSeconds == 0 && $0.completedStageCount == 0 })
    }

    func testDataCenterHandlesLongitudinalLocalHistoryAtPrototypeScale() async throws {
        let directory = try temporaryDirectory()
        let dataCenter = LocalDataCenterService(directory: LocalDataDirectory(root: directory))
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let firstDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -119, to: today))
        let stageTypes: [StageType] = [.startup, .reading, .writing]
        let focusSeconds = [300, 360, 420]
        let ingestionStartedAt = Date()

        for dayIndex in 0..<120 {
            let day = try XCTUnwrap(calendar.date(byAdding: .day, value: dayIndex, to: firstDay))
            let localDay = FocusFlowCalendar.localDay(for: day, calendar: calendar)
            let taskId = "task_long_\(dayIndex)"
            let taskType: EducationTaskType = dayIndex.isMultiple(of: 2) ? .reading : .writing
            let title = taskType == .reading ? "Read research paper \(dayIndex)" : "Write study notes \(dayIndex)"

            try await dataCenter.recordEvent(LearningEvent(
                id: "evt_long_task_created_\(dayIndex)",
                eventType: .taskCreated,
                sourceModule: .module1TaskPlanning,
                timestamp: day,
                localDay: localDay,
                taskId: taskId,
                taskTitle: title,
                taskType: taskType,
                status: "planned"
            ))

            for stageIndex in 0..<3 {
                let timestamp = day.addingTimeInterval(TimeInterval(600 + stageIndex * 900))
                try await dataCenter.recordEvent(LearningEvent(
                    id: "evt_long_stage_completed_\(dayIndex)_\(stageIndex)",
                    eventType: .stageCompleted,
                    sourceModule: .module2Execution,
                    timestamp: timestamp,
                    localDay: localDay,
                    taskId: taskId,
                    stageId: "stage_long_\(dayIndex)_\(stageIndex)",
                    taskTitle: title,
                    taskType: taskType,
                    stageTitle: "Stage \(stageIndex + 1)",
                    stageType: stageTypes[stageIndex],
                    status: "completed",
                    plannedDurationSeconds: focusSeconds[stageIndex],
                    actualFocusSeconds: focusSeconds[stageIndex],
                    pauseCount: stageIndex == 1 && dayIndex.isMultiple(of: 3) ? 1 : 0
                ))
            }

            if dayIndex.isMultiple(of: 3) {
                try await dataCenter.recordEvent(LearningEvent(
                    id: "evt_long_resumed_\(dayIndex)",
                    eventType: .stageResumed,
                    sourceModule: .module2Execution,
                    timestamp: day.addingTimeInterval(3_600),
                    localDay: localDay,
                    taskId: taskId,
                    stageId: "stage_long_\(dayIndex)_1",
                    taskTitle: title,
                    taskType: taskType,
                    stageTitle: "Stage 2",
                    stageType: .reading,
                    status: "running"
                ))
            }

            if dayIndex.isMultiple(of: 5) {
                try await dataCenter.recordEvent(LearningEvent(
                    id: "evt_long_feedback_\(dayIndex)",
                    eventType: .stageFeedbackSubmitted,
                    sourceModule: .module3FeedbackOptimization,
                    timestamp: day.addingTimeInterval(4_200),
                    localDay: localDay,
                    taskId: taskId,
                    stageId: "stage_long_\(dayIndex)_2",
                    taskTitle: title,
                    taskType: taskType,
                    stageTitle: "Stage 3",
                    stageType: .writing,
                    status: "distracted",
                    tags: ["feedback", "distraction"],
                    metadata: ["intent": FeedbackIntent.distracted.rawValue]
                ))
            }

            if dayIndex.isMultiple(of: 2) {
                try await dataCenter.recordEvent(LearningEvent(
                    id: "evt_long_task_completed_\(dayIndex)",
                    eventType: .taskCompleted,
                    sourceModule: .module4ClosureEmotion,
                    timestamp: day.addingTimeInterval(5_400),
                    localDay: localDay,
                    taskId: taskId,
                    taskTitle: title,
                    taskType: taskType,
                    status: "completed",
                    actualFocusSeconds: 0
                ))
            }
        }

        let ingestionSeconds = Date().timeIntervalSince(ingestionStartedAt)
        let queryStartedAt = Date()
        let stats = try await dataCenter.getStats(range: .allTime)
        let daily = try await dataCenter.getDailyStats(range: .last30Days)
        let history = try await dataCenter.queryHistory(HistoryQuery(dateRange: .allTime))
        let detail = try await dataCenter.getHistoryDetail(taskId: "task_long_0")
        let csv = try await dataCenter.exportEventsCSV()
        let profile = try await dataCenter.getUserProfileSnapshot()
        let achievements = try await dataCenter.getUnlockedAchievements()
        let querySeconds = Date().timeIntervalSince(queryStartedAt)
        let eventFiles = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("events"), includingPropertiesForKeys: nil)

        XCTAssertEqual(stats.activeDays, 120)
        XCTAssertEqual(stats.completedStageCount, 360)
        XCTAssertEqual(stats.recoveryCount, 40)
        XCTAssertEqual(stats.totalFocusSeconds, 129_600)
        XCTAssertEqual(daily.count, 30)
        XCTAssertEqual(history.count, 120)
        XCTAssertEqual(detail.completedStageCount, 3)
        XCTAssertGreaterThan(csv.count, 20_000)
        XCTAssertTrue(csv.contains("task_long_119"))
        XCTAssertGreaterThanOrEqual(eventFiles.filter { $0.pathExtension == "jsonl" }.count, 4)
        XCTAssertGreaterThanOrEqual(profile.confidence, 0.85)
        XCTAssertTrue(achievements.contains { $0.id == "sixty_minutes" })
        XCTAssertLessThan(ingestionSeconds, 20, "Longitudinal ingestion should stay prototype-fast.")
        XCTAssertLessThan(querySeconds, 3, "Stats, history, export, profile, and achievement reads should remain responsive.")
    }

    func testClearUserProfilePreservesHistory() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let dataCenter = LocalDataCenterService(directory: root)
        try await dataCenter.recordEvent(LearningEvent(
            eventType: .stageCompleted,
            sourceModule: .module2Execution,
            taskId: "task_profile",
            stageId: "stage_profile",
            taskTitle: "Study chemistry",
            taskType: .examReview,
            stageTitle: "Review one formula",
            stageType: .reviewing,
            status: "completed",
            actualFocusSeconds: 420
        ))
        try await dataCenter.updateProfileFromRecentEvents()
        let learned = try await dataCenter.getUserProfileSnapshot()
        let snapshotURL = root.profile.appendingPathComponent("profile_snapshots.jsonl")
        let snapshotText = try String(contentsOf: snapshotURL, encoding: .utf8)
        XCTAssertGreaterThan(learned.confidence, 0)
        XCTAssertTrue(snapshotText.contains("\"confidence\""))

        try await dataCenter.clearUserProfile()
        let reset = try await dataCenter.getUserProfileSnapshot()
        let history = try await dataCenter.queryHistory(HistoryQuery(dateRange: .allTime, keyword: "chemistry"))
        let json = try await dataCenter.exportEventsJSON()

        XCTAssertEqual(reset, .empty)
        XCTAssertEqual(history.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL.path))
        XCTAssertTrue(json.contains("profile_memory_cleared"))
    }

    func testProfileLearningGatePreservesEventsWithoutUpdatingProfile() async throws {
        let directory = try temporaryDirectory()
        let dataCenter = LocalDataCenterService(directory: LocalDataDirectory(root: directory))
        await dataCenter.setProfileLearningEnabled(false)
        try await dataCenter.recordEvent(LearningEvent(
            eventType: .stageCompleted,
            sourceModule: .module2Execution,
            taskId: "task_gate",
            stageId: "stage_gate",
            taskTitle: "Study physics",
            taskType: .examReview,
            stageTitle: "Review one equation",
            stageType: .reviewing,
            status: "completed",
            actualFocusSeconds: 360
        ))
        try await dataCenter.updateProfileFromRecentEvents()

        let disabledProfile = try await dataCenter.getUserProfileSnapshot()
        let history = try await dataCenter.queryHistory(HistoryQuery(dateRange: .allTime, keyword: "physics"))
        XCTAssertEqual(disabledProfile, .empty)
        XCTAssertEqual(history.count, 1)

        await dataCenter.setProfileLearningEnabled(true)
        try await dataCenter.recordEvent(LearningEvent(
            eventType: .stageCompleted,
            sourceModule: .module2Execution,
            taskId: "task_gate_second",
            stageId: "stage_gate_second",
            taskTitle: "Study physics again",
            taskType: .examReview,
            stageTitle: "Review a second equation",
            stageType: .reviewing,
            status: "completed",
            actualFocusSeconds: 420
        ))
        let enabledProfile = try await dataCenter.getUserProfileSnapshot()
        XCTAssertGreaterThan(enabledProfile.confidence, 0)
    }

    func testProfileLearnsDifficultStageTypesFromFeedbackIntentRawValues() async throws {
        let directory = try temporaryDirectory()
        let dataCenter = LocalDataCenterService(directory: LocalDataDirectory(root: directory))
        let intents = [
            FeedbackIntent.tooHard.rawValue,
            FeedbackIntent.unclearInstruction.rawValue,
            "want_to_quit"
        ]
        for index in intents.indices {
            try await dataCenter.recordEvent(LearningEvent(
                eventType: .stageFeedbackSubmitted,
                sourceModule: .module3FeedbackOptimization,
                taskId: "task_difficult_profile",
                stageId: "stage_difficult_\(index)",
                taskTitle: "Write lab report",
                taskType: .writing,
                stageTitle: "Draft paragraph \(index)",
                stageType: .writing,
                status: intents[index],
                tags: ["feedback"],
                metadata: ["intent": intents[index]]
            ))
        }

        let profile = try await dataCenter.getUserProfileSnapshot()

        XCTAssertTrue(profile.difficultStageTypes.contains(.writing))
    }

    func testNaturalLanguageHistoryQueryAndDetail() async throws {
        let directory = try temporaryDirectory()
        let dataCenter = LocalDataCenterService(directory: LocalDataDirectory(root: directory))
        try await dataCenter.recordEvent(LearningEvent(
            eventType: .stageCompleted,
            sourceModule: .module2Execution,
            taskId: "task_history_detail",
            stageId: "stage_history_detail",
            taskTitle: "Read neuroscience paper",
            taskType: .reading,
            stageTitle: "Read abstract",
            stageType: .reading,
            status: "completed",
            actualFocusSeconds: 420
        ))

        let query = try await dataCenter.parseHistoryQuery("find last week reading paper records")
        let cards = try await dataCenter.queryHistory(query)
        let detail = try await dataCenter.getHistoryDetail(taskId: "task_history_detail")

        XCTAssertEqual(query.dateRange, .last7Days)
        XCTAssertEqual(query.taskTypes, [.reading])
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(detail.completedStageCount, 1)
        XCTAssertEqual(detail.stages.first?.title, "Read abstract")
    }

    func testAgentContextProviderBuildsRecentHistoryNotes() async throws {
        let directory = try temporaryDirectory()
        let dataCenter = LocalDataCenterService(directory: LocalDataDirectory(root: directory))
        let provider = LocalAgentContextProvider(dataCenter: dataCenter)
        try await dataCenter.recordEvent(LearningEvent(
            eventType: .stageCompleted,
            sourceModule: .module2Execution,
            taskId: "task_context_old",
            stageId: "stage_context_old",
            taskTitle: "Read article",
            taskType: .reading,
            stageTitle: "Read abstract",
            stageType: .reading,
            status: "completed",
            actualFocusSeconds: 300
        ))
        try await dataCenter.recordEvent(LearningEvent(
            eventType: .stageCompleted,
            sourceModule: .module2Execution,
            taskId: "task_context_current",
            stageId: "stage_context_current",
            taskTitle: "Current essay",
            taskType: .writing,
            stageTitle: "Write opener",
            stageType: .writing,
            status: "completed",
            actualFocusSeconds: 600
        ))

        let context = try await provider.getContext(for: "task_context_current", stageId: nil)

        XCTAssertEqual(context.privacyMode, .localOnly)
        XCTAssertEqual(context.recentSimilarTaskNotes.count, 1)
        XCTAssertTrue(context.recentSimilarTaskNotes[0].contains("reading"))
        XCTAssertFalse(context.recentSimilarTaskNotes[0].contains("Current essay"))
    }

    func testDeleteHistoryTaskRemovesTaskEventsButKeepsAuditEvent() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let dataCenter = LocalDataCenterService(directory: root)
        let repository = LocalTaskRepository(directory: root)
        var task = sampleTask()
        task = TaskPlan(
            id: "task_delete_me",
            originalInput: task.originalInput,
            title: "Delete this",
            taskType: .homework,
            status: task.status,
            estimatedTotalSeconds: task.estimatedTotalSeconds,
            stages: task.stages.map {
                StagePlan(
                    id: $0.id,
                    taskId: "task_delete_me",
                    order: $0.order,
                    title: $0.title,
                    instruction: $0.instruction,
                    completionCriteria: $0.completionCriteria,
                    stageType: $0.stageType,
                    estimatedSeconds: $0.estimatedSeconds,
                    status: $0.status
                )
            }
        )
        try await repository.save(task)
        try await dataCenter.recordEvent(LearningEvent(
            eventType: .taskCreated,
            sourceModule: .module1TaskPlanning,
            taskId: "task_delete_me",
            taskTitle: "Delete this",
            taskType: .homework
        ))

        try await dataCenter.deleteHistoryTask(taskId: "task_delete_me")
        let cards = try await dataCenter.queryHistory(HistoryQuery(dateRange: .allTime, keyword: "Delete this"))
        let json = try await dataCenter.exportEventsJSON()

        XCTAssertTrue(cards.isEmpty)
        XCTAssertTrue(json.contains("dataDeleted"))
        do {
            _ = try await repository.getTask("task_delete_me")
            XCTFail("Expected deleted task file to be removed.")
        } catch FocusFlowError.taskNotFound {
            XCTAssertTrue(true)
        }
    }

    func testDeleteHistoryDayRemovesOnlyThatDayAndKeepsAuditEvent() async throws {
        let directory = try temporaryDirectory()
        let dataCenter = LocalDataCenterService(directory: LocalDataDirectory(root: directory))
        try await dataCenter.recordEvent(LearningEvent(
            eventType: .stageCompleted,
            sourceModule: .module2Execution,
            localDay: "2026-06-25",
            taskId: "task_delete_day",
            stageId: "stage_delete_day",
            taskTitle: "Delete this day",
            taskType: .reading,
            stageTitle: "Read page",
            stageType: .reading,
            status: "completed",
            actualFocusSeconds: 300
        ))
        try await dataCenter.recordEvent(LearningEvent(
            eventType: .stageCompleted,
            sourceModule: .module2Execution,
            localDay: "2026-06-26",
            taskId: "task_keep_day",
            stageId: "stage_keep_day",
            taskTitle: "Keep this day",
            taskType: .writing,
            stageTitle: "Write line",
            stageType: .writing,
            status: "completed",
            actualFocusSeconds: 300
        ))

        try await dataCenter.deleteHistoryDay(localDay: "2026-06-25")
        let deletedCards = try await dataCenter.queryHistory(HistoryQuery(dateRange: .allTime, keyword: "Delete this day"))
        let keptCards = try await dataCenter.queryHistory(HistoryQuery(dateRange: .allTime, keyword: "Keep this day"))
        let json = try await dataCenter.exportEventsJSON()

        XCTAssertTrue(deletedCards.isEmpty)
        XCTAssertEqual(keptCards.count, 1)
        XCTAssertTrue(json.contains("day_history_deleted"))
        XCTAssertTrue(json.contains("2026-06-25"))
    }

    func testExpandedAchievementRulesUnlock() async throws {
        let directory = try temporaryDirectory()
        let dataCenter = LocalDataCenterService(directory: LocalDataDirectory(root: directory))
        for index in 0..<10 {
            try await dataCenter.recordEvent(LearningEvent(
                eventType: .stageCompleted,
                sourceModule: .module2Execution,
                taskId: "task_many_steps",
                stageId: "stage_\(index)",
                taskTitle: "Build study guide",
                taskType: .examReview,
                stageTitle: "Step \(index)",
                stageType: .reviewing,
                status: "completed",
                actualFocusSeconds: 420
            ))
        }
        try await dataCenter.recordEvent(LearningEvent(
            eventType: .taskCompleted,
            sourceModule: .module4ClosureEmotion,
            taskId: "task_many_steps",
            taskTitle: "Build study guide",
            taskType: .examReview,
            status: "completed"
        ))

        let achievements = try await dataCenter.getUnlockedAchievements()
        XCTAssertTrue(achievements.contains { $0.id == "ten_small_steps" })
        XCTAssertTrue(achievements.contains { $0.id == "sixty_minutes" })
        XCTAssertTrue(achievements.contains { $0.id == "first_loop_closed" })
    }

    func testAchievementCatalogCoversUnlockedRules() {
        let catalogIDs = AchievementCatalog.all.map(\.id)
        XCTAssertEqual(Set(catalogIDs).count, catalogIDs.count)

        let expectedRuleIDs: Set<String> = [
            "tiny_start",
            "first_stage",
            "gentle_return",
            "ten_small_steps",
            "sixty_minutes",
            "first_loop_closed",
            "noticed_distraction"
        ]
        XCTAssertTrue(expectedRuleIDs.isSubset(of: Set(catalogIDs)))
    }

    func testEmotionSupportAgentCanDecodeLLMCopy() async throws {
        let agent = EmotionSupportAgent(llmClient: FakeLLMClient(response: """
        {
          "encouragement_text": "You made the task visible and easier to return to.",
          "soothing_text": null,
          "review_items": [
            {"text":"You completed the smallest start.","type":"highlight"},
            {"text":"Next time, begin from the saved next step.","type":"suggestion"}
          ]
        }
        """))
        let copy = await agent.closureCopy(for: sampleTask(), focusSeconds: 600, closureType: .completed, reason: nil)

        XCTAssertEqual(copy.encouragementText, "You made the task visible and easier to return to.")
        XCTAssertEqual(copy.reviewItems.count, 2)
        XCTAssertEqual(copy.reviewItems[0].type, .highlight)
    }

    func testClosureAbandonmentUpdatesTaskStagesAndRecordsEvent() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let dataCenter = LocalDataCenterService(directory: root)
        let repository = LocalTaskRepository(directory: root)
        let eventBus = AppEventBus(dataCenter: dataCenter)
        let service = TaskClosureService(repository: repository, dataCenter: dataCenter, eventBus: eventBus)
        let task = sampleTask()
        try await repository.save(task)
        try await dataCenter.recordEvent(LearningEvent(
            eventType: .stageCompleted,
            sourceModule: .module2Execution,
            taskId: task.id,
            stageId: "stage_done_before_abandon",
            taskTitle: task.title,
            taskType: task.taskType,
            stageTitle: "Opened the paper",
            stageType: .startup,
            status: "completed",
            actualFocusSeconds: 240
        ))

        let summary = try await service.presentAbandonment(taskId: task.id, reason: "Needs a cleaner stop.")
        let abandoned = try await repository.getTask(task.id)
        let json = try await dataCenter.exportEventsJSON()

        XCTAssertEqual(summary.closureType, .abandoned)
        XCTAssertEqual(summary.totalFocusSeconds, 240)
        XCTAssertEqual(summary.abandonedStageCount, 1)
        XCTAssertEqual(abandoned.status, .abandoned)
        XCTAssertEqual(abandoned.stages.first?.status, .abandoned)
        XCTAssertTrue(json.contains("\"event_type\":\"taskAbandoned\"") || json.contains("\"event_type\" : \"taskAbandoned\""))
        XCTAssertTrue(json.contains("Needs a cleaner stop."))
    }

    func testClosureReviewSubmissionRecordsEvent() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let dataCenter = LocalDataCenterService(directory: root)
        let repository = LocalTaskRepository(directory: root)
        let eventBus = AppEventBus(dataCenter: dataCenter)
        let service = TaskClosureService(repository: repository, dataCenter: dataCenter, eventBus: eventBus)
        let task = sampleTask()
        try await repository.save(task)
        let review = ReviewItem(id: "review_focus_visible", text: "You made the task visible.", type: .highlight)
        let summary = TaskClosureSummary(
            id: "closure_review_test",
            taskId: task.id,
            closureType: .completed,
            totalPlannedSeconds: 300,
            totalFocusSeconds: 180,
            completedStageCount: 1,
            skippedStageCount: 0,
            abandonedStageCount: 0,
            keyBreakthroughs: ["Read the abstract"],
            encouragementText: "Progress counts.",
            soothingText: nil,
            reviewItems: [review],
            emotionTag: nil
        )

        try await service.submitReview(summary: summary, item: review, confirmed: false)
        let json = try await dataCenter.exportEventsJSON()

        XCTAssertTrue(json.contains("\"event_type\":\"reviewSubmitted\"") || json.contains("\"event_type\" : \"reviewSubmitted\""))
        XCTAssertTrue(json.contains("\"status\":\"not_quite\"") || json.contains("\"status\" : \"not_quite\""))
        XCTAssertTrue(json.contains("review_focus_visible"))
    }

    func testClosureEmotionMarkRecordsEvent() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let dataCenter = LocalDataCenterService(directory: root)
        let repository = LocalTaskRepository(directory: root)
        let eventBus = AppEventBus(dataCenter: dataCenter)
        let service = TaskClosureService(repository: repository, dataCenter: dataCenter, eventBus: eventBus)
        let task = sampleTask()
        try await repository.save(task)
        let summary = TaskClosureSummary(
            id: "closure_emotion_test",
            taskId: task.id,
            closureType: .completed,
            totalPlannedSeconds: 300,
            totalFocusSeconds: 180,
            completedStageCount: 1,
            skippedStageCount: 0,
            abandonedStageCount: 0,
            keyBreakthroughs: ["Read the abstract"],
            encouragementText: "Progress counts.",
            soothingText: nil,
            reviewItems: [],
            emotionTag: nil
        )

        try await service.markEmotion(summary: summary, emotion: .tired)
        let json = try await dataCenter.exportEventsJSON()

        XCTAssertTrue(json.contains("\"event_type\":\"emotionMarked\"") || json.contains("\"event_type\" : \"emotionMarked\""))
        XCTAssertTrue(json.contains("\"emotion\":\"tired\"") || json.contains("\"emotion\" : \"tired\""))
        XCTAssertTrue(json.contains("closure_emotion_test"))
    }

    func testClosureArchiveUpdatesTaskAndRecordsEvent() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let dataCenter = LocalDataCenterService(directory: root)
        let repository = LocalTaskRepository(directory: root)
        let eventBus = AppEventBus(dataCenter: dataCenter)
        let service = TaskClosureService(repository: repository, dataCenter: dataCenter, eventBus: eventBus)
        let task = sampleTask()
        try await repository.save(task)
        let summary = TaskClosureSummary(
            id: "closure_archive_test",
            taskId: task.id,
            closureType: .completed,
            totalPlannedSeconds: 300,
            totalFocusSeconds: 180,
            completedStageCount: 1,
            skippedStageCount: 0,
            abandonedStageCount: 0,
            keyBreakthroughs: ["Read the abstract"],
            encouragementText: "Progress counts.",
            soothingText: nil,
            reviewItems: [],
            emotionTag: nil
        )

        try await service.archiveTask(summary)
        let archived = try await repository.getTask(task.id)
        let json = try await dataCenter.exportEventsJSON()

        XCTAssertEqual(archived.status, .archived)
        XCTAssertTrue(json.contains("\"event_type\":\"taskArchived\"") || json.contains("\"event_type\" : \"taskArchived\""))
        XCTAssertTrue(json.contains("closure_archive_test"))
    }

    func testProfileAgentCanDecodeObservation() async throws {
        let agent = ProfileAgent(llmClient: FakeLLMClient(response: """
        {"text":"Your recent reading steps seem easier when they stay under ten minutes.","confidence":0.72}
        """))
        let observation = await agent.observation(
            profile: UserProfileSnapshot(preferredStageDurationSeconds: 540, confidence: 0.6),
            stats: StatsSummary(
                range: .last7Days,
                activeDays: 3,
                strictStreakDays: 2,
                gentleRhythmText: "You returned to learning 3 days this week.",
                totalFocusSeconds: 1800,
                completedStageCount: 5,
                stageCompletionRate: 0.8,
                taskCompletionRate: nil,
                recoveryCount: 1
            )
        )

        XCTAssertTrue(observation.text.contains("reading"))
        XCTAssertEqual(observation.confidence, 0.72)
    }

    func testHistoryQueryAgentCanDecodeLLMQueryWithoutHistoryUpload() async throws {
        let recorder = LLMMessageRecorder(response: """
        {
          "date_range": "thisMonth",
          "keyword": "paper",
          "task_types": ["reading"],
          "stage_types": ["reading"],
          "statuses": ["completed"]
        }
        """)
        let agent = HistoryQueryAgent(llmClient: recorder)

        let query = try await agent.parseUsingLLM("show this month completed reading paper records")
        let lastPrompt = await recorder.lastUserMessage()

        XCTAssertEqual(query.dateRange, .thisMonth)
        XCTAssertEqual(query.keyword, "paper")
        XCTAssertEqual(query.taskTypes, [.reading])
        XCTAssertEqual(query.stageTypes, [.reading])
        XCTAssertEqual(query.statuses, ["completed"])
        XCTAssertEqual(lastPrompt, "show this month completed reading paper records")
        XCTAssertFalse(lastPrompt.contains("event_type"))
    }

    func testStageEditPersistsClampsAndPublishesPlanUpdate() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let dataCenter = LocalDataCenterService(directory: root)
        let repository = LocalTaskRepository(directory: root)
        let eventBus = AppEventBus(dataCenter: dataCenter)
        let service = TaskPlanningService(repository: repository, eventBus: eventBus)
        let task = sampleTask()
        try await repository.save(task)

        let updated = try await service.updateStage(
            taskId: task.id,
            stageId: task.stages[0].id,
            patch: StagePlanPatch(
                title: "Read intro",
                instruction: "Read only the introduction.",
                completionCriteria: "One useful sentence is underlined.",
                stageType: .reading,
                estimatedSeconds: 30
            )
        )
        let stored = try await repository.getTask(task.id)
        let json = try await dataCenter.exportEventsJSON()

        XCTAssertEqual(updated.stages[0].title, "Read intro")
        XCTAssertEqual(stored.stages[0].instruction, "Read only the introduction.")
        XCTAssertEqual(stored.stages[0].estimatedSeconds, 120)
        XCTAssertTrue(json.contains("\"event_type\":\"taskPlanUpdated\"") || json.contains("\"event_type\" : \"taskPlanUpdated\""))
        XCTAssertTrue(json.contains("manual_stage_edit"))
    }

    func testRuntimeExtensionUpdatesRemainingTimeAndPublishesEvent() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let dataCenter = LocalDataCenterService(directory: root)
        let repository = LocalTaskRepository(directory: root)
        let runtimeStore = LocalRuntimeStore(directory: root)
        let eventBus = AppEventBus(dataCenter: dataCenter)
        let service = ExecutionService(repository: repository, runtimeStore: runtimeStore, eventBus: eventBus)
        let task = sampleTask()
        try await repository.save(task)
        try await runtimeStore.save(StageRuntime(
            taskId: task.id,
            stageId: task.stages[0].id,
            status: .running,
            startedAt: Date().addingTimeInterval(-240),
            pauseStartedAt: nil,
            pauseTotalSeconds: 0,
            plannedSeconds: 300,
            monotonicAnchor: ProcessInfo.processInfo.systemUptime - 240
        ))

        let beforeValue = try await service.remainingSeconds()
        let before = try XCTUnwrap(beforeValue)
        XCTAssertEqual(before, 60)

        let extended = try await service.extendCurrentStage(seconds: 300, trigger: .user)
        let remainingValue = try await service.remainingSeconds()
        let remaining = try XCTUnwrap(remainingValue)
        let stored = try await repository.getTask(task.id)
        let json = try await dataCenter.exportEventsJSON()

        XCTAssertEqual(extended.plannedSeconds, 600)
        XCTAssertGreaterThanOrEqual(remaining, 355)
        XCTAssertLessThanOrEqual(remaining, 365)
        XCTAssertEqual(stored.stages[0].estimatedSeconds, extended.plannedSeconds)
        XCTAssertTrue(json.contains("\"event_type\":\"runtimeExtended\"") || json.contains("\"event_type\" : \"runtimeExtended\""))
        XCTAssertTrue(json.contains("\"added_seconds\":\"300\"") || json.contains("\"added_seconds\" : \"300\""))
    }

    func testEnterOvertimeWhenRemainingTimeExpires() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let dataCenter = LocalDataCenterService(directory: root)
        let repository = LocalTaskRepository(directory: root)
        let runtimeStore = LocalRuntimeStore(directory: root)
        let eventBus = AppEventBus(dataCenter: dataCenter)
        let service = ExecutionService(repository: repository, runtimeStore: runtimeStore, eventBus: eventBus)
        let task = sampleTask()
        try await repository.save(task)
        try await runtimeStore.save(StageRuntime(
            taskId: task.id,
            stageId: task.stages[0].id,
            status: .running,
            startedAt: Date().addingTimeInterval(-360),
            pauseStartedAt: nil,
            pauseTotalSeconds: 0,
            plannedSeconds: 300
        ))

        let entered = try await service.enterOvertimeIfNeeded()
        let runtime = try await runtimeStore.loadActiveRuntime()
        let stored = try await repository.getTask(task.id)

        XCTAssertTrue(entered)
        XCTAssertEqual(runtime?.status, .overtime)
        XCTAssertEqual(stored.stages[0].status, .overtime)
    }

    func testRetryQueueCapturesFailedEventWritesAndReplaysWithoutDuplication() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let failing = LocalDataCenterService(directory: root, simulateEventWriteFailure: true)
        let event = LearningEvent(
            id: "evt_retry_once",
            eventType: .manualCheckIn,
            sourceModule: .module5DataCenter,
            status: "retry_probe"
        )

        try await failing.recordEvent(event)
        let queuedFiles = try FileManager.default.contentsOfDirectory(at: root.retryQueue, includingPropertiesForKeys: nil)
        XCTAssertFalse(queuedFiles.isEmpty)

        let healthy = LocalDataCenterService(directory: root)
        let firstReplay = try await healthy.replayRetryQueue()
        let secondReplay = try await healthy.replayRetryQueue()
        let json = try await healthy.exportEventsJSON()

        XCTAssertEqual(firstReplay.replayedCount, 1)
        XCTAssertEqual(firstReplay.failedCount, 0)
        XCTAssertEqual(secondReplay.replayedCount, 0)
        XCTAssertEqual(json.components(separatedBy: "evt_retry_once").count - 1, 1)
        XCTAssertTrue(json.contains("\"event_type\":\"eventWriteRetried\"") || json.contains("\"event_type\" : \"eventWriteRetried\""))
    }

    func testOtherTextFeedbackCreatesStructuredMetadata() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let dataCenter = LocalDataCenterService(directory: root)
        let repository = LocalTaskRepository(directory: root)
        let eventBus = AppEventBus(dataCenter: dataCenter)
        let service = FeedbackOptimizationService(repository: repository, eventBus: eventBus)
        let task = sampleTask()
        try await repository.save(task)

        _ = try await service.submitFeedback(StageFeedback(
            taskId: task.id,
            stageId: task.stages[0].id,
            executionResultId: "result_other_text",
            selectedLabel: "Other",
            otherText: "I kept rereading the same line.",
            intent: .other
        ))
        let json = try await dataCenter.exportEventsJSON()

        XCTAssertTrue(json.contains("\"other_text\":\"I kept rereading the same line.\"") || json.contains("\"other_text\" : \"I kept rereading the same line.\""))
        XCTAssertTrue(json.contains("\"intent\":\"other\"") || json.contains("\"intent\" : \"other\""))
    }

    func testPersistentSevereInterruptionCountersTriggerIntervention() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let dataCenter = LocalDataCenterService(directory: root)
        let repository = LocalTaskRepository(directory: root)
        let eventBus = AppEventBus(dataCenter: dataCenter)
        let service = FeedbackOptimizationService(repository: repository, eventBus: eventBus)
        let task = sampleTask()
        try await repository.save(task)

        _ = try await service.submitFeedback(StageFeedback(
            taskId: task.id,
            stageId: task.stages[0].id,
            executionResultId: "result_overload_1",
            selectedLabel: "Other",
            intent: .other,
            emotionTag: .overwhelmed
        ))
        let second = try await service.submitFeedback(StageFeedback(
            taskId: task.id,
            stageId: task.stages[0].id,
            executionResultId: "result_overload_2",
            selectedLabel: "Other",
            intent: .other,
            emotionTag: .overwhelmed
        ))
        let stored = try await repository.getTask(task.id)

        XCTAssertEqual(second.interventionRequest?.interruptionType, .emotionalOverload)
        XCTAssertEqual(stored.metadata["emotional_overload_count"], "2")
    }

    func testProfileCorrectionReducesConfidenceAndAgentContextSeesIt() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let dataCenter = LocalDataCenterService(directory: root)
        let profile = UserProfileSnapshot(
            preferredStageDurationSeconds: 420,
            recommendedFirstStageSeconds: 180,
            difficultStageTypes: [.reading],
            easierStageTypes: [.writing],
            effectiveInterventions: [.splitSmaller],
            encouragementStyle: .gentleDirect,
            rewardPreference: .quietBadge,
            streakSensitivity: .medium,
            confidence: 0.8,
            lastUpdatedAt: Date()
        )
        try root.prepare()
        let data = try FocusFlowJSON.encoder.encode(profile)
        try data.write(to: root.profile.appendingPathComponent("user_profile.json"), options: [.atomic])

        let corrected = try await dataCenter.submitProfileCorrection(ProfileCorrection(
            reason: "reading inference was wrong",
            affectedStageTypes: [.reading],
            note: "Reading was hard because the PDF was broken.",
            confidenceImpact: 0.3
        ))
        let context = try await LocalAgentContextProvider(dataCenter: dataCenter).getContext(for: nil, stageId: nil)
        let json = try await dataCenter.exportEventsJSON()

        XCTAssertEqual(corrected.confidence, 0.5, accuracy: 0.001)
        XCTAssertFalse(corrected.difficultStageTypes.contains(.reading))
        XCTAssertEqual(context.userProfileSnapshot.confidence, corrected.confidence, accuracy: 0.001)
        XCTAssertTrue(json.contains("\"event_type\":\"profileCorrectionSubmitted\"") || json.contains("\"event_type\" : \"profileCorrectionSubmitted\""))
    }

    func testThisMonthHistoryRangeUsesCalendarMonthNotRollingThirtyDays() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let dataCenter = LocalDataCenterService(directory: root)
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = try XCTUnwrap(calendar.date(from: calendar.dateComponents([.year, .month], from: now)))
        let thisMonthDate = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: startOfMonth))
        let previousMonthDate = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: startOfMonth))

        try await dataCenter.recordEvent(LearningEvent(
            id: "evt_this_month",
            eventType: .stageCompleted,
            sourceModule: .module2Execution,
            timestamp: thisMonthDate,
            localDay: FocusFlowCalendar.localDay(for: thisMonthDate),
            taskId: "task_this_month",
            taskTitle: "This month task",
            status: "completed",
            actualFocusSeconds: 60
        ))
        try await dataCenter.recordEvent(LearningEvent(
            id: "evt_previous_month",
            eventType: .stageCompleted,
            sourceModule: .module2Execution,
            timestamp: previousMonthDate,
            localDay: FocusFlowCalendar.localDay(for: previousMonthDate),
            taskId: "task_previous_month",
            taskTitle: "Previous month task",
            status: "completed",
            actualFocusSeconds: 60
        ))

        let monthHistory = try await dataCenter.queryHistory(HistoryQuery(dateRange: .thisMonth))
        let parsed = try await dataCenter.parseHistoryQuery("show this month reading history")

        XCTAssertTrue(monthHistory.contains { $0.taskId == "task_this_month" })
        XCTAssertFalse(monthHistory.contains { $0.taskId == "task_previous_month" })
        XCTAssertEqual(parsed.dateRange, .thisMonth)
    }

    func testClosureSummaryPersistsUnderDataCenterSummaries() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let dataCenter = LocalDataCenterService(directory: root)
        let repository = LocalTaskRepository(directory: root)
        let eventBus = AppEventBus(dataCenter: dataCenter)
        let service = TaskClosureService(repository: repository, dataCenter: dataCenter, eventBus: eventBus)
        let task = sampleTask()
        try await repository.save(task)

        let summary = try await service.presentCompletion(taskId: task.id)
        let loaded = try await dataCenter.getClosureSummary(taskId: task.id)
        let summaryURL = root.summaries.appendingPathComponent("\(task.id)_closure.json")

        XCTAssertEqual(loaded.id, summary.id)
        XCTAssertEqual(loaded.closureType, .completed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: summaryURL.path))
    }

    func testFeedbackOptionsPrewarmCachesAgentResult() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let dataCenter = LocalDataCenterService(directory: root)
        let repository = LocalTaskRepository(directory: root)
        let eventBus = AppEventBus(dataCenter: dataCenter)
        let task = sampleTask()
        try await repository.save(task)
        let recorder = LLMCallRecorder()
        let feedbackAgent = FeedbackAgent(llmClient: CountingLLMClient(recorder: recorder, response: """
        {"options":[
          {"label":"Read enough","emoji":"📄","intent":"completed"},
          {"label":"Too dense","emoji":"🔍","intent":"tooHard"},
          {"label":"Need time","emoji":"⏱","intent":"needMoreTime"}
        ]}
        """))
        let service = FeedbackOptimizationService(repository: repository, eventBus: eventBus, feedbackAgent: feedbackAgent)

        try await service.prewarmFeedbackOptions(taskId: task.id, stageId: task.stages[0].id)
        let options = try await service.prepareFeedbackOptions(taskId: task.id, stageId: task.stages[0].id)
        let callCount = await recorder.value()

        XCTAssertEqual(options.map(\.label), ["Read enough", "Too dense", "Need time"])
        XCTAssertEqual(callCount, 1)
    }

    func testRemainingSecondsUsesMonotonicAnchorWhenWallClockDrifts() async throws {
        let directory = try temporaryDirectory()
        let root = LocalDataDirectory(root: directory)
        let dataCenter = LocalDataCenterService(directory: root)
        let repository = LocalTaskRepository(directory: root)
        let runtimeStore = LocalRuntimeStore(directory: root)
        let eventBus = AppEventBus(dataCenter: dataCenter)
        let service = ExecutionService(repository: repository, runtimeStore: runtimeStore, eventBus: eventBus)
        let started = Date(timeIntervalSince1970: 10_000)
        try await runtimeStore.save(StageRuntime(
            taskId: "task_clock",
            stageId: "stage_clock",
            status: .running,
            startedAt: started,
            pauseStartedAt: nil,
            pauseTotalSeconds: 0,
            plannedSeconds: 300,
            lastTickAt: started,
            monotonicAnchor: 100
        ))

        let forwardValue = try await service.remainingSeconds(
            now: started.addingTimeInterval(3_600),
            monotonicNow: 110
        )
        let forwardJump = try XCTUnwrap(forwardValue)
        let backwardValue = try await service.remainingSeconds(
            now: started.addingTimeInterval(-300),
            monotonicNow: 110
        )
        let backwardJump = try XCTUnwrap(backwardValue)

        XCTAssertEqual(forwardJump, 290)
        XCTAssertEqual(backwardJump, 290)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FocusFlowTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func hasQuarantinedFile(named fileName: String, under root: URL) throws -> Bool {
        let quarantineRoot = root.appendingPathComponent(".corrupt", isDirectory: true)
        guard FileManager.default.fileExists(atPath: quarantineRoot.path) else {
            return false
        }
        guard let enumerator = FileManager.default.enumerator(at: quarantineRoot, includingPropertiesForKeys: nil) else {
            return false
        }
        for case let url as URL in enumerator where url.lastPathComponent == fileName {
            return true
        }
        return false
    }

    private func sampleTask() -> TaskPlan {
        let taskId = "task_sample"
        let stage = StagePlan(
            id: "stage_sample",
            taskId: taskId,
            order: 1,
            title: "Read the abstract",
            instruction: "Read the abstract and mark one sentence.",
            completionCriteria: "One sentence is marked.",
            stageType: .reading,
            estimatedSeconds: 300
        )
        return TaskPlan(
            id: taskId,
            originalInput: "Read a paper",
            title: "Read a paper",
            taskType: .reading,
            status: .active,
            estimatedTotalSeconds: 300,
            stages: [stage]
        )
    }

    private func multiStageTask() -> TaskPlan {
        let taskId = "task_multi_stage"
        let stages = [
            StagePlan(
                id: "stage_multi_1",
                taskId: taskId,
                order: 1,
                title: "Read the abstract",
                instruction: "Read the abstract and mark one sentence.",
                completionCriteria: "One sentence is marked.",
                stageType: .reading,
                estimatedSeconds: 300,
                status: .completed
            ),
            StagePlan(
                id: "stage_multi_2",
                taskId: taskId,
                order: 2,
                title: "Read the conclusion",
                instruction: "Read the conclusion and notice the main claim.",
                completionCriteria: "The main claim is noted.",
                stageType: .reading,
                estimatedSeconds: 420
            ),
            StagePlan(
                id: "stage_multi_3",
                taskId: taskId,
                order: 3,
                title: "Write one summary sentence",
                instruction: "Write one sentence in your own words.",
                completionCriteria: "One sentence is written.",
                stageType: .writing,
                estimatedSeconds: 300,
                status: .adjusted
            )
        ]
        return TaskPlan(
            id: taskId,
            originalInput: "Read a paper",
            title: "Read a paper",
            taskType: .reading,
            status: .active,
            estimatedTotalSeconds: stages.reduce(0) { $0 + $1.estimatedSeconds },
            stages: stages
        )
    }
}

private struct FakeLLMClient: LLMClient {
    let response: String

    func complete(messages: [LLMMessage], privacyMode: PrivacyMode, responseFormat: LLMResponseFormat?) async throws -> String {
        response
    }
}

private actor LLMMessageRecorder: LLMClient {
    private let response: String
    private var messages: [LLMMessage] = []

    init(response: String) {
        self.response = response
    }

    func complete(messages: [LLMMessage], privacyMode: PrivacyMode, responseFormat: LLMResponseFormat?) async throws -> String {
        self.messages = messages
        return response
    }

    func lastUserMessage() -> String {
        messages.last(where: { $0.role == "user" })?.content ?? ""
    }
}

private actor LLMCallRecorder {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}

private struct CountingLLMClient: LLMClient {
    let recorder: LLMCallRecorder
    let response: String

    func complete(messages: [LLMMessage], privacyMode: PrivacyMode, responseFormat: LLMResponseFormat?) async throws -> String {
        await recorder.increment()
        return response
    }

    init(recorder: LLMCallRecorder, response: String = "{\"ok\":true}") {
        self.recorder = recorder
        self.response = response
    }
}
