# FocusFlow

FocusFlow is a local-first macOS educational agent for students who benefit from ADHD-friendly task support. The product language is English, while the original PRD is Chinese.

The current codebase is a native Swift foundation with:

- SwiftUI macOS app shell
- AppKit floating timer adapter
- UserNotifications adapter
- Carbon hotkey adapter with global handler routing
- AVSpeechSynthesizer adapter for optional encouragement playback
- Speech framework adapter for optional voice input
- Five-module service layer matching the PRD
- Shared Codable domain model with snake_case JSON
- Local `.agent_data` storage under Application Support
- JSONL event log, task repository, runtime recovery store
- Actor-local event cache for responsive long-running local histories
- Persistent settings under `.agent_data/settings/privacy.json`
- DeepSeek key storage through macOS Keychain
- Settings readiness dashboard for local storage, DeepSeek, notifications, floating timer, shortcuts, and voice capability
- Rule-based local agents for task breakdown, feedback, plan optimization, emotion support, profile/statistics, and achievements
- DeepSeek-compatible LLM client using `deepseek-v4-flash` for remote task planning, feedback options, stuck-help prompts, closure copy, and profile observations

## Product Documents

- Original Chinese PRD: [`docs/prd/FocusFlow_ADHD_Educational_Agent_五模块统一产品需求文档.md`](docs/prd/FocusFlow_ADHD_Educational_Agent_%E4%BA%94%E6%A8%A1%E5%9D%97%E7%BB%9F%E4%B8%80%E4%BA%A7%E5%93%81%E9%9C%80%E6%B1%82%E6%96%87%E6%A1%A3.md)
- Implementation matrix: [`docs/PRD_IMPLEMENTATION_MATRIX.md`](docs/PRD_IMPLEMENTATION_MATRIX.md)
- AI audit and continuation prompt: [`docs/AI_PROGRESS_AUDIT_AND_CONTINUATION_PROMPT.md`](docs/AI_PROGRESS_AUDIT_AND_CONTINUATION_PROMPT.md)
- Project frontend skill: [`.codex/skills/adhd-swiftui-frontend/SKILL.md`](.codex/skills/adhd-swiftui-frontend/SKILL.md)

## Requirements

- macOS 14 or newer recommended
- Xcode with command line tools installed
- Swift Package Manager, provided by Xcode
- GitHub CLI only if you want to publish or inspect GitHub state from the terminal
- Optional: DeepSeek API key for remote agent behavior

Check the active Swift toolchain:

```bash
xcode-select -p
swift --version
```

If needed, select Xcode explicitly:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Quick Start

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift run FocusFlow
```

FocusFlow works without a remote model by using local rule-based fallbacks. To test remote agent behavior for task planning, feedback, stuck help, closure copy, and profile observations, pass a DeepSeek key only through the environment or the in-app Keychain setting:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
DEEPSEEK_API_KEY=your_local_key_here \
swift run FocusFlow
```

The app never commits API keys to the repository.

You can also paste a DeepSeek key in Settings and save it to Keychain. Environment variables take precedence over the saved Keychain value.

## Local Data

By default, app data is stored under:

```text
~/Library/Application Support/com.focusflow.education-agent/.agent_data
```

For repeatable local tests or demos, launch with an isolated data root:

```bash
swift run FocusFlow --focusflow-data-root /tmp/focusflow-demo-data
```

API keys are stored in Keychain or provided through environment variables, not in local JSON files. Ordinary local learning data is kept local-first and user-exportable.

## Test

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

## Smoke Check

```bash
Scripts/smoke_check.sh
```

The smoke check runs tests, packages the app, verifies code signing, validates `Info.plist`, and scans workspace files for accidentally committed DeepSeek keys.

## DeepSeek Connectivity Check

```bash
DEEPSEEK_API_KEY=your_local_key_here Scripts/check_deepseek.sh
```

The script calls DeepSeek Chat Completions with `deepseek-v4-flash`, JSON response mode, and thinking disabled. It also reads the saved FocusFlow Keychain key when `DEEPSEEK_API_KEY` is not set. The key is passed through temporary files with restricted permissions and removed on exit.

## UI Smoke Check

```bash
Scripts/ui_smoke_check.sh
FOCUSFLOW_UI_STRICT_CLICK=1 Scripts/ui_smoke_check.sh
FOCUSFLOW_UI_STRICT_CLICK=1 Scripts/ui_smoke_execution_controls.sh
FOCUSFLOW_UI_STRICT_CLICK=1 Scripts/ui_smoke_closure_history.sh
FOCUSFLOW_UI_STRICT_CLICK=1 Scripts/ui_smoke_settings.sh
```

The UI smoke check packages and launches the app with an isolated data root, then attempts the primary task flow. It first tries named Accessibility buttons; if SwiftUI controls are not exposed to System Events, it falls back to CGEvent coordinate clicks and verifies that feedback was written to the local event store. Strict mode makes click failures fail the script.

## PRD Coverage

The implementation-to-PRD mapping lives in `docs/PRD_IMPLEMENTATION_MATRIX.md`. It tracks the five modules, shared interfaces, agent boundaries, settings, privacy, exception handling, and acceptance coverage.

## Package A Local `.app`

```bash
Scripts/package_app.sh
open dist/FocusFlow.app
```

The package script creates `dist/FocusFlow.app`, copies the release executable into a macOS app bundle, includes microphone/speech/notification usage descriptions, strips extended attributes, and applies ad-hoc signing for local verification.

## Build A Release DMG

```bash
Scripts/release_app.sh
open dist/release
```

The release script packages the app, verifies the signature, creates a compressed DMG with an Applications symlink, verifies the DMG, and writes a SHA-256 checksum next to it. Without Apple certificates it produces a local ad-hoc signed DMG for prototype distribution.

For Developer ID distribution:

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Company (TEAMID)" \
Scripts/release_app.sh
```

For notarization, add either `NOTARYTOOL_PROFILE` or `APPLE_ID`, `APPLE_TEAM_ID`, and `APPLE_APP_SPECIFIC_PASSWORD`, then set `FOCUSFLOW_NOTARIZE=1`.

## Reproduce The Current Release Gate

From a clean checkout:

```bash
git clone https://github.com/hiteacherIamhumble/FocusFlow.git
cd FocusFlow
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
Scripts/smoke_check.sh
```

For UI coverage, grant Accessibility and Input Monitoring permissions to the terminal or Codex app that launches the scripts, then run:

```bash
FOCUSFLOW_UI_STRICT_CLICK=1 Scripts/ui_smoke_check.sh
FOCUSFLOW_UI_STRICT_CLICK=1 Scripts/ui_smoke_execution_controls.sh
FOCUSFLOW_UI_STRICT_CLICK=1 Scripts/ui_smoke_closure_history.sh
FOCUSFLOW_UI_STRICT_CLICK=1 Scripts/ui_smoke_settings.sh
```

## Architecture

```text
FocusFlowApp
 ├── SwiftUI screens
 ├── Native adapters
 │   ├── FloatingTimerWindowController
 │   ├── LocalNotificationService
 │   ├── HotKeyManager
 │   ├── SpeechSynthesisService
 │   └── SpeechRecognitionService
 └── FocusFlowCore
     ├── Domain models
     ├── Service protocols
     ├── Module services
     ├── Local data layer
     └── Rule-based agents
```

## PRD Module Mapping

- Module 1: `TaskPlanningService`, `TaskBreakdownAgent`
- Module 2: `ExecutionService`, `LocalRuntimeStore`
- Module 3: `FeedbackOptimizationService`, `FeedbackAgent`, `PlanOptimizationAgent`
- Module 4: `TaskClosureService`, `EmotionSupportAgent`
- Module 5: `LocalDataCenterService`, `ProfileAgent`, local JSONL/statistics/profile/achievement logic

## Current Implementation Scope

Implemented:

- Natural-language learning task input
- Education task classification
- ADHD-friendly stage generation
- DeepSeek v4 flash task breakdown with local rule fallback
- First step constrained to 2-5 minutes
- Plan preview and refinement actions
- Stage execution state machine
- Timestamp-based focus time with pause exclusion
- AppKit floating timer adapter wired to active execution
- Local notification scheduling for active stages
- Stuck-help card with DeepSeek generation and fallback
- Executable stuck-help actions: hint, example, split-smaller plan update, and 3-minute break countdown
- Severe-interruption panel with save progress, split smaller, rest 10 minutes, switch task, and close actions
- Feedback options with DeepSeek generation and fallback
- Simple plan updates for too-hard, distracted, and need-more-time feedback
- Completion and graceful-pause summaries with DeepSeek emotion copy and fallback
- Personal center with three core metrics and ProfileAgent observations
- Persistent privacy/focus settings
- System readiness dashboard in Settings with required/optional capability status
- Profile learning keeps both the latest profile and a local `profile_snapshots.jsonl` journal
- DeepSeek API key save/clear/test from Settings via Keychain
- One-command DeepSeek connectivity check for `deepseek-v4-flash`
- Global hotkeys for pause/resume, skip, distraction mark, and help
- Voice encouragement playback and optional voice input
- Voice transcript capture on stage feedback
- Markdown, JSON, and CSV export for local event history
- History search/filter controls for date range and learning task type
- Natural-language history query parsing
- History task detail cards with stage summaries
- Single-task history deletion with local audit event
- Achievement unlock storage plus pending queue display
- Expanded achievement rules for ten stages, sixty minutes, first task loop, and distraction awareness
- Local `.app` bundle packaging script with Info.plist, entitlements, and ad-hoc signing
- Release DMG script with optional Developer ID signing, hardened runtime, notarization, stapling, verification, and checksum output
- Generated macOS app icon and status/achievement overlays
- Adaptive ADHD-friendly SwiftUI design tokens, responsive controls, and VoiceOver-readable progress/status surfaces
- One-command smoke check for tests, packaging, signing, plist validation, and secret scanning
- Local data delete entry
- Corrupt JSON quarantine and safe fallback for settings, runtime, tasks, profile, and achievements
- Five-module end-to-end service test covering task input, planning, execution, feedback, closure, personal data, and profile learning
- Longitudinal local-data regression test covering 120 days of history, statistics, export, profile learning, and achievements
- UI accessibility identifiers for the primary task, plan, execution, closure, personal center, and settings flows
- UI smoke script for packaged app launch plus optional strict Accessibility click automation

Production hardening still to build:

- Apple updater and public distribution channel
- Broader visual regression and beta-session QA across varied macOS display/accessibility settings
- A fully permissioned macOS automation runner for broader visual regression coverage beyond the primary click smoke
- More production-grade voice UX calibration and microphone permission onboarding
