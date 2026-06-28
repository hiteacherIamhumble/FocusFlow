import FocusFlowCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: FocusFlowAppModel
    @State private var confirmingDeleteAllData = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Settings")
                        .font(AppFont.pageTitle)
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Keep the assistant quiet, local, and adjustable.")
                        .font(.title3)
                        .foregroundStyle(AppColor.textSecondary)
                }
                .padding(.bottom, 4)

                SettingsSection("System readiness", initiallyExpanded: true) {
                    HStack(spacing: 10) {
                        Image(systemName: model.readinessReport.isPrototypeReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(model.readinessReport.isPrototypeReady ? AppColor.success : AppColor.warning)
                        Text(model.readinessReport.summaryText)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(AppColor.textPrimary)
                        Spacer()
                        Button("Refresh") {
                            Task { await model.refreshReadiness() }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                        ForEach(model.readinessReport.items) { item in
                            readinessRow(item)
                        }
                    }
                    AdaptiveButtonRow {
                        Button("Open notification settings") {
                            model.openNotificationSettings()
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("open_notification_settings_button")
                        Button("Test floating timer") {
                            model.testFloatingTimer()
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("test_floating_timer_button")
                        Button("Test voice") {
                            model.testVoicePrompt()
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("test_voice_button")
                        Button("Test shortcuts") {
                            model.testShortcuts()
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("test_shortcuts_button")
                    }
                }

                SettingsSection("Focus support", initiallyExpanded: true) {
                    Toggle("System notifications", isOn: $model.settings.notificationsEnabled)
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            Text("Floating timer opacity")
                            Slider(value: $model.settings.floatingTimerOpacity, in: 0.35...1.0)
                                .frame(maxWidth: 260)
                            Text("\(Int(model.settings.floatingTimerOpacity * 100))%")
                                .foregroundStyle(AppColor.textSecondary)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Floating timer opacity")
                            Slider(value: $model.settings.floatingTimerOpacity, in: 0.35...1.0)
                            Text("\(Int(model.settings.floatingTimerOpacity * 100))%")
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }
                    AdaptiveButtonRow {
                        Text("Floating timer position")
                        Button("Reset position") {
                            model.resetFloatingTimerPosition()
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    Toggle("Voice encouragement", isOn: $model.settings.voicePromptsEnabled)
                    Picker("Voice", selection: Binding(
                        get: { model.settings.voiceIdentifier ?? "" },
                        set: { model.settings.voiceIdentifier = $0.isEmpty ? nil : $0 }
                    )) {
                        ForEach(model.availableVoiceOptions) { voice in
                            Text(voice.displayName).tag(voice.id)
                        }
                    }
                    .frame(maxWidth: 360)
                    Toggle("Voice input", isOn: $model.settings.voiceInputEnabled)
                    Toggle("Achievement toast", isOn: $model.settings.achievementsToastEnabled)
                    Button("Save focus settings") {
                        model.saveSettings()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                SettingsSection("Privacy & data") {
                    Toggle("Local profile learning", isOn: $model.settings.profileLearningEnabled)
                    Label("Local encryption is off. Learning data stays as plain JSON on this Mac.", systemImage: "lock.open")
                        .font(.callout)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle("Remote agent personalization", isOn: $model.settings.remoteAgentEnabled)
                    Text("FocusFlow stores learning events locally under Application Support. It does not record screenshots, keystrokes, page text, or medical diagnoses.")
                        .font(.callout)
                        .foregroundStyle(AppColor.textSecondary)
                    Button("Save privacy settings") {
                        model.saveSettings()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Button("Clear agent profile memory") {
                        model.clearProfileMemory()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    if confirmingDeleteAllData {
                        AdaptiveButtonRow {
                            Label("This deletes local events, tasks, profile, and settings.", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(AppColor.warning)
                            Button("Confirm delete") {
                                model.deleteAllData()
                                confirmingDeleteAllData = false
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .accessibilityIdentifier("confirm_delete_all_data_button")
                            Button("Cancel") {
                                confirmingDeleteAllData = false
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Button("Delete all local data") {
                            confirmingDeleteAllData = true
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("delete_all_data_button")
                    }
                    AdaptiveButtonRow {
                        Picker("Export format", selection: $model.exportFormat) {
                            Text("Markdown").tag("Markdown")
                            Text("JSON").tag("JSON")
                            Text("CSV").tag("CSV")
                        }
                        .frame(width: 180)
                        Button("Export local data") {
                            model.exportLocalData()
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }

                SettingsSection("Remote agent") {
                    Text(model.remoteAgentStatus)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Set DEEPSEEK_API_KEY in the launch environment to enable DeepSeek v4 flash. The key is never committed to the project.")
                        .font(.callout)
                        .foregroundStyle(AppColor.textSecondary)
                    SecureField("Paste DeepSeek API key for Keychain storage", text: $model.deepSeekAPIKeyDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 460)
                    AdaptiveButtonRow {
                        Button("Save key to Keychain") {
                            model.saveDeepSeekKey()
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        Button("Clear saved key") {
                            model.clearDeepSeekKey()
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    Button("Test DeepSeek connection") {
                        model.testDeepSeekConnection()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                SettingsSection("Shortcuts") {
                    Toggle("Global shortcuts", isOn: $model.settings.globalShortcutsEnabled)
                    Text(model.hotKeyStatus)
                        .font(.callout)
                        .foregroundStyle(AppColor.textSecondary)
                    if !model.settings.shortcutKeys.duplicateKeys.isEmpty {
                        Label("Each shortcut needs a different letter.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(AppColor.warning)
                    }
                    shortcutPicker("Pause or resume current stage", key: $model.settings.shortcutKeys.pauseResume)
                    shortcutPicker("Skip feedback or sheet", key: $model.settings.shortcutKeys.skip)
                    shortcutPicker("Voice input", key: $model.settings.shortcutKeys.voiceInput)
                    shortcutPicker("Mark distraction", key: $model.settings.shortcutKeys.markDistraction)
                    shortcutPicker("Open help", key: $model.settings.shortcutKeys.help)
                    Button("Save shortcut settings") {
                        model.saveSettings()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(42)
        }
    }

    private func shortcutPicker(_ label: String, key: Binding<String>) -> some View {
        let duplicates = Set(model.settings.shortcutKeys.duplicateKeys)
        return HStack {
            Text(label)
            Spacer()
            if duplicates.contains(key.wrappedValue) {
                Label("Conflict", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.warning)
            } else {
                Label("Ready", systemImage: "checkmark.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.success)
            }
            Text("⌘ ⇧")
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .foregroundStyle(AppColor.textSecondary)
            Picker("", selection: key) {
                ForEach(FocusFlowShortcutSettings.supportedKeys, id: \.self) { key in
                    Text(key).tag(key)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 78)
        }
    }

    private func readinessRow(_ item: AppReadinessItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: readinessIcon(for: item.state))
                .font(.callout.weight(.semibold))
                .foregroundStyle(readinessColor(for: item.state))
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    if item.isRequired {
                        Text("Required")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppColor.actionPrimary)
                    }
                }
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.bgBase.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title). \(item.state.rawValue). \(item.detail)")
    }

    private func readinessIcon(for state: AppReadinessState) -> String {
        switch state {
        case .ready:
            return "checkmark.circle.fill"
        case .needsAttention:
            return "exclamationmark.circle.fill"
        case .off:
            return "minus.circle.fill"
        }
    }

    private func readinessColor(for state: AppReadinessState) -> Color {
        switch state {
        case .ready:
            return AppColor.success
        case .needsAttention:
            return AppColor.warning
        case .off:
            return AppColor.textSecondary
        }
    }
}

struct SettingsSection<Content: View>: View {
    @State private var expanded: Bool
    private let title: String
    private let content: Content

    init(_ title: String, initiallyExpanded: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self._expanded = State(initialValue: initiallyExpanded)
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    expanded.toggle()
                }
            } label: {
                HStack {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings_section_\(title.lowercased().replacingOccurrences(of: " ", with: "_"))")

            if expanded {
                VStack(alignment: .leading, spacing: 14) {
                    content
                        .font(.body)
                        .foregroundStyle(AppColor.textPrimary)
                }
                .padding(.top, 16)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.surfaceCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColor.borderSubtle.opacity(0.6)))
    }
}
