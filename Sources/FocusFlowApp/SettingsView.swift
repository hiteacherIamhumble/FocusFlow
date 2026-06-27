import FocusFlowCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: FocusFlowAppModel
    @State private var confirmingDeleteAllData = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Settings")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(FFColors.ink)
                    Text("Keep the assistant quiet, local, and adjustable.")
                        .font(.title3)
                        .foregroundStyle(FFColors.softGray)
                }

                settingsGroup("System readiness") {
                    HStack(spacing: 10) {
                        Image(systemName: model.readinessReport.isPrototypeReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(model.readinessReport.isPrototypeReady ? FFColors.mint : FFColors.peach)
                        Text(model.readinessReport.summaryText)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(FFColors.ink)
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
                    HStack {
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

                settingsGroup("Focus support") {
                    Toggle("System notifications", isOn: $model.settings.notificationsEnabled)
                    HStack {
                        Text("Floating timer opacity")
                        Slider(value: $model.settings.floatingTimerOpacity, in: 0.35...1.0)
                            .frame(maxWidth: 260)
                        Text("\(Int(model.settings.floatingTimerOpacity * 100))%")
                            .foregroundStyle(FFColors.softGray)
                    }
                    HStack {
                        Text("Floating timer position")
                        Spacer()
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

                settingsGroup("Privacy") {
                    Toggle("Local profile learning", isOn: $model.settings.profileLearningEnabled)
                    Toggle("Local encryption", isOn: $model.settings.localEncryptionEnabled)
                    Text("When enabled, new task, runtime, history, profile, achievement, and closure files are encrypted with a Keychain-backed key.")
                        .font(.callout)
                        .foregroundStyle(FFColors.softGray)
                    Toggle("Remote agent personalization", isOn: $model.settings.remoteAgentEnabled)
                    Text("FocusFlow stores learning events locally under Application Support. It does not record screenshots, keystrokes, page text, or medical diagnoses.")
                        .font(.callout)
                        .foregroundStyle(FFColors.softGray)
                    Button("Save privacy settings") {
                        model.saveSettings()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Button("Clear agent profile memory") {
                        model.clearProfileMemory()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    if confirmingDeleteAllData {
                        HStack {
                            Label("This deletes local events, tasks, profile, and settings.", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(FFColors.peach)
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
                    HStack {
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

                settingsGroup("Remote agent") {
                    Text(model.remoteAgentStatus)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(FFColors.ink)
                    Text("Set DEEPSEEK_API_KEY in the launch environment to enable DeepSeek v4 flash. The key is never committed to the project.")
                        .font(.callout)
                        .foregroundStyle(FFColors.softGray)
                    SecureField("Paste DeepSeek API key for Keychain storage", text: $model.deepSeekAPIKeyDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 460)
                    HStack {
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

                settingsGroup("Shortcuts") {
                    Toggle("Global shortcuts", isOn: $model.settings.globalShortcutsEnabled)
                    Text(model.hotKeyStatus)
                        .font(.callout)
                        .foregroundStyle(FFColors.softGray)
                    if !model.settings.shortcutKeys.duplicateKeys.isEmpty {
                        Label("Each shortcut needs a different letter.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(FFColors.peach)
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

    @ViewBuilder
    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
                .foregroundStyle(FFColors.ink)
            content()
                .font(.body)
                .foregroundStyle(FFColors.ink)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
    }

    private func shortcutPicker(_ label: String, key: Binding<String>) -> some View {
        let duplicates = Set(model.settings.shortcutKeys.duplicateKeys)
        return HStack {
            Text(label)
            Spacer()
            if duplicates.contains(key.wrappedValue) {
                Label("Conflict", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FFColors.peach)
            } else {
                Label("Ready", systemImage: "checkmark.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FFColors.mint)
            }
            Text("⌘ ⇧")
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .foregroundStyle(FFColors.softGray)
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
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(readinessColor(for: item.state))
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(FFColors.ink)
                    if item.isRequired {
                        Text("Required")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(FFColors.blue)
                    }
                }
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(FFColors.softGray)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FFColors.canvas.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
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
            return FFColors.mint
        case .needsAttention:
            return FFColors.peach
        case .off:
            return FFColors.softGray
        }
    }
}
