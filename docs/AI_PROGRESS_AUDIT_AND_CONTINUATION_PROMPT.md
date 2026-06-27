# AI Progress Audit And Continuation Prompt

Copy this prompt into a fresh AI coding session when you want it to audit FocusFlow against the PRD before continuing implementation.

```text
你现在接手 FocusFlow 项目。请先审计当前项目完成进度，再继续实现。

项目背景：
- FocusFlow 是 macOS 原生 SwiftUI/AppKit ADHD-friendly educational agent app。
- 需求源以 docs/prd/FocusFlow_ADHD_Educational_Agent_五模块统一产品需求文档.md 为准。
- 当前进度矩阵在 docs/PRD_IMPLEMENTATION_MATRIX.md。
- 前端样式和 SwiftUI 体验必须使用项目 skill：.codex/skills/adhd-swiftui-frontend/SKILL.md。
- 注意：本地文件加密不再是产品需求。本轮不要把加密作为必须补齐项，不要因为加密缺口阻塞 MVP。DeepSeek API key 仍应通过 Keychain 或环境变量处理，不要写入仓库。

第一阶段：只审计，不改代码。
1. 阅读 PRD、实现矩阵、README、Package.swift、Sources、Tests、Scripts。
2. 对照 PRD 的五个模块列出当前完成、部分完成、缺失、风险项。
3. 特别检查前端体验：信息层级、视觉一致性、ADHD 友好、可访问性、Dynamic Type、Reduce Motion、VoiceOver、颜色语义和不以颜色单独传达意义。
4. 检查测试和脚本覆盖：swift test、smoke check、UI smoke scripts、DeepSeek 检查脚本。
5. 输出一份审计报告，按优先级列出下一步任务。不要泛泛而谈，要引用具体文件路径。

第二阶段：等审计报告完成后，再继续实现。
1. 先从 P0/P1 缺口中选择最小闭环工作，不做无关重构。
2. 前端修改必须遵守 adhd-swiftui-frontend skill，使用语义 token 和可访问性检查。
3. 后端/服务修改必须保持五模块边界清晰，优先沿用现有模型和服务模式。
4. 每完成一组修改后运行相关测试；能运行 swift test 就运行，必要时再运行 smoke scripts。
5. 最终汇报：改了什么、覆盖了哪些 PRD 缺口、验证结果、剩余风险。

请先执行第一阶段并停下来给出审计报告；不要在审计完成前写代码。
```

