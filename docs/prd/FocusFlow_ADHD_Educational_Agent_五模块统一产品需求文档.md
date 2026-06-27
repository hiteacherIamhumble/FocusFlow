# FocusFlow：ADHD Educational Agent Mac App — 五模块统一产品需求文档

> **产品**：FocusFlow / ADHD 主动式学习辅助 Agent（macOS 原生应用）  
> **文档定位**：五个平等、低耦合模块的统一产品需求文档，可直接交给 coding agent 拆分实现  
> **版本**：v1.0  
> **日期**：2026-06-26  
> **核心目标**：把「任务输入 → 智能拆解 → 阶段执行 → 阶段反馈 → 动态优化 → 任务闭环 → 数据沉淀 → 成就激励」统一成一条可落地、可编码、低认知负担的 ADHD 友好学习流程。

---

## 0. 阅读说明与统一原则

本文件将原 5 个模块需求合并为一份完整 PRD，并对以下内容进行了统一：

1. **技术栈统一**：统一采用 macOS 原生技术栈，避免模块二使用 Tauri、模块五使用 SwiftUI 的冲突。
2. **数据接口统一**：所有模块共享同一套 `TaskPlan / StagePlan / StageExecutionResult / LearningEvent / UserProfileSnapshot` 数据结构。
3. **持久化责任统一**：长期历史、统计、画像、成就统一由模块五负责；其他模块只负责生成事件与短期运行态。
4. **Agent 责任统一**：不做一个混乱的大 Agent，而是通过 5 个轻量 Agent Service 分别服务不同模块，再由统一 `AgentContextProvider` 提供历史画像。
5. **UI 风格统一**：整体界面必须简洁、明朗、温暖、有设计感，避免复杂仪表盘、红色惩罚、排行榜和黑色科技风。
6. **模块边界统一**：每个模块都是独立需求单元，但通过统一事件总线和本地服务接口拼接。

---

## 1. 产品总览

### 1.1 产品定位

FocusFlow 是一个面向存在 ADHD 特征、注意力启动困难、学习拖延或任务组织困难的学生用户的 **macOS 原生 Educational Agent App**。

它不是传统待办清单，也不是单纯番茄钟，而是一个嵌入用户学习过程的主动式 Agent：

```text
用户说出学习任务
    ↓
AI 帮用户拆成短小、具体、可执行的阶段
    ↓
悬浮窗陪用户执行当前阶段
    ↓
阶段结束后采集反馈并动态调整后续计划
    ↓
任务完成或中断时提供结算、安抚和正向反馈
    ↓
本地长期记录数据，形成用户画像和成就体系
```

产品核心隐喻是：

> 一个不评判、不催命、不制造羞耻感的「外置前额叶」，帮用户把学习任务变小、把时间感变清楚、把进步感变可见。

### 1.2 目标用户

主要用户：

- ADHD 学生；
- 有 ADHD 特征但未诊断的学生；
- 注意力容易漂移、难以启动学习任务的用户；
- 面对论文、考试、阅读、作业、presentation 等学习任务时容易拖延的用户。

产品不做医疗诊断，不评估 ADHD 严重程度，不替代医生、心理咨询师或学习障碍评估。

### 1.3 场景范围

MVP 固定服务于 **education / 学习相关任务**：

| 场景 | 示例 |
|---|---|
| 写作 | 课程论文、读书报告、实验报告、申请文书 |
| 阅读 | 英文论文、教材章节、课程文献、课前阅读 |
| 复习 | 期中/期末考试、小测、错题、PPT 课件 |
| 作业 | 编程作业、数学作业、在线测验、实验报告 |
| 展示 | 小组报告、课堂 presentation、演讲稿、PPT |
| 长期学习项目 | 毕业论文、课程项目、作品集、语言考试 |

暂不覆盖：家务、运动、健康管理、行政事务、商业工作项目。

### 1.4 五模块分工

| 模块 | 名称 | 核心定位 | 主要产出 |
|---|---|---|---|
| 模块一 | 任务输入与智能拆解 | 产品流程起点，把自然语言学习任务拆成可执行阶段 | `TaskPlan`、`StagePlan[]` |
| 模块二 | 阶段执行与本地提醒 | 执行过程管控，负责计时、悬浮窗、状态机、本地通知 | `StageExecutionResult`、执行事件 |
| 模块三 | 阶段反馈与动态优化 | 自适应中枢，采集反馈并优化后续阶段 | `StageFeedback`、`StageUpdate`、干预事件 |
| 模块四 | 任务闭环与情绪激励 | 情绪引擎，负责完成结算、中断安抚、轻量复盘 | `TaskClosureSummary`、情绪/复盘事件 |
| 模块五 | 个人数据中心与成就体系 | 长期记忆层，负责本地存储、画像、统计、成就 | `LearningEvent` 日志、`UserProfileSnapshot`、成就 |

### 1.5 模块责任边界总表

| 功能 | 归属模块 | 不应由谁实现 |
|---|---|---|
| 判断任务是否属于学习场景 | 模块一 | 模块二/三/四/五 |
| 初始阶段拆解与时长估算 | 模块一 | 模块二/三 |
| 倒计时与阶段运行状态 | 模块二 | 模块三/五 |
| 前后台、锁屏、重启后的计时校准 | 模块二 | 模块五 |
| 阶段结束后反馈采集 | 模块三 | 模块二 |
| 阶段反馈选项生成 | 模块三 | 模块二 |
| 后续阶段动态调整 | 模块三 | 模块一/二/四 |
| 全任务完成结算 | 模块四 | 模块二/三/五 |
| 中途放弃安抚 | 模块四 | 模块三只触发，不主导 |
| 历史任务查询 | 模块五 | 模块四 |
| 连续打卡、完成率、累计专注时长 | 模块五 | 模块二/四 |
| 成就解锁与展示队列 | 模块五 | 模块四只展示结果 |
| 长期用户画像 | 模块五 | 模块一/三只读取快照 |
| 原始事件长期存储 | 模块五 | 其他模块不得各自写长期日志 |

---

## 2. 统一技术栈

### 2.1 主技术栈

统一采用 **macOS 原生 App 技术栈**。

| 层级 | 技术选择 | 用途 |
|---|---|---|
| UI 层 | SwiftUI | 主窗口、个人中心、历史页、结算页、设置页 |
| 原生窗口能力 | AppKit | 悬浮窗、always-on-top、无边框窗口、窗口层级控制 |
| 状态管理 | Swift Observation / Combine | 任务状态、计时状态、反馈状态、个人中心状态同步 |
| 本地通知 | UserNotifications | 阶段到点、即将结束、休息结束等系统通知 |
| 语音合成 | AVSpeechSynthesizer | 本地 TTS，用于反馈、鼓励、安抚播报 |
| 语音识别 | Speech Framework | 本地/系统 ASR，用于语音反馈和情绪补充 |
| 全局快捷键 | AppKit Event Monitor / Carbon RegisterEventHotKey / 可封装 HotKeyManager | 暂停、跳过、呼出语音、标记分心 |
| 本地文件 | FileManager + Codable + JSONL | 隐藏文件记录事件，不使用数据库 |
| Secret 存储 | Keychain | DeepSeek API key 等敏感凭据放 Keychain；普通本地学习数据使用可读 JSON/JSONL 文件 |
| 图表 | Swift Charts / SwiftUI Canvas | 个人中心轻量趋势图、成就花园 |
| LLM 抽象 | `LLMClient` protocol | 任务拆解、反馈选项、动态优化、情绪文案、自然语言查询 |

### 2.2 为什么不统一采用 Tauri/Electron

模块二原文档提出 Tauri/Electron 可实现主窗 + 悬浮窗，但本产品定位是 **Mac App**，且需要深度使用 macOS 通知、TTS、ASR、全局快捷键、窗口层级和本地隐私存储。因此合并版本统一为：

```text
SwiftUI + AppKit + 本地 Service Layer
```

若团队已有 Web 前端资产，可保留 Tauri 作为备选，但本 PRD 的接口、数据模型和服务命名均以 Swift/macOS 原生实现为准。

### 2.3 前后端定义

本产品不是传统 Web 前后端架构。这里的「前端 / 后端」统一定义为：

| 名称 | 含义 |
|---|---|
| 前端 | SwiftUI / AppKit View、用户交互、动画、页面状态展示 |
| 后端 | App 内本地 Service Layer，包括 Agent、计时、事件存储、统计、成就、文件读写 |
| 远程服务 | 可选 LLM API。默认不上传用户原始历史数据，只有用户授权后才可调用 |

### 2.4 本地服务架构

```text
FocusFlowApp
 ├── UI Layer
 │   ├── TaskInputView
 │   ├── ExecutionCenterView
 │   ├── FloatingTimerWindow
 │   ├── StageFeedbackSheet
 │   ├── TaskClosureView
 │   ├── PersonalCenterView
 │   └── SettingsView
 │
 ├── Domain Service Layer
 │   ├── TaskPlanningService          // 模块一
 │   ├── ExecutionService             // 模块二
 │   ├── FeedbackOptimizationService  // 模块三
 │   ├── TaskClosureService           // 模块四
 │   ├── DataCenterService            // 模块五
 │   ├── AppEventBus                  // 统一事件总线
 │   ├── TaskRepository               // 当前任务计划读写
 │   ├── RuntimeStore                 // 当前执行态恢复
 │   └── AgentContextProvider         // 给各模块提供画像与上下文
 │
 ├── Agent Layer
 │   ├── TaskBreakdownAgent
 │   ├── FeedbackAgent
 │   ├── PlanOptimizationAgent
 │   ├── EmotionSupportAgent
 │   ├── ProfileAgent
 │   └── LLMClient protocol
 │
 └── Local Data Layer
     ├── .agent_data/events/*.jsonl
     ├── .agent_data/tasks/*.json
     ├── .agent_data/runtime/*.json
     ├── .agent_data/profile/*.json
     ├── .agent_data/achievements/*.json
     └── .agent_data/summaries/*.json
```

---

## 3. 统一 UI/UX 设计系统

### 3.1 设计目标

本产品的 UI 是核心竞争力之一。界面必须满足：

```text
简洁、明朗、温暖、好看、有设计感、低认知负担、非惩罚、非排行榜、非黑色科技风
```

用户打开 App 时，不应感觉自己进入一个复杂项目管理工具，而应感觉进入一个清楚、轻松、有陪伴感的学习辅助空间。

### 3.2 ADHD 友好设计原则

| 原则 | 具体要求 |
|---|---|
| 一屏一重点 | 当前界面只突出一个主要动作或状态 |
| 低启动成本 | 避免复杂表单，允许用户只输入一句话 |
| 清晰时间锚点 | 执行阶段必须有大号倒计时或视觉化时间流逝 |
| 大点击区域 | 所有核心操作按钮面积足够大，减少误触和犹豫 |
| 渐进展开 | 复杂信息默认折叠，用户需要时再展开 |
| 非惩罚语言 | 不出现失败、懒惰、不自律、效率太低等词 |
| 温和动画 | 动效可爱但克制，不闪烁、不强刺激、不打断心流 |
| 无排行榜 | 不与其他用户比较，只和用户自己的过去比较 |
| 可跳过 | 反馈、复盘、情绪记录均可跳过 |
| 可恢复叙事 | 中断不是失败，回来继续是值得奖励的行为 |

### 3.3 视觉风格

推荐色彩系统：

| 用途 | 颜色名 | 色值 | 说明 |
|---|---|---|---|
| 页面背景 | Warm Canvas | `#F7F4ED` | 纸张感背景，降低压迫 |
| 主色 | Focus Blue | `#5B7CFA` | 主按钮、当前进度 |
| 完成/恢复 | Mint Green | `#7BC99A` | 完成、恢复、积极反馈 |
| 成就点缀 | Peach | `#FFB86B` | 成就、里程碑、温暖提示 |
| 文本主色 | Ink Gray | `#2F3440` | 主文本 |
| 弱文本 | Soft Gray | `#8A8F98` | 辅助说明 |
| 安抚背景 | Soft Lavender | `#EEE9FF` | 中断安抚页 |

禁止：

- 大面积纯黑背景；
- 大面积红色警告；
- 高饱和荧光色；
- 密集表格和复杂仪表盘；
- 大量动效同时出现。

### 3.4 统一组件

| 组件 | 用途 | 设计要求 |
|---|---|---|
| Hero Card | 首屏核心状态 | 一句话 + 一个主按钮 |
| Bento Card | 个人中心和预览页 | 每卡只表达一个主题 |
| Floating Capsule | 悬浮窗 | 倒计时 + 2 个按钮，极简 |
| Feedback Choice Card | 阶段反馈选项 | 3-4 个大卡片，文案 ≤ 8 汉字 |
| Soft Toast | 轻量提示 | 不抢焦点，1-2 秒消失 |
| Gentle Sheet | 反馈/复盘浮层 | 非全屏，保留上下文 |
| Achievement Badge | 成就徽章 | 小而精致，不强刺激 |
| Timeline Row | 历史阶段记录 | 按日期/任务聚合，不密集 |

### 3.5 全局文案规则

推荐：

```text
先做一个小步骤。
已经开始了，这一步很重要。
回来继续也算进展。
先到这里也可以，进度已经保存。
这部分确实不容易，我们把它拆小一点。
```

禁止：

```text
你又没完成。
你应该更自律。
效率太低。
任务失败。
不要再拖延。
```

---

## 4. 统一数据模型与接口规范

### 4.1 命名规范

- Swift 类型使用 `UpperCamelCase`；
- Swift 字段使用 `lowerCamelCase`；
- JSON 文件序列化建议使用 `snake_case`；
- 所有时间戳同时记录：
  - `timestamp`：ISO8601；
  - `localDay`：用户本地日期，如 `2026-06-26`；
  - `timezoneIdentifier`：如 `Asia/Singapore`。

### 4.2 核心枚举

```swift
enum SourceModule: String, Codable {
    case module1TaskPlanning
    case module2Execution
    case module3FeedbackOptimization
    case module4ClosureEmotion
    case module5DataCenter
    case system
}

enum EducationTaskType: String, Codable {
    case writing
    case reading
    case examReview
    case homework
    case presentation
    case longTermProject
    case unknown
}

enum StageType: String, Codable {
    case startup
    case reading
    case writing
    case reviewing
    case problemSolving
    case organizing
    case presentationMaking
    case breakTime
    case other
}

enum TaskStatus: String, Codable {
    case draft
    case planned
    case active
    case paused
    case completed
    case gracefullyPaused
    case abandoned
    case archived
    case deleted
}

enum StageStatus: String, Codable {
    case idle
    case running
    case paused
    case overtime
    case completed
    case skipped
    case abandoned
    case adjusted
}

enum EndReason: String, Codable {
    case completedEarly
    case completedOnTime
    case completedAfterOvertime
    case userPaused
    case userSkipped
    case userAbandoned
    case timeoutPrompted
    case appInterrupted
}
```

### 4.3 任务计划模型

模块一创建，模块二执行，模块三可修改后续阶段，模块四结算，模块五记录事件和统计。

```swift
struct TaskPlan: Codable, Identifiable {
    let id: String
    var originalInput: String
    var title: String
    var taskType: EducationTaskType
    var status: TaskStatus
    var createdAt: Date
    var updatedAt: Date
    var deadline: Date?
    var estimatedTotalSeconds: Int
    var stages: [StagePlan]
    var metadata: [String: String]
}

struct StagePlan: Codable, Identifiable {
    let id: String
    let taskId: String
    var order: Int
    var title: String
    var instruction: String
    var completionCriteria: String
    var stageType: StageType
    var estimatedSeconds: Int
    var status: StageStatus
    var createdBy: SourceModule
    var parentStageId: String?
    var metadata: [String: String]
}
```

### 4.4 阶段运行态模型

模块二拥有。用于计时恢复，不作为长期统计的唯一依据。

```swift
struct StageRuntime: Codable {
    let taskId: String
    let stageId: String
    var status: StageStatus
    var startedAt: Date?
    var pauseStartedAt: Date?
    var pauseTotalSeconds: Int
    var plannedSeconds: Int
    var lastTickAt: Date?
    var monotonicAnchor: TimeInterval?
    var difficultyHitCount: Int
    var timeoutPrompted: Bool
}
```

### 4.5 阶段执行结果

模块二产出，模块三用于反馈和优化，模块五用于统计。

```swift
struct StageExecutionResult: Codable, Identifiable {
    let id: String
    let taskId: String
    let stageId: String
    let startedAt: Date
    let endedAt: Date
    let plannedSeconds: Int
    let actualFocusSeconds: Int
    let pauseCount: Int
    let pauseTotalSeconds: Int
    let overtimeSeconds: Int
    let difficultyHitCount: Int
    let timeoutPrompted: Bool
    let endReason: EndReason
    let endTrigger: EventTrigger
    let localDay: String
}

enum EventTrigger: String, Codable {
    case user
    case system
    case shortcut
    case voice
}
```

### 4.6 阶段反馈模型

模块三产出。

```swift
struct StageFeedback: Codable, Identifiable {
    let id: String
    let taskId: String
    let stageId: String
    let executionResultId: String
    let submittedAt: Date
    let selectedLabel: String?
    let freeText: String?
    let voiceTranscript: String?
    let intent: FeedbackIntent
    let difficulty: DifficultyLevel?
    let granularity: GranularityFeedback?
    let emotionTag: EmotionTag?
    let skipped: Bool
    let metadata: [String: String]
}

enum FeedbackIntent: String, Codable {
    case completed
    case tooHard
    case distracted
    case needBreak
    case needMoreTime
    case unclearInstruction
    case wantToQuit
    case other
    case skippedFeedback
}

enum DifficultyLevel: String, Codable {
    case easy
    case normal
    case hard
    case tooHard
}

enum GranularityFeedback: String, Codable {
    case tooSmall
    case justRight
    case tooLarge
}

enum EmotionTag: String, Codable {
    case calm
    case happy
    case tired
    case frustrated
    case overwhelmed
    case anxious
    case unknown
}
```

### 4.7 阶段更新模型

模块三产出，模块二和 `TaskRepository` 应用。

```swift
struct StageUpdate: Codable, Identifiable {
    let id: String
    let taskId: String
    let sourceStageId: String?
    let updateScope: StageUpdateScope
    let updatedStages: [StagePlan]
    let removedStageIds: [String]
    let reason: String
    let requiresUserConfirmation: Bool
    let createdAt: Date
}

enum StageUpdateScope: String, Codable {
    case currentStageOnly
    case remainingStages
    case entireTask
}
```

### 4.8 任务闭环摘要

模块四产出，模块五记录。

```swift
struct TaskClosureSummary: Codable, Identifiable {
    let id: String
    let taskId: String
    let closedAt: Date
    let closureType: TaskClosureType
    let totalPlannedSeconds: Int
    let totalFocusSeconds: Int
    let completedStageCount: Int
    let skippedStageCount: Int
    let abandonedStageCount: Int
    let keyBreakthroughs: [String]
    let encouragementText: String?
    let soothingText: String?
    let reviewItems: [ReviewItem]
    let emotionTag: EmotionTag?
    let archiveEventIds: [String]
}

enum TaskClosureType: String, Codable {
    case completed
    case gracefullyPaused
    case abandoned
    case archivedOnly
}

struct ReviewItem: Codable, Identifiable {
    let id: String
    let text: String
    let type: ReviewItemType
    var userConfirmed: Bool?
}

enum ReviewItemType: String, Codable {
    case highlight
    case suggestion
    case userNote
}
```

### 4.9 统一事件模型

所有模块都通过 `DataCenterService.recordEvent(_:)` 进入长期日志。模块一至模块四不直接写长期统计文件。

```swift
struct LearningEvent: Codable, Identifiable {
    let id: String
    let eventType: LearningEventType
    let sourceModule: SourceModule
    let timestamp: Date
    let localDay: String
    let timezoneIdentifier: String

    let taskId: String?
    let stageId: String?
    let relatedObjectId: String?

    let taskTitle: String?
    let taskType: EducationTaskType?
    let stageTitle: String?
    let stageType: StageType?

    let status: String?
    let plannedDurationSeconds: Int?
    let actualFocusSeconds: Int?
    let pauseCount: Int?

    let tags: [String]
    let metadata: [String: String]
}

enum LearningEventType: String, Codable {
    case taskCreated
    case taskPlanConfirmed
    case taskPlanUpdated
    case stageStarted
    case stagePaused
    case stageResumed
    case stageCompleted
    case stageSkipped
    case stageAbandoned
    case stageTimeoutPrompted
    case stageDifficultyRequested
    case stageFeedbackSubmitted
    case stageAdjusted
    case interventionTriggered
    case taskCompleted
    case taskGracefullyPaused
    case taskAbandoned
    case taskArchived
    case emotionMarked
    case reviewSubmitted
    case achievementUnlocked
    case manualCheckIn
    case dataExported
    case dataDeleted
}
```

### 4.10 用户画像快照

模块五生成，模块一、三、四读取。

```swift
struct UserProfileSnapshot: Codable {
    let preferredStageDurationSeconds: Int?
    let recommendedFirstStageSeconds: Int?
    let difficultStageTypes: [StageType]
    let easierStageTypes: [StageType]
    let effectiveInterventions: [InterventionType]
    let encouragementStyle: EncouragementStyle
    let rewardPreference: RewardPreference
    let streakSensitivity: SensitivityLevel
    let confidence: Double
    let lastUpdatedAt: Date
}

enum InterventionType: String, Codable {
    case splitSmaller
    case addShortBreak
    case simplifyInstruction
    case extendTime
    case switchTask
    case bodyDoubleEncouragement
}

enum EncouragementStyle: String, Codable {
    case gentleDirect
    case playful
    case quiet
    case minimal
}

enum RewardPreference: String, Codable {
    case quietBadge
    case softAnimation
    case noPopup
    case voiceEncouragement
}

enum SensitivityLevel: String, Codable {
    case low
    case medium
    case high
}
```

---

## 5. 统一模块通信与接口

### 5.1 通信原则

```text
模块一负责创建计划
模块二负责执行计划
模块三负责根据反馈修改计划
模块四负责结束任务并生成情绪闭环
模块五负责记录所有事件并生成长期画像
```

任何模块需要长期数据时，不直接读其他模块内部文件，而是通过模块五接口或 `AgentContextProvider` 获取。

### 5.2 核心服务接口

```swift
protocol TaskPlanningServiceProtocol {
    func createPlan(from input: String, context: UserProfileSnapshot?) async throws -> TaskPlan
    func refinePlan(_ task: TaskPlan, userInstruction: String) async throws -> TaskPlan
    func confirmPlan(_ task: TaskPlan) async throws
}

protocol ExecutionServiceProtocol {
    func startTask(_ taskId: String) async throws
    func startStage(taskId: String, stageId: String) async throws
    func pauseCurrentStage(trigger: EventTrigger) async throws
    func resumeCurrentStage(trigger: EventTrigger) async throws
    func completeCurrentStage(trigger: EventTrigger) async throws -> StageExecutionResult
    func skipCurrentStage(trigger: EventTrigger) async throws -> StageExecutionResult
    func abandonCurrentStage(trigger: EventTrigger) async throws -> StageExecutionResult
    func applyStageUpdate(_ update: StageUpdate) async throws
}

protocol FeedbackOptimizationServiceProtocol {
    func prepareFeedbackOptions(taskId: String, stageId: String) async throws -> [FeedbackOption]
    func submitFeedback(_ feedback: StageFeedback) async throws -> FeedbackOptimizationResult
    func handleTimeoutDifficulty(taskId: String, stageId: String, runtime: StageRuntime) async throws -> DifficultyPrompt
}

protocol TaskClosureServiceProtocol {
    func presentCompletion(taskId: String) async throws -> TaskClosureSummary
    func presentGracefulPause(taskId: String, reason: String?) async throws -> TaskClosureSummary
    func archiveTask(_ summary: TaskClosureSummary) async throws
}

protocol DataCenterServiceProtocol {
    func recordEvent(_ event: LearningEvent) async throws
    func getStats(range: StatsRange) async throws -> StatsSummary
    func getUserProfileSnapshot() async throws -> UserProfileSnapshot
    func updateProfileFromRecentEvents() async throws
    func checkAchievements(after event: LearningEvent) async throws -> [Achievement]
    func queryHistory(_ query: HistoryQuery) async throws -> [HistoryTaskCard]
}
```

### 5.3 统一事件总线

```swift
final class AppEventBus {
    static let shared = AppEventBus()

    func publish(_ event: LearningEvent) {
        // 1. 先进入内存事件流，供当前 UI 响应
        // 2. 再异步交给 DataCenterService 追加写入 JSONL
        // 3. 触发 StatsEngine / ProfileAgent / AchievementEngine 增量更新
    }
}
```

事件总线用途：

| 事件 | 产生模块 | 消费模块 |
|---|---|---|
| `taskPlanConfirmed` | 模块一 | 模块二、模块五 |
| `stageCompleted` | 模块二 | 模块三、模块四、模块五 |
| `stageFeedbackSubmitted` | 模块三 | 模块二、模块四、模块五 |
| `stageAdjusted` | 模块三 | 模块二、模块五 |
| `taskCompleted` | 模块四 | 模块五 |
| `taskGracefullyPaused` | 模块四 | 模块二、模块五 |
| `achievementUnlocked` | 模块五 | 模块四、个人中心 |

### 5.4 数据拥有权

| 数据 | 读写归属 | 说明 |
|---|---|---|
| `TaskPlan` | `TaskRepository` 统一管理；模块一创建，模块三可修改 | 不属于某一个 UI 页面 |
| `StageRuntime` | 模块二 / RuntimeStore | 用于计时恢复，不用于长期统计唯一依据 |
| `StageFeedback` | 模块三创建；模块五记录事件 | 反馈原文可本地保存 |
| `TaskClosureSummary` | 模块四创建；模块五记录事件 | 结算与安抚结果 |
| `LearningEvent` | 模块五长期存储 | 其他模块只生成事件，不写长期日志 |
| `UserProfileSnapshot` | 模块五生成 | 其他模块只读，不直接写 |
| `Achievement` | 模块五生成 | UI 展示可由模块四或个人中心承载 |

### 5.5 统一端到端流程

#### 5.5.1 新建任务流程

```text
用户输入学习任务
    ↓
模块一 TaskPlanningService.createPlan
    ↓
读取模块五 UserProfileSnapshot，用于个性化阶段时长与第一步大小
    ↓
生成 TaskPlan + StagePlan[]
    ↓
用户预览并确认
    ↓
TaskRepository 保存 TaskPlan
    ↓
AppEventBus 发布 taskCreated / taskPlanConfirmed
    ↓
模块二进入执行页
```

#### 5.5.2 阶段执行完成流程

```text
模块二计时运行
    ↓
用户点击「我完成了这一步」或阶段到点
    ↓
ExecutionService 生成 StageExecutionResult
    ↓
AppEventBus 发布 stageCompleted / stageSkipped / stageAbandoned
    ↓
模块三打开反馈入口
    ↓
模块五记录事件并更新统计
    ↓
如果是最后阶段，模块四准备结算
```

#### 5.5.3 阶段反馈与动态优化流程

```text
模块三展示情境化反馈选项
    ↓
用户点选/语音回答/跳过
    ↓
FeedbackOptimizationService 生成 StageFeedback
    ↓
如需优化，生成 StageUpdate
    ↓
用户确认或轻量自动生效
    ↓
TaskRepository 更新后续 StagePlan
    ↓
模块二刷新阶段清单和时长
    ↓
模块五记录 stageFeedbackSubmitted / stageAdjusted
```

#### 5.5.4 中断与安抚流程

```text
模块二检测放弃/跳过/长时间无响应
    ↓
模块三判断是否严重中断
    ↓
如严重，发送 InterventionRequest 给模块四
    ↓
模块四展示中途放弃安抚页
    ↓
用户选择：保存进度 / 拆小一点 / 休息 / 换任务 / 关闭
    ↓
模块四生成 TaskClosureSummary 或任务暂停状态
    ↓
模块五记录长期事件并更新画像
```

#### 5.5.5 任务完成与成就流程

```text
最后阶段完成 / 用户主动标记任务完成
    ↓
模块四聚合任务执行数据
    ↓
生成结算页、鼓励文案、轻量复盘
    ↓
发布 taskCompleted / taskArchived / emotionMarked / reviewSubmitted
    ↓
模块五更新统计、画像、成就
    ↓
若成就解锁且当前非专注阶段，展示轻量 Toast
    ↓
个人中心和历史页可查询完整记录
```

---

## 6. 模块一：任务输入与智能拆解需求

### 6.1 模块定位

模块一是产品的学习任务入口，负责把用户的一句话学习任务转化为多个短小、具体、有时间预估和完成标准的阶段。

模块一必须让用户感觉：

```text
我现在不需要完成全部任务。
我只需要先做第一个小步骤。
这个步骤大概需要几分钟。
做到什么程度就可以停。
```

### 6.2 负责范围

模块一负责：

- 接收教育相关任务自然语言输入；
- 判断输入清晰度；
- 对模糊任务进行最多 3 个轻量追问；
- 识别教育任务类型；
- 生成 `TaskPlan` 和 `StagePlan[]`；
- 确保第一阶段足够低门槛；
- 提供拆解结果预览和轻量编辑；
- 用户确认后把计划交给模块二。

模块一不负责：

- 阶段计时；
- 阶段反馈；
- 动态优化；
- 情绪结算；
- 长期统计。

### 6.3 前端页面

#### 6.3.1 学习任务输入页

核心元素：

- 主输入框；
- 主要按钮：「帮我拆小」；
- 任务模板 Chips；
- 温和辅助文案。

推荐辅助文案：

```text
不用想完整，先把学习任务写下来。
你只需要说出要做什么，我会帮你找到第一步。
```

输入框 placeholder：

```text
比如：我明天要交论文，但还没开始
```

#### 6.3.2 轻量追问卡片

触发条件：

- 用户输入过于模糊，如「我要学习」「好多作业」「我要复习一下」；
- 无法判断任务类型、对象或优先级。

规则：

- 最多追问 3 个问题；
- 每次只问一个重点；
- 优先选择题；
- 允许跳过；
- 不评价用户输入不清楚。

示例：

```text
我们先不用处理全部。你想先从哪一个开始？

[最急的] [最简单的] [最让我焦虑的] [帮我选一个]
```

#### 6.3.3 拆解结果预览页

展示内容：

- 任务标题；
- 教育任务类型；
- 阶段数量；
- 预计总时长；
- 第一阶段高亮；
- 阶段列表；
- 每阶段预计时间和完成标准；
- 操作按钮：确认开始、拆小一点、减少步骤、改时间、重新生成。

### 6.4 智能拆解规则

每个 Stage 必须回答：

```text
我要做什么？
我要做到哪里停？
大概需要多久？
```

ADHD 友好拆解原则：

| 规则 | 要求 |
|---|---|
| 一阶段一件事 | 不把阅读、总结、写作塞进同一步 |
| 动作具体 | 使用打开、找到、新建、写下、阅读、标记、做 3 题 |
| 时间短 | 启动阶段 2-5 分钟，普通阶段尽量不超过 25 分钟 |
| 完成标准清楚 | 明确做到哪里停 |
| 允许粗糙开始 | 写作和复习不要求一开始完美 |

### 6.5 第一阶段冷启动要求

第一阶段必须：

- 2-5 分钟；
- 不需要复杂判断；
- 能立刻执行；
- 让用户获得启动感。

示例：

| 任务类型 | 第一阶段 |
|---|---|
| 写论文 | 打开作业要求，找到主题和截止时间 |
| 阅读论文 | 打开 PDF，只看标题和摘要 |
| 复习考试 | 找到考试范围或第一份课件 |
| 做作业 | 打开作业页面，数一共有几题 |
| 做 presentation | 新建 PPT，写下展示主题 |

### 6.6 模块一接口

#### 输入

```swift
struct TaskInputRequest: Codable {
    let rawInput: String
    let createdAt: Date
    let userProfileSnapshot: UserProfileSnapshot?
}
```

#### 输出

```swift
struct TaskPlanDraft: Codable {
    let task: TaskPlan
    let confidence: Double
    let clarificationQuestions: [ClarificationQuestion]
}

struct ClarificationQuestion: Codable, Identifiable {
    let id: String
    let question: String
    let options: [String]
    let skippable: Bool
}
```

#### 事件

模块一必须发布：

| 时机 | 事件 |
|---|---|
| 用户提交输入 | `taskCreated` |
| 用户确认计划 | `taskPlanConfirmed` |
| 用户编辑计划 | `taskPlanUpdated` |

### 6.7 模块一验收标准

1. 用户可以用自然语言输入教育任务；
2. 系统能识别写作、阅读、复习、作业、展示、长期项目；
3. 模糊任务能轻量追问；
4. 每个阶段包含标题、指令、预计时间、完成标准、阶段类型；
5. 第一阶段必须低门槛；
6. 单阶段尽量不超过 25 分钟；
7. 用户可以预览和编辑计划；
8. 确认后产生标准 `TaskPlan` 并交给模块二；
9. 所有文案无羞耻感和压迫感。

---

## 7. 模块二：阶段执行与本地提醒需求

### 7.1 模块定位

模块二负责让用户真正进入并完成当前阶段。它是产品的执行控制层，核心是：

```text
主窗口执行页 + 常驻悬浮窗 + 准确计时 + 本地提醒 + 阶段状态机
```

### 7.2 负责范围

模块二负责：

- 主窗执行中心；
- always-on-top 悬浮窗；
- 单阶段计时；
- 前后台、锁屏、休眠、重启计时校准；
- 阶段开始、暂停、继续、完成、跳过、放弃、超时状态机；
- 单焦点多任务切换；
- 到点无操作时触发困难询问；
- 生成 `StageExecutionResult`。

模块二不负责：

- 反馈选项生成；
- 动态优化算法；
- 任务完成后的情绪激励；
- 长期统计与成就。

### 7.3 前端页面

#### 7.3.1 执行中心页

展示：

- 当前任务标题；
- 当前阶段标题；
- 具象化行动指令；
- 第 N / 共 M 阶段；
- 大号倒计时；
- 进度环或时间色块；
- 主按钮：开始 / 暂停 / 继续 / 我完成了这一步；
- 辅助按钮：+5 分钟 / 跳过 / 放弃任务；
- 阶段清单默认折叠。

#### 7.3.2 悬浮窗

悬浮窗是 ADHD 友好的时间锚点。

内容只保留：

```text
倒计时
[我遇到困难]
[我完成了这一步]
```

规则：

- always-on-top；
- 无边框；
- 可拖动；
- 半透明可调；
- 主窗最小化时仍运行；
- 最后 2 分钟可轻微呼吸动效，不闪烁报警。

### 7.4 计时引擎规则

计时不能依赖 UI tick 累加，而必须基于时间戳重算。

```text
remainingSeconds = plannedSeconds - (now - startedAt - pauseTotalSeconds)
```

要求：

- UI 每秒刷新；
- 前后台切换后用绝对时间重算；
- 用 monotonic clock 兜底防系统时间变更；
- App 崩溃重启后读取 `runtime/active_stage.json` 恢复；
- 常见场景误差 ≤ 2 秒。

### 7.5 状态机

```text
idle
  ↓ start
running
  ↔ pause/resume
paused
  ↓ resume
running
  ↓ countdown ends
 overtime / timeoutPrompted
  ↓ user action
completed / skipped / abandoned
```

规则：

- 暂停时间不计入 `actualFocusSeconds`；
- 开始新阶段时，当前运行阶段自动暂停；
- 全局同一时刻只有一个 running/overtime 阶段；
- 每次状态变化发布事件给模块五；
- 阶段结束后把 `StageExecutionResult` 交给模块三。

### 7.6 到点无操作主动询问困难

归属统一如下：

| 内容 | 归属 |
|---|---|
| 判断倒计时归零 | 模块二 |
| 判断用户是否无操作 | 模块二 |
| 展开悬浮窗/触发询问 UI | 模块二 |
| 生成具体困难询问文案 | 模块三 `FeedbackAgent` |
| 用户回答后的优化策略 | 模块三 |

流程：

```text
倒计时归零
    ↓
用户没有点「完成」或「困难」
    ↓
模块二发布 stageTimeoutPrompted
    ↓
模块三生成 DifficultyPrompt
    ↓
悬浮窗展开显示：这一步卡在哪了？
    ↓
用户选择：完成 / 多给 5 分钟 / 卡住了 / 想休息 / 放弃
    ↓
模块二处理计时动作，模块三处理反馈和优化
```

### 7.7 模块二接口

#### 输入

```swift
func startTask(_ task: TaskPlan)
func applyStageUpdate(_ update: StageUpdate)
```

#### 输出

```swift
func completeCurrentStage(trigger: EventTrigger) async throws -> StageExecutionResult
func skipCurrentStage(trigger: EventTrigger) async throws -> StageExecutionResult
func abandonCurrentStage(trigger: EventTrigger) async throws -> StageExecutionResult
```

#### 事件

| 时机 | 事件 |
|---|---|
| 阶段开始 | `stageStarted` |
| 暂停 | `stagePaused` |
| 恢复 | `stageResumed` |
| 完成 | `stageCompleted` |
| 跳过 | `stageSkipped` |
| 放弃 | `stageAbandoned` |
| 到点无操作 | `stageTimeoutPrompted` |
| 点击困难 | `stageDifficultyRequested` |

### 7.8 模块二验收标准

1. 主窗与悬浮窗状态实时同步；
2. 切后台、锁屏、重启后倒计时准确；
3. 同一时刻只有一个阶段计时；
4. 暂停时间不计入专注时间；
5. 到点无操作时触发困难询问；
6. 阶段结束产生标准 `StageExecutionResult`；
7. 拒绝系统通知权限时，悬浮窗仍可提醒；
8. 所有提醒文案短、正向、无评判。

---

## 8. 模块三：阶段反馈与动态优化需求

### 8.1 模块定位

模块三是系统的自适应中枢，负责建立：

```text
阶段执行结果 → 情境化反馈 → 语义理解 → 后续阶段优化 → 状态回写
```

### 8.2 负责范围

模块三负责：

- 阶段结束后的反馈弹窗；
- 到点困难询问文案生成；
- 语音反馈和 ASR 语义理解；
- 用户反馈意图识别；
- 后续阶段动态优化；
- 优化预览与确认；
- 主动干预；
- 向模块二回写 `StageUpdate`；
- 向模块四发送严重中断信号。

模块三不负责：

- 基础倒计时；
- 全任务完成结算；
- 长期成就统计。

### 8.3 前端组件

| 组件 | 触发时机 | 功能 |
|---|---|---|
| 阶段反馈弹窗 | 阶段完成/跳过/放弃/到点 | 采集用户状态 |
| 计划调整预览页 | 反馈后需要调整 | 展示原方案 vs 新方案 |
| 主动干预弹窗 | 连续未完成/长时间无响应 | 提供恢复、休息、退出路径 |
| 轻量调整提示条 | 微调后续阶段 | 不阻断用户，附撤销 |
| 语音浮层 | 语音模式开启 | TTS + ASR 低操作负担 |

### 8.4 阶段反馈弹窗规则

触发后暂停阶段计时，避免反馈过程制造时间焦虑。

选项规则：

- 由 AI 根据当前任务和阶段动态生成；
- 3-4 个主要选项；
- 每个选项 ≤ 8 个汉字；
- 配 Emoji 或轻量图标；
- 允许「其他情况」折叠输入；
- 允许跳过。

示例：

阅读论文阶段：

```text
[读完摘要了 📄] [遇到生词 🔍] [走神了 😵] [需要休息 🍵]
```

写报告大纲阶段：

```text
[大纲完成 ✍️] [卡在开头 🚧] [想换思路 🔄] [查点资料 📚]
```

### 8.5 动态优化规则

模块三根据 `StageExecutionResult + StageFeedback + UserProfileSnapshot` 生成后续调整。

可用策略：

| 反馈模式 | 优化策略 |
|---|---|
| 太难 | 拆小阶段、降低完成标准 |
| 时间不够 | 延长同类阶段时间或加入检查点 |
| 走神 | 插入 3 分钟恢复阶段或改短阶段 |
| 指令不清楚 | 重写后续阶段 instruction |
| 任务太碎 | 合并部分阶段 |
| 想放弃 | 触发模块四安抚，而非继续强推 |

安全边界：

- 单阶段默认不超过 25 分钟；
- 单次优化新增阶段不超过 3 个；
- 总阶段数超过 15 时提示用户「计划可能太细」；
- 不自动删除用户已完成阶段；
- 大幅调整必须用户确认。

### 8.6 严重中断判断

若满足以下任一条件，模块三向模块四发送 `InterventionRequest`：

- 连续 2 个阶段未完成；
- 同一阶段 2 次主动选择「不想做了」；
- 到点无响应且超过 10 分钟；
- 用户明确表达强挫败，如「我做不了了」「算了」；
- 用户连续标记 overwhelmed / frustrated。

```swift
struct InterventionRequest: Codable {
    let taskId: String
    let stageId: String?
    let interruptionType: InterruptionType
    let urgency: InterventionUrgency
    let lastFeedback: StageFeedback?
    let suggestedTone: EncouragementStyle
    let createdAt: Date
}
```
## 用户卡壳时的分层提示机制（Demo 版）

### 1. 功能定位

当用户在执行阶段中点击「我遇到困难」，或阶段到点后长时间没有操作时，系统需要主动帮助用户从卡壳状态回到可执行状态。

本功能的目标不是直接替用户完成学习任务，而是提供一个足够小、足够明确、可以立刻开始的下一步。

### 2. 职责归属

| 模块  | 职责                          |
| --- | --------------------------- |
| 模块二 | 检测用户卡壳行为，如点击「我遇到困难」、阶段到点无操作 |
| 模块三 | 生成卡壳提示、拆小建议和可选帮助动作          |
| 模块四 | 当用户表现出明显放弃或情绪低落时，提供安抚引导     |
| 模块五 | 记录卡壳事件，用于长期用户画像更新           |

### 3. 触发条件

满足以下任一条件时触发卡壳帮助：

1. 用户在悬浮窗点击「我遇到困难」；
2. 阶段倒计时结束后，用户没有点击「完成」或「困难」；
3. 用户连续 2 次在相似阶段选择「太难」「不想做」「卡住了」。

Demo 阶段优先实现前两种触发条件。

### 4. 提示策略

系统采用三层提示，不直接默认代做。

#### 第一层：情绪承接

先用一句低压力文案接住用户状态。

示例：

```text
没关系，这一步确实容易卡。
```

或：

```text
先不用做完整，我们只处理一个小点。
```

#### 第二层：最小下一步

给用户一个 1-3 分钟内可以完成的小动作。

示例：

```text
现在只需要看摘要最后两句话，找出作者说“本文做了什么”。
```

或：

```text
先不用写完整段落，只写下 3 个关键词。
```

#### 第三层：可选帮助

提供 3-4 个按钮，让用户选择需要的帮助程度。

| 按钮      | 作用             |
| ------- | -------------- |
| 给点提示    | 展示一个更具体的引导问题   |
| 拆小一点    | 将当前阶段拆成更小步骤    |
| 给个例子    | 给一个可参考的示例开头或模板 |
| 休息 3 分钟 | 暂停当前阶段，启动短休息   |

### 5. UI 展示形式

卡壳提示在悬浮窗中展开，不跳转大页面。

展示结构：

```text
[一句安抚文案]

[一个最小下一步]

[给点提示] [拆小一点]
[给个例子] [休息 3 分钟]
```

UI 要求：

* 文案总长度不超过 80 字；
* 每个按钮不超过 5 个字；
* 不使用红色警告；
* 不出现「失败」「你没完成」「效率太低」等表达；
* 用户可以一键关闭，不强制回应。

### 6. 交互流程

```text
用户点击「我遇到困难」
    ↓
模块二发送 stuck_help_requested 事件
    ↓
模块三读取当前 stage 信息
    ↓
生成：
    - 一句情绪承接
    - 一个最小下一步
    - 3-4 个帮助按钮
    ↓
悬浮窗展开卡壳帮助卡片
    ↓
用户选择：
    ├── 给点提示 → 展示一个引导问题
    ├── 拆小一点 → 模块三生成更小步骤
    ├── 给个例子 → 展示一个简短模板或示例
    └── 休息 3 分钟 → 模块二暂停计时
```

### 7. 简化接口定义

#### 模块二 → 模块三

```swift
struct StuckHelpRequest: Codable {
    let taskId: String
    let stageId: String
    let taskTitle: String
    let stageTitle: String
    let instruction: String
    let plannedSeconds: Int
    let elapsedSeconds: Int
    let trigger: StuckTrigger
}

enum StuckTrigger: String, Codable {
    case userClickedDifficulty
    case timeoutNoAction
}
```

#### 模块三 → 前端

```swift
struct StuckHelpResponse: Codable {
    let comfortText: String
    let nextSmallStep: String
    let actions: [StuckHelpAction]
}

struct StuckHelpAction: Codable {
    let title: String
    let actionType: StuckActionType
}

enum StuckActionType: String, Codable {
    case hint
    case splitSmaller
    case example
    case shortBreak
}
```

### 8. Demo 版本实现范围

Demo 只需要实现以下能力：

1. 用户点击「我遇到困难」后展示卡壳帮助卡片；
2. 阶段到点无操作后自动展示卡壳帮助卡片；
3. 卡片包含一句安抚文案、一个最小下一步、四个按钮；
4. 「休息 3 分钟」可以真实暂停计时；
5. 「给点提示」「拆小一点」「给个例子」Demo 阶段可以先展示预设文案；
6. 每次触发写入模块五事件日志。

暂不实现复杂能力：

* 不做多轮深度对话；
* 不做复杂心理状态判断；
* 不做完整作业代写；
* 不做长期情绪分析；
* 不做云端同步。

### 9. 示例

当前阶段：

```text
阅读第一篇论文摘要
```

用户点击：

```text
我遇到困难
```

系统展示：

```text
没关系，英文摘要信息量很大。

先不用全部看懂。现在只看最后两句话，找出作者说“本文做了什么”。

[给点提示] [拆小一点]
[给个例子] [休息3分钟]
```

### 10. 验收标准

| 测试项     | 通过标准                              |
| ------- | --------------------------------- |
| 点击困难按钮  | 1 秒内展示卡壳帮助卡片                      |
| 到点无操作   | 自动展示卡壳帮助卡片                        |
| 文案长度    | 总文案不超过 80 字                       |
| 帮助按钮    | 至少包含「给点提示」「拆小一点」「休息 3 分钟」         |
| 休息功能    | 点击后当前阶段暂停 3 分钟                    |
| 数据记录    | 每次触发都写入 `stuck_help_requested` 事件 |
| ADHD 友好 | 不出现责备、羞辱、失败类文案                    |

### 8.7 模块三接口

```swift
struct FeedbackOption: Codable, Identifiable {
    let id: String
    let label: String
    let emoji: String?
    let intent: FeedbackIntent
}

struct DifficultyPrompt: Codable {
    let promptText: String
    let options: [FeedbackOption]
}

struct FeedbackOptimizationResult: Codable {
    let feedback: StageFeedback
    let stageUpdate: StageUpdate?
    let interventionRequest: InterventionRequest?
    let lightweightMessage: String?
}
```

### 8.8 事件

模块三必须发布：

| 时机 | 事件 |
|---|---|
| 用户提交反馈 | `stageFeedbackSubmitted` |
| 用户跳过反馈 | `stageFeedbackSubmitted` with skipped |
| 生成并应用更新 | `stageAdjusted` |
| 主动干预触发 | `interventionTriggered` |
| 用户标记分心 | `stageFeedbackSubmitted` + metadata |

### 8.9 模块三验收标准

1. 不同任务阶段生成不同反馈选项；
2. 所有选项 ≤ 8 个汉字；
3. 反馈弹窗不全屏、不强迫填写；
4. 用户反馈「太难」后，后续阶段能变小；
5. 用户反馈「时间不够」后，同类阶段时间可调整；
6. 大幅调整需要预览和确认；
7. 调整后模块二阶段列表同步更新；
8. 严重中断能触发模块四安抚；
9. 语音失败能降级为视觉弹窗；
10. 快捷键响应不抢焦点。

---

## 9. 模块四：任务闭环与情绪激励需求

### 9.1 模块定位

模块四是情绪引擎与正向反馈中心。它负责在任务生命周期终点提供：

```text
完成结算 / 中断安抚 / 轻量复盘 / 归档触发 / 情绪支持
```

它的目标不是评判用户是否高效，而是把用户已经做过的部分看见、承认并保存。

### 9.2 负责范围

模块四负责：

- 全任务完成后的结算页；
- 个性化鼓励话术；
- 中途放弃或严重中断后的安抚页；
- 轻量复盘；
- 阶段过渡鼓励；
- 情绪记录；
- 任务归档触发；
- 把任务闭环事件发送给模块五。

模块四不负责：

- 任务拆解；
- 阶段计时；
- 阶段反馈优化；
- 长期统计计算。

### 9.3 任务结算页

触发条件：

- 所有阶段完成；
- 用户主动标记任务完成；
- 用户完成到自定义目标并选择闭环。

展示内容：

- 动态标题，如「报告大纲搞定了 🎉」；
- 完成轨迹时间线；
- 各阶段状态；
- 总专注时长；
- 关键突破点；
- 个性化鼓励文案；
- 可选情绪记录；
- 按钮：「关闭」「查看历史」。

规则：

- 不强调用时偏差；
- 不说「效率高/低」；
- 关键突破点优先展示「困难但完成」；
- 动效轻柔，完成音效可关闭。

### 9.4 中途放弃安抚页

触发条件：

- 用户点击放弃任务；
- 模块三发送高紧急度 `InterventionRequest`；
- 用户连续中断并表达强烈抗拒。

文案框架：

```text
先到这里也可以。
你已经完成的部分都保存好了。
这不是失败，只是今天先暂停。
```

选项：

```text
[保存进度 🌙]
[拆小一点 🔧]
[休息 10 分钟 🍵]
[换个任务 🔄]
[只是关闭]
```

行为归属：

| 用户选择 | 处理 |
|---|---|
| 保存进度 | 模块四生成 `TaskClosureSummary(type: gracefullyPaused)`，模块五记录 |
| 拆小一点 | 模块四调用模块三/模块一重新拆分剩余阶段 |
| 休息 10 分钟 | 模块二启动 break stage 或本地提醒 |
| 换个任务 | 返回模块一输入页 |
| 只是关闭 | 保存当前进度，静默归档 |

### 9.5 轻量复盘

结算后可展示 2-3 条系统总结，用户只需确认或跳过。

示例：

```text
你在读论文阶段调整了 2 次计划，最后找到了能继续的方法。
写大纲阶段比预估快了一些，下次可以先从大纲开始。
```

规则：

- 用户不需要主动填写长文本；
- 每条复盘可点「同意」「不太对」；
- 可补充一句，但不强制；
- 复盘结果作为事件进入模块五。

### 9.6 话术生成规则

模块四使用 `EmotionSupportAgent`，输入：

- `TaskPlan`；
- 所有 `StageExecutionResult`；
- 所有 `StageFeedback`；
- `UserProfileSnapshot`；
- 模块三中断信号；
- 近期历史表现摘要。

输出：

- 主鼓励文案；
- 安抚文案；
- 阶段过渡鼓励；
- 复盘条目。

约束：

- 主文案 ≤ 50 字；
- 安抚主文案 ≤ 60 字；
- 不与他人比较；
- 不使用「必须」「应该」「失败」「懒惰」；
- 语气像朋友陪伴，不像老师评价。

### 9.7 模块四接口

```swift
enum InterruptionType: String, Codable {
    case repeatedIncomplete
    case activeQuit
    case longNoResponse
    case emotionalOverload
}

enum InterventionUrgency: String, Codable {
    case low
    case medium
    case high
}
```

```swift
func presentCompletion(taskId: String) async throws -> TaskClosureSummary
func presentGracefulPause(taskId: String, reason: String?) async throws -> TaskClosureSummary
func archiveTask(_ summary: TaskClosureSummary) async throws
```

### 9.8 事件

模块四必须发布：

| 时机 | 事件 |
|---|---|
| 任务完成 | `taskCompleted` |
| 优雅暂停 | `taskGracefullyPaused` |
| 放弃任务 | `taskAbandoned` |
| 任务归档 | `taskArchived` |
| 标记情绪 | `emotionMarked` |
| 提交复盘 | `reviewSubmitted` |

### 9.9 模块四验收标准

1. 完成任务后 500ms 内展示结算页；
2. 结算页能展示阶段轨迹、总专注时长、关键突破点；
3. 中途放弃不显示「失败」；
4. 安抚页提供保存、拆小、休息、换任务、关闭；
5. 情绪记录可选，不阻塞流程；
6. 复盘可跳过；
7. 归档后模块五能查询历史；
8. 鼓励和安抚文案符合零指责规则。

---

## 10. 模块五：个人数据中心与成就体系需求

### 10.1 模块定位

模块五是长期数据沉淀、用户画像和成就体系的统一负责人。

它要回答：

```text
用户哪天做了什么？
完成了多少？
专注了多久？
在哪类任务上容易卡住？
什么干预方式有效？
有哪些进步值得被看见？
```

### 10.2 负责范围

模块五负责：

- 本地隐藏文件存储；
- 事件日志追加写入；
- 历史任务查询；
- 统计计算；
- 用户画像；
- 成就规则；
- 个人中心 UI；
- 隐私、导出、删除、重置。

模块五不负责：

- 创建任务；
- 计时；
- 即时反馈弹窗；
- 情绪文案生成。

### 10.3 本地存储目录

```text
~/Library/Application Support/<BundleIdentifier>/.agent_data/
 ├── events/
 │   ├── 2026-06.jsonl
 │   └── 2026-07.jsonl
 ├── tasks/
 │   ├── task_001.json
 │   └── task_002.json
 ├── runtime/
 │   └── active_stage.json
 ├── summaries/
 │   ├── daily/2026-06-26.json
 │   └── weekly/2026-W26.json
 ├── profile/
 │   ├── user_profile.json
 │   └── profile_snapshots.jsonl
 ├── achievements/
 │   ├── unlocked.json
 │   └── pending_queue.json
 ├── settings/
 │   └── privacy.json
 └── export/
```

归属：

| 目录 | 主要写入者 | 说明 |
|---|---|---|
| `events/` | 模块五 | 所有长期事件日志 |
| `tasks/` | TaskRepository | 当前/历史任务计划 |
| `runtime/` | 模块二 | 当前执行态恢复 |
| `summaries/` | 模块五 | 可删除重算的统计缓存 |
| `profile/` | 模块五 | 用户画像 |
| `achievements/` | 模块五 | 成就状态 |
| `settings/` | SettingsService | 隐私、语音、快捷键设置 |

### 10.4 事件存储规则

- 采用 JSON Lines，一行一个 `LearningEvent`；
- 按月份拆分文件；
- 所有写入幂等检查 `event.id`；
- 写入失败进入 retry queue；
- summaries 可由 events 重算；
- 其他模块不得直接修改 `events/*.jsonl`。

示例：

```json
{
  "id": "evt_20260626_103012_ab12",
  "event_type": "stage_completed",
  "source_module": "module2Execution",
  "timestamp": "2026-06-26T10:30:12+08:00",
  "local_day": "2026-06-26",
  "timezone_identifier": "Asia/Singapore",
  "task_id": "task_001",
  "stage_id": "stage_003",
  "task_title": "准备小组报告",
  "task_type": "presentation",
  "stage_title": "阅读第一篇论文摘要",
  "stage_type": "reading",
  "status": "completed",
  "planned_duration_seconds": 600,
  "actual_focus_seconds": 480,
  "pause_count": 1,
  "tags": ["reading", "paper"],
  "metadata": {
    "end_reason": "completedOnTime",
    "timeout_prompted": "false"
  }
}
```

### 10.5 隐私规则

默认规则：

1. 数据只保存在本机；
2. 默认不上传历史记录；
3. 用户可查看、导出、删除全部数据；
4. 用户可关闭 Agent 画像；
5. 用户可清空画像但保留历史；
6. 调用远程 LLM 时只允许上传当前任务上下文和脱敏摘要；
7. 不记录屏幕截图、键盘输入、网页全文、论文全文；
8. 不做医学诊断。

### 10.6 用户画像 ProfileAgent

画像字段：

| 字段 | 用途 |
|---|---|
| `preferredStageDurationSeconds` | 给模块一/三建议阶段时长 |
| `recommendedFirstStageSeconds` | 给模块一建议第一阶段大小 |
| `difficultStageTypes` | 给模块三生成反馈选项和干预策略 |
| `effectiveInterventions` | 给模块三/四选择干预方式 |
| `encouragementStyle` | 给模块四生成文案 |
| `rewardPreference` | 给模块五控制成就展示强度 |
| `streakSensitivity` | 判断是否展示严格连续天数 |
| `confidence` | 防止数据不足时过度推断 |

画像更新规则：

- 最近 14 天权重最高；
- 最近 30 天用于趋势；
- 同一模式至少出现 3 次才写入；
- 单次异常不改变画像；
- 数据不足显示「还在了解你的学习节奏」；
- 用户可标记画像不准确。

### 10.7 个人中心页面

信息架构：

```text
个人中心
 ├── 顶部身份区
 ├── 今日状态 Hero Card
 ├── 三个核心指标 Mini Cards
 ├── 本周轻量趋势
 ├── 成就花园 / 星图
 ├── Agent 观察卡片
 └── 隐私与数据入口
```

默认只展示 3 个核心指标：

1. 学习节奏；
2. 本周专注；
3. 阶段完成。

Hero Card 示例：

```text
你这周已经回到学习里 4 天了。

[继续上次任务]
```

Agent 观察示例：

```text
我注意到：你在 8-12 分钟的阅读阶段更容易完成。
下次读论文时，我会优先帮你拆成这个长度。

[不准确？点这里修改]
```

### 10.8 历史记录页

支持查询：

| 查询方式 | 示例 |
|---|---|
| 日期 | 今天、昨天、最近 7 天、本月 |
| 状态 | 已完成、进行中、暂停、归档 |
| 任务类型 | 写作、阅读、复习、作业、展示 |
| 阶段类型 | 启动、阅读、写作、做题、整理 |
| 关键词 | 小组报告、英文论文 |
| 自然语言 | 找上周读论文的记录 |

无数据库查询逻辑：

```text
HistoryQueryService 解析条件
    ↓
按日期范围读取 events/*.jsonl
    ↓
过滤 task_type / status / keyword
    ↓
按 local_day + task_id 聚合
    ↓
生成 HistoryTaskCardViewModel
```

### 10.9 核心统计规则

#### 有效学习日

满足任一条件：

- 完成至少 1 个阶段；
- 有效专注 ≥ 5 分钟；
- 完成 1 个任务；
- 用户手动确认今日学习过。

#### 连续学习天数

```text
strict_streak_days = 从最近一个有效学习日向前连续计算
```

UI 主展示建议使用柔性学习节奏，而不是惩罚式断签。

#### 阶段完成率

```text
stage_completion_rate = completed_stage_count / (completed + skipped + abandoned)
```

跳过不展示为失败，文案用「跳过」「稍后继续」。

#### 任务完成率

```text
task_completion_rate = completed_tasks / (completed + abandoned + expired_unfinished)
```

数据少于 3 个任务时不展示百分比。

#### 累计专注时长

```text
total_focus_seconds = Σ valid StageExecutionResult.actualFocusSeconds
```

异常超过 3 小时的单阶段需标记 `needs_review`。

#### 恢复次数

暂停或中断后重新 resumed/completed，计为恢复。

展示文案：

```text
你这周有 3 次重新回到任务里。
```

### 10.10 成就体系

成就原则：

- 奖励开始；
- 奖励恢复；
- 奖励小步骤；
- 不惩罚断签；
- 不排行榜；
- 不打断专注。

成就类型：

| 类型 | 示例 |
|---|---|
| 启动类 | 小小启动、第一步开始 |
| 阶段类 | 第一个阶段、完成 10 个阶段 |
| 恢复类 | 回来就好、温和重启 |
| 连续类 | 三天节奏、七天节奏 |
| 专注类 | 60 分钟累积、300 分钟累积 |
| 任务类 | 第一个任务闭环 |
| 自我觉察类 | 主动标记分心 3 次 |

触发流程：

```text
DataCenterService.recordEvent
    ↓
StatsEngine 更新统计
    ↓
ProfileAgent 更新画像
    ↓
AchievementEngine 检查规则
    ↓
如果当前处于专注阶段 → 放入 pending_queue
否则 → 轻量 Toast 展示
```

### 10.11 模块五接口

```swift
struct StatsSummary: Codable {
    let range: StatsRange
    let activeDays: Int
    let strictStreakDays: Int
    let gentleRhythmText: String
    let totalFocusSeconds: Int
    let completedStageCount: Int
    let stageCompletionRate: Double?
    let taskCompletionRate: Double?
    let recoveryCount: Int
}

enum StatsRange: String, Codable {
    case today
    case last7Days
    case last30Days
    case allTime
}
```

```swift
struct HistoryQuery: Codable {
    let dateRange: StatsRange?
    let keyword: String?
    let taskTypes: [EducationTaskType]
    let stageTypes: [StageType]
    let statuses: [String]
}
```

### 10.12 模块五验收标准

1. 所有模块事件都能写入 JSONL；
2. 重复事件不重复写；
3. 无网络时历史、统计、成就可用；
4. 能查询今天、最近 7 天、本月历史；
5. 能计算连续学习天数、阶段完成率、任务完成率、累计专注时长；
6. 能生成用户画像并供其他模块读取；
7. 用户可关闭画像更新；
8. 用户可导出和删除数据；
9. 成就不会打断专注；
10. 所有统计和成就文案无羞辱、无医疗诊断。

---

## 11. 全局设置需求

### 11.1 设置项

| 设置 | 默认 | 说明 |
|---|---|---|
| 系统通知 | 首次询问 | 拒绝后降级悬浮窗提示 |
| 悬浮窗透明度 | 85% | 可调 |
| 悬浮窗位置 | 自动记忆 | 用户拖动后保存 |
| 语音提醒 | 关闭 | 模块三/四共用 |
| 语音回答 | 关闭 | 需要麦克风权限 |
| 语音音色 | 系统默认温和音色 | 可选 2-3 个 |
| 全局快捷键 | 开启 | 可自定义 |
| 成就 Toast | 开启 | 可关闭，只保留个人中心记录 |
| Agent 画像 | 开启 | 可关闭/重置 |
| 数据导出 | 手动 | JSON / Markdown / CSV |
| 数据删除 | 手动二次确认 | 单任务/单日/全部 |

### 11.2 默认快捷键

| 快捷键 | 功能 | 所属模块 |
|---|---|---|
| `⌘ + Shift + P` | 暂停/恢复当前阶段 | 模块二 |
| `⌘ + Shift + S` | 跳过当前弹窗/反馈/结算页 | 模块三/四 |
| `⌘ + Shift + M` | 呼出语音输入 | 模块三/四 |
| `⌘ + Shift + D` | 标记分心 | 模块三 |
| `⌘ + Shift + H` | 呼出帮助/干预 | 模块三/四 |

冲突处理：

- 检测系统快捷键冲突；
- 冲突时提示用户更换；
- 用户坚持使用时记录风险；
- 当前无活跃任务时快捷键静默失效。

---

## 12. Agent 设计总规范

### 12.1 Agent 不是一个大黑盒

产品内 Agent 采用分工明确的轻量服务：

| Agent | 所属模块 | 职责 |
|---|---|---|
| TaskBreakdownAgent | 模块一 | 拆解学习任务 |
| FeedbackAgent | 模块三 | 生成反馈选项、理解反馈 |
| PlanOptimizationAgent | 模块三 | 动态调整后续阶段 |
| EmotionSupportAgent | 模块四 | 生成鼓励、安抚、复盘文案 |
| ProfileAgent | 模块五 | 更新用户画像和长期观察 |

### 12.2 AgentContextProvider

所有 Agent 获取用户历史时统一走：

```swift
protocol AgentContextProviderProtocol {
    func getContext(for taskId: String?, stageId: String?) async throws -> AgentContext
}

struct AgentContext: Codable {
    let userProfileSnapshot: UserProfileSnapshot
    let recentStatsSummary: StatsSummary?
    let recentSimilarTaskNotes: [String]
    let privacyMode: PrivacyMode
}
```

不得让模块一、三、四直接扫描历史文件。

### 12.3 LLM 调用隐私

默认规则：

- 可把当前任务标题、阶段标题、用户当前反馈传给 LLM；
- 不上传完整历史事件；
- 只上传模块五生成的脱敏摘要；
- 用户可在设置中关闭远程 LLM 个性化；
- 无网络时使用规则模板降级。

### 12.4 Agent 输出安全规则

所有 Agent 输出必须经过基础过滤：

- 不出现羞辱词；
- 不出现医学诊断；
- 不与其他用户比较；
- 不制造 deadline 恐慌；
- 不生成过长文案；
- 不用「你必须」「你应该」「你又」。

---

## 13. 异常与边界情况

### 13.1 输入非教育任务

模块一提示：

```text
这个功能主要帮你拆解学习任务。你现在想先处理哪一个课程、作业、考试或阅读任务？
```

### 13.2 用户只启动就退出

模块四安抚：

```text
你已经尝试开始了，这也算一个小动作。进度我先帮你保存。
```

模块五记录：

- `taskCreated`；
- `taskGracefullyPaused`；
- 不计入失败。

### 13.3 阶段计时异常过长

模块二标记：

```text
metadata.needs_review = true
```

模块五不直接计入统计，等待用户确认或按上限截断。

### 13.4 App 崩溃

启动时：

```text
读取 runtime/active_stage.json
    ↓
若存在 running stage
    ↓
按时间戳重算
    ↓
若超时，标记 appInterrupted 或 timeoutPrompted
    ↓
恢复到执行页或展示温和提示
```

### 13.5 文件损坏

模块五处理：

```text
读取 JSONL 失败
    ↓
跳过损坏行
    ↓
尝试 backups
    ↓
生成修复日志
    ↓
提示用户：部分历史可能无法恢复
```

### 13.6 用户删除数据

支持：

| 操作 | 行为 |
|---|---|
| 删除单条历史 | 删除相关事件并重算 summaries |
| 删除某任务 | 删除 task_id 相关事件和 task 文件 |
| 清空画像 | 删除 profile 文件，保留 events |
| 清空全部数据 | 删除 `.agent_data/` 下全部用户数据 |

---

## 14. 测试与验收总表

### 14.1 功能验收

| 模块 | 核心验收 |
|---|---|
| 模块一 | 能输入教育任务，生成 ADHD 友好阶段计划 |
| 模块二 | 能准确计时、悬浮提醒、输出执行结果 |
| 模块三 | 能采集反馈、理解意图、动态优化计划 |
| 模块四 | 能完成结算、中断安抚、轻量复盘、归档 |
| 模块五 | 能本地存储、查询历史、统计、画像、成就 |

### 14.2 跨模块验收

| 测试 | 通过标准 |
|---|---|
| 模块一 → 二 | `TaskPlan` 确认后模块二可立即执行第一阶段 |
| 模块二 → 三 | 阶段完成后模块三收到完整 `StageExecutionResult` |
| 模块三 → 二 | `StageUpdate` 应用后，模块二阶段列表和计时同步刷新 |
| 模块三 → 四 | 严重中断时模块四能展示安抚页 |
| 模块四 → 五 | 任务闭环后历史页能看到记录 |
| 模块五 → 一 | 模块一能读取画像生成更适合的第一阶段 |
| 模块五 → 三 | 模块三能根据历史困难模式生成更适合的反馈选项 |
| 模块五 → 四 | 模块四能根据鼓励偏好生成合适文案 |

### 14.3 ADHD 友好验收

1. 首屏不出现复杂仪表盘；
2. 默认一屏一个重点；
3. 核心操作按钮足够大；
4. 反馈选项不超过 4 个；
5. 成就弹窗不打断专注；
6. 不出现羞辱、惩罚、失败导向文案；
7. 中断后默认强调保存和恢复；
8. 历史页默认按天聚合，不显示密集日志。

### 14.4 性能验收

| 项目 | 标准 |
|---|---|
| 悬浮窗响应 | 操作后 200ms 内反馈 |
| 计时误差 | 常见前后台/锁屏/重启 ≤ 2 秒 |
| 阶段结束反馈弹窗 | ≤ 500ms 展示，依赖预生成 |
| TTS 启动 | ≤ 1 秒 |
| ASR 识别完成 | 用户说完后 ≤ 2 秒 |
| 任务归档 | ≤ 2 秒，不阻塞 UI |
| 长期运行 | 24 小时无明显内存泄漏 |

### 14.5 隐私验收

1. 无网络时核心流程可用；
2. 未授权不上传历史数据；
3. 用户可导出 JSON / Markdown / CSV；
4. 用户可删除单任务和全部数据；
5. 关闭 Agent 画像后不再更新 profile；
6. 远程 LLM 不接收完整事件日志。

---

## 15. Coding Agent 实现建议

### 15.1 推荐开发顺序

```text
Step 1：建立共享数据模型与 TaskRepository / AppEventBus
Step 2：实现模块五 LocalEventStore，保证事件可写入 JSONL
Step 3：实现模块一 TaskInputView + TaskBreakdownAgent stub
Step 4：实现模块二 ExecutionService + FloatingTimerWindow
Step 5：实现模块三 Feedback Sheet + StageUpdate 应用
Step 6：实现模块四 TaskClosureView + Graceful Pause
Step 7：实现模块五 PersonalCenter + History + Stats
Step 8：补全 ProfileAgent 和 AchievementEngine
Step 9：统一设置、隐私、导出、删除
```

### 15.2 MVP 可先 stub 的能力

| 能力 | MVP 替代方案 |
|---|---|
| LLM 任务拆解 | 固定规则模板 + 简单任务类型识别 |
| 反馈选项生成 | 按 StageType 预设选项 |
| 动态优化 | 规则：太难→拆小；时间不够→+5 分钟 |
| 鼓励文案 | 按任务类型模板生成 |
| 用户画像 | 最近 14 天滑动统计 |
| 自然语言历史查询 | 关键词 + 日期规则 |

### 15.3 首版必须做的能力

不能省略：

- 统一数据模型；
- 本地 JSONL 事件写入；
- 第一阶段低门槛；
- 悬浮窗倒计时；
- 暂停不计入专注时间；
- 阶段反馈；
- 任务结算 / 中断安抚；
- 个人中心 3 个核心指标；
- 数据删除入口。

---

## 16. 附录：完整 Demo 流程

### 16.1 用户输入

```text
我下周要做小组展示，但还没开始准备。
```

### 16.2 模块一输出

```text
任务：准备小组展示
类型：presentation
预计总时长：约 68 分钟

1. 找到展示要求（3 分钟）
2. 新建 PPT 文件（5 分钟）
3. 写下展示主题（5 分钟）
4. 列出 3 个要讲的点（8 分钟）
5. 阅读第一篇资料摘要（10 分钟）
6. 写第一页 PPT 的一句话（10 分钟）
7. 整理报告大纲（12 分钟）
8. 简单排练开头（15 分钟）
```

### 16.3 模块二执行

悬浮窗显示：

```text
03:00
[我遇到困难] [我完成了这一步]
```

阶段完成后输出：

```json
{
  "stage_id": "stage_001",
  "task_id": "task_001",
  "planned_seconds": 180,
  "actual_focus_seconds": 145,
  "pause_count": 0,
  "end_reason": "completedEarly"
}
```

### 16.4 模块三反馈

弹窗：

```text
这一步感觉怎么样？

[找到了 📌] [没找到 🔍] [走神了 😵] [要休息 🍵]
```

如果用户选择「没找到」，模块三将下一阶段插入：

```text
先打开课程平台，找到老师发的展示说明。
```

### 16.5 模块四闭环

任务完成后：

```text
展示大纲搭起来了 🎉

你从“还没开始”推进到了可以继续制作 PPT 的状态。
中间资料那一步卡了一下，但你把它拆小后继续了。
```

### 16.6 模块五记录

个人中心：

```text
你这周已经回到学习里 4 天了。

本周专注：1 小时 54 分钟
完成阶段：12 个
当前节奏：连续 3 天

我注意到：你在 8-12 分钟的整理阶段更容易完成。
```

成就：

```text
🌱 小小启动
你已经开始了，这一步很重要。
```

---

## 17. 文档总结

本产品的核心不是让用户变得「更自律」，而是通过 Agent、界面和本地数据系统，把学习变成一系列更容易开始、更容易回来、更容易被看见的小动作。

五个模块的最终关系是：

```text
模块一：把任务变小
模块二：陪用户执行
模块三：根据反馈调整
模块四：把结果变成正向闭环
模块五：把每次努力沉淀为长期画像和成就
```

最终用户应感受到：

```text
我不用一次完成全部。
我知道现在该做哪一步。
我中断了也可以回来。
我的努力被记录了。
这个 Agent 越来越懂我的学习节奏。
我的数据只属于我自己。
```
