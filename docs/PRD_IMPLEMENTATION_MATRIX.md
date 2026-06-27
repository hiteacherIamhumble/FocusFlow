# FocusFlow PRD Implementation Matrix

This matrix maps the Chinese five-module PRD to the current native macOS implementation. It is meant to keep the product honest as the codebase moves from demo to production.

## Product Shell

| PRD Area | Implementation | Verification |
| --- | --- | --- |
| Native macOS app, not Electron/Tauri | SwiftUI app target in `Sources/FocusFlowApp`, packaged by `Scripts/package_app.sh` into `dist/FocusFlow.app` | `Scripts/smoke_check.sh` validates build, bundle, signature, and plist |
| Release artifact | `Scripts/release_app.sh` creates a verified DMG, SHA-256 checksum, optional Developer ID signing, optional notarization, and stapling | `Scripts/release_app.sh` plus `hdiutil verify` |
| English product surface | User-facing SwiftUI copy is English across task input, plan preview, execution, closure, personal center, and settings | Manual app launch plus UI smoke launch check |
| Light ADHD-friendly design | Adaptive semantic color tokens, compact navigation, restrained cards, progressive task flow, low-pressure feedback copy, responsive button/metric layouts, and VoiceOver-friendly labels | Visual review through packaged app plus SwiftUI token scan |
| Runtime readiness | Settings includes a readiness dashboard for required and optional local/remote/native capabilities | `AppReadinessService` tests |
| Readiness actions | Settings can open notification settings and test floating timer, voice, shortcuts, DeepSeek, export, profile reset, and data deletion confirmation | `Scripts/ui_smoke_settings.sh` launch smoke; strict click mode available |
| Secret storage readiness | DeepSeek API key is handled through Keychain or environment variables; ordinary local learning data does not require encrypted-at-rest storage for MVP | Settings and secret scan checks |
| Local-first architecture | `FocusFlowCore` owns models, services, agents, storage, event bus; app layer binds native UI/adapters | Swift smoke test suite |
| DeepSeek remote model path | `DeepSeekLLMClient` calls DeepSeek chat completions with model `deepseek-v4-flash`; gated by settings and API-key availability | Privacy-gated tests and app settings flow |

## Shared Contracts

| PRD Area | Implementation | Verification |
| --- | --- | --- |
| Core enums and task/stage models | `FocusFlowModels.swift`, `FocusFlowSupport.swift` | Decode, planning, execution, feedback, closure tests |
| Runtime stage model | `ExecutionRuntime`, `RuntimeStore`, `ExecutionService` | Runtime restore, pause accounting, timeout tests |
| Timer drift guard | Remaining time is recalculated from timestamps and falls back to monotonic uptime when wall-clock drift exceeds 2 seconds | `testRemainingSecondsUsesMonotonicAnchorWhenWallClockDrifts` |
| Runtime extension contract | `ExecutionService.extendCurrentStage(seconds:trigger:)` and `LearningEventType.runtimeExtended` | `testRuntimeExtensionUpdatesRemainingTimeAndPublishesEvent` |
| Stage edit contract | `StagePlanPatch` and `TaskPlanningService.updateStage(taskId:stageId:patch:)` | `testStageEditPersistsClampsAndPublishesPlanUpdate` |
| Feedback/update contracts | `StageFeedback`, `otherText`, `StageUpdateProposal`, `FeedbackOptimizationService` | Feedback optimization and other-text tests |
| Closure summary | `TaskClosureService`, task archive/completion metadata | Closure tests |
| Closure summary persistence | Module four saves `TaskClosureSummary` through module five under `summaries/<task>_closure.json` | `testClosureSummaryPersistsUnderDataCenterSummaries` |
| Unified event model | `AppEvent`, `AppEventBus`, `DataCenterService` JSONL storage and retry queue | Event dedupe, query, delete, export, retry replay tests |
| User profile snapshot | `UserProfileSnapshot`, `ProfileAgent`, latest profile file, and `profile_snapshots.jsonl` journal in data center | Profile learning, snapshot, gate, reset tests |
| Service interface boundaries | `ServiceProtocols.swift` plus concrete services | Cross-module end-to-end test |

## Module 1: Task Input And Intelligent Breakdown

| PRD Requirement | Implementation | Verification |
| --- | --- | --- |
| Educational-task input | `TaskInputView`, `TaskPlanningService` | Non-educational rejection test |
| Lightweight clarification | Draft planning and acceptance flow in `TaskPlanningService` and `FocusFlowAppModel` | Draft clarification test |
| Plan preview | `PlanPreviewView` | App launch smoke and accessibility identifiers |
| True plan editing | Inline edit controls for stage title, instruction, completion criteria, type, and minutes before start | `testStageEditPersistsClampsAndPublishesPlanUpdate` |
| ADHD-friendly breakdown | `TaskBreakdownAgent` tiny first-step rules and fallback parser | Breakdown tests |
| Cold-start first stage | First stage is intentionally small and low-friction | `testTaskBreakdownCreatesTinyFirstStep` |
| Time bounds and stage warning | Stage edit clamps first step to 2+ minutes, max stage to 25 minutes, and surfaces 15+ stage warning | Stage edit test plus plan UI |
| Regenerate/refine | Plan refine/regenerate actions | Regenerate and more-time tests |
| Agent run logging | `AgentRunLogger` records request/success/fallback/failure events | Planning agent-run tests |

## Module 2: Stage Execution And Local Reminders

| PRD Requirement | Implementation | Verification |
| --- | --- | --- |
| Execution center | `ExecutionCenterView`, `ExecutionService` | E2E service test |
| Floating timer | Native `NSPanel` adapter in `NativeAdapters.swift` with stuck, +5, and done actions wired to app actions | Runtime extension test plus packaged app smoke |
| Timer state machine | Not-started/running/paused/completed/skipped/timeout flow | Pause, complete, skip, timeout tests |
| Runtime extension | Execution center, floating timer, and floating preview expose `+5 min`, writing `runtimeExtended` | Runtime extension test |
| Explicit task ending | Execution center separates pause gently, complete task now, skip, and end task | UI smoke launch scripts and closure tests |
| Collapsed stage list | Stage list is collapsed by default with expand/collapse | Execution UI |
| Active task restore after app restart | `RuntimeStore` persists active runtime | Runtime recovery tests |
| Local notifications | `NativeNotificationScheduler` plus fallback message logic | Notification fallback test |
| Custom shortcuts | Settings-backed shortcut model and app commands | Shortcut normalization tests |
| Voice semantic commands | `VoiceCommandParser` and voice adapter hooks | Voice parser test |

## Module 3: Feedback And Dynamic Optimization

| PRD Requirement | Implementation | Verification |
| --- | --- | --- |
| Feedback options after stage | `FeedbackAgent`, `FeedbackOptimizationService`, `ExecutionCenterView` | Feedback decode and E2E tests |
| Fast feedback sheet | `FeedbackOptimizationService.prewarmFeedbackOptions` caches options when a stage starts so the later feedback sheet can reuse them | `testFeedbackOptionsPrewarmCachesAgentResult` |
| Other situation feedback | Feedback sheet includes free-text "Other situation" and stores `other_text` metadata | `testOtherTextFeedbackCreatesStructuredMetadata` |
| Dynamic stage update | `PlanOptimizationAgent`, update preview/apply/undo flow | Stage update and undo tests |
| Severe interruption handling | High-urgency intervention routes to closure/pause flow, with persistent repeated-overload/incomplete counters in task metadata | Want-to-quit and persistent counter tests |
| Stuck layered hints | Stuck-help feedback path with emotional acknowledgement and next-step suggestions; writes `stuckHelpRequested` | Timeout/stuck tests |
| Short feedback labels | LLM labels are deterministically cleaned to max 3 words / 18 characters | Feedback decode/cleaning path |
| Skip feedback safely | Skip path records event without mutating stage | Skip feedback test |
| Agent run logging | Feedback optimization events logged to data center | Feedback agent-run test |

## Module 4: Closure And Emotional Encouragement

| PRD Requirement | Implementation | Verification |
| --- | --- | --- |
| Task settlement page | `ClosureView`, `TaskClosureService` | Completion/archive tests |
| Durable closure summary | Completion, graceful pause, and abandonment summaries are saved by `DataCenterService` before the closure event is published | Closure summary persistence test |
| Completion timeline | Closure page lists stage status timeline and breakthrough points | Closure UI |
| Gentle abandonment flow | Graceful pause and abandoned closure paths | Abandonment tests |
| Lightweight review | Emotion mark, review submission, and optional one-line user note | Emotion/review tests and closure UI |
| History entry from closure | Closure page includes "View history" action | `Scripts/ui_smoke_closure_history.sh` launch smoke |
| Abandoned action set | Non-completed closure includes save progress, split smaller, rest, switch task, and close actions | Closure UI |
| Encouraging copy generation | `EmotionSupportAgent` with deterministic fallback | Emotion support decode test |
| Closure event emission | Closure actions write events and update task status | Closure event tests |

## Module 5: Personal Data Center And Achievements

| PRD Requirement | Implementation | Verification |
| --- | --- | --- |
| Local storage directory | `LocalDataDirectory`, supports default app data root plus test/launch overrides | Environment data-root test |
| Task and runtime files | `LocalTaskRepository` and `LocalRuntimeStore` persist recoverable local files and keep compatibility with existing local data | Runtime recovery and repository tests |
| Event JSONL storage | `DataCenterService` daily JSONL event files | Event storage tests |
| Closure summary files | `summaries/` stores task closure summaries for later history/detail recovery | Closure summary persistence test |
| Event write retry queue | Failed event writes are queued under `retry_queue/*.jsonl` and replayed with dedupe/audit events | `testRetryQueueCapturesFailedEventWritesAndReplaysWithoutDuplication` |
| Local memory files | Event, retry queue, profile, achievement, and closure summary files stay local-first and export to user-readable JSON/CSV/Markdown | Data center export and history tests |
| Responsive long local history | `DataCenterService` keeps an actor-local event cache while preserving JSONL as source of durable storage | Longitudinal 120-day regression test |
| Privacy controls | Settings gate remote calls and profile learning | Privacy/profile gate tests |
| ProfileAgent learning | Profile updates from feedback and task history, appending each learned snapshot to `profile/profile_snapshots.jsonl` | Profile tests |
| Profile correction | Personal center can mark an observation inaccurate, reducing profile confidence and clearing affected stage-type signals | `testProfileCorrectionReducesConfidenceAndAgentContextSeesIt` |
| Personal center | `PersonalCenterView` stats, history, profile, export actions | App launch smoke |
| History query/detail/delete | `HistoryQueryAgent` parses natural-language history queries with DeepSeek-compatible JSON output and local rule fallback; APIs include calendar "this month" | History agent, history, and this-month tests |
| Statistics | Learning days, streaks, completion rates, focus minutes, recovery count | Daily stats tests |
| Achievements | Catalog, unlock rules, queued notifications | Achievement tests |
| Export | JSON and CSV export | Export tests |

## Global Settings

| PRD Requirement | Implementation | Verification |
| --- | --- | --- |
| Remote agent toggle | `SettingsView`, `SettingsService`, privacy-gated LLM client | Privacy-gated tests |
| DeepSeek API key handling | Key is stored through native secure adapter when configured; not committed to repo | Smoke secret scan |
| Secret handling | API keys are never committed and are saved through native secure storage when configured; local learning files remain local-first without an MVP encryption requirement | Settings persistence and smoke secret scan |
| Profile learning toggle/reset | Settings and data center profile reset | Profile gate/reset tests |
| Notification, floating timer, voice, shortcuts | Settings-backed app controls | Settings and shortcut tests |
| Per-shortcut conflict state | Each shortcut row shows ready/conflict and conflict risk can be recorded during shortcut testing | Settings UI |
| Legacy settings migration | Defaults applied when older settings omit newer fields | Legacy settings test |

## Agent Architecture

| PRD Requirement | Implementation | Verification |
| --- | --- | --- |
| No single black-box agent | Separate task breakdown, feedback, plan optimization, emotion support, and profile agents | Agent-specific tests |
| History query agent | `HistoryQueryAgent` converts user search text to `HistoryQuery` without uploading full history | `testHistoryQueryAgentCanDecodeLLMQueryWithoutHistoryUpload` |
| AgentContextProvider | Recent profile/history context injected into prompts | Context provider tests |
| Privacy-gated LLM calls | Remote calls blocked unless enabled and key exists | Privacy-gated test |
| Safe structured output | Agents decode structured JSON and fall back deterministically | Decode/fallback tests |
| Agent observability | Agent run lifecycle events are recorded | Agent run logger tests |

## Exception And Boundary Cases

| PRD Requirement | Implementation | Verification |
| --- | --- | --- |
| Non-educational input | Rejected before task persistence | Non-educational test |
| Start then quit | Runtime persists and can be restored | Runtime tests |
| Overlong timer/no action | Timeout prompt event and help path | Timeout test |
| App crash/restart | Active runtime and task data survive local files | Runtime/store tests |
| Corrupt files | Bad JSON is quarantined into `.corrupt` and safe defaults are used | Corrupt settings/runtime/task/profile tests |
| User deletes data | Data deletion APIs keep audit events where required | Delete history tests |

## Acceptance Coverage

| Acceptance Area | Current Status |
| --- | --- |
| Functional acceptance | Covered by the passing Swift smoke test suite |
| Cross-module acceptance | `testFiveModuleLearningLoopRunsEndToEnd` exercises modules 1 through 5 |
| ADHD-friendly acceptance | UI flow is progressive, low-pressure, avoids punitive language, uses semantic color roles, does not rely on color alone, and respects Reduce Motion in animated stage-list transitions |
| Performance acceptance | Local services are file-backed with actor-local event caching; 120 days of local events exercise stats, history, export, profile learning, and achievements | `testDataCenterHandlesLongitudinalLocalHistoryAtPrototypeScale` |
| Privacy acceptance | Remote calls are opt-in, data is local-first, secret scan runs in smoke check |
| UI launch acceptance | `Scripts/ui_smoke_check.sh` packages and launches the app in permission-light mode |
| Strict UI click acceptance | `FOCUSFLOW_UI_STRICT_CLICK=1 Scripts/ui_smoke_check.sh` runs the primary task flow through Accessibility names or CGEvent fallback and verifies feedback event storage |
| Supplemental UI coverage | `Scripts/ui_smoke_settings.sh`, `Scripts/ui_smoke_execution_controls.sh`, and `Scripts/ui_smoke_closure_history.sh` launch the app and support strict named-control clicks when macOS Accessibility exposes SwiftUI controls |
| Release acceptance | `Scripts/release_app.sh` creates `dist/release/FocusFlow-<version>-build-<build>.dmg` and checksum |
