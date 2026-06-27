import AppKit
import Carbon
import FocusFlowCore
import SwiftUI
import UserNotifications

@MainActor
final class FloatingTimerWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var onFrameChanged: ((NSRect) -> Void)?

    func show(
        stageTitle: String,
        remainingSeconds: Int,
        opacity: Double,
        savedOrigin: CGPoint?,
        onFrameChanged: @escaping (NSRect) -> Void,
        onDifficulty: @escaping () -> Void,
        onExtend: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) {
        self.onFrameChanged = onFrameChanged
        let view = FloatingTimerPanel(
            stageTitle: stageTitle,
            remainingSeconds: remainingSeconds,
            opacity: opacity,
            onDifficulty: onDifficulty,
            onExtend: onExtend,
            onComplete: onComplete
        )
        if window == nil {
            let hosting = NSHostingController(rootView: view)
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 280, height: 150),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.contentViewController = hosting
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isMovableByWindowBackground = true
            panel.delegate = self
            if let savedOrigin {
                panel.setFrameOrigin(savedOrigin)
            } else {
                panel.center()
            }
            panel.makeKeyAndOrderFront(nil)
            window = panel
        } else if let hosting = window?.contentViewController as? NSHostingController<FloatingTimerPanel> {
            hosting.rootView = view
            window?.orderFrontRegardless()
        }
    }

    func hide() {
        window?.orderOut(nil)
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        onFrameChanged?(window.frame)
    }
}

struct FloatingTimerPanel: View {
    let stageTitle: String
    let remainingSeconds: Int
    let opacity: Double
    let onDifficulty: () -> Void
    let onExtend: () -> Void
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text(stageTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(1)
            Text(String(format: "%02d:%02d", max(0, remainingSeconds) / 60, max(0, remainingSeconds) % 60))
                .font(.system(.title, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(AppColor.actionPrimary)
            AdaptiveButtonRow(spacing: 8) {
                Button("I'm stuck", action: onDifficulty)
                    .buttonStyle(SecondaryButtonStyle())
                Button("+5", action: onExtend)
                    .buttonStyle(SecondaryButtonStyle())
                Button("Done", action: onComplete)
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(14)
        .frame(width: 280, height: 150)
        .background(AppColor.surfaceCard.opacity(min(1, max(0.35, opacity))), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stageTitle). \(max(0, remainingSeconds) / 60) minutes \(max(0, remainingSeconds) % 60) seconds remaining.")
    }
}

struct LocalNotificationService {
    private var canUseNotificationCenter: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    func requestAuthorization() async -> Bool {
        guard canUseNotificationCenter else {
            return false
        }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            break
        @unknown default:
            break
        }
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    func scheduleStageReminder(identifier: String, title: String, body: String, secondsFromNow: TimeInterval) async -> Bool {
        guard await requestAuthorization() else {
            return false
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, secondsFromNow), repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch {
            return false
        }
    }

    func cancelPendingStageReminders() {
        guard canUseNotificationCenter else {
            return
        }
        Task {
            let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
            let identifiers = requests.map(\.identifier).filter { $0.hasPrefix("focusflow.") }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }
}

@MainActor
final class HotKeyManager {
    nonisolated(unsafe) private static weak var current: HotKeyManager?

    enum Action {
        case pauseResume
        case skip
        case voiceInput
        case markDistraction
        case help
    }

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef?] = []
    private var handlerRef: EventHandlerRef?
    private(set) var failedRegistrationCount = 0

    @discardableResult
    func register(
        shortcuts: FocusFlowShortcutSettings,
        pauseResume: @escaping () -> Void,
        skip: @escaping () -> Void,
        voiceInput: @escaping () -> Void,
        markDistraction: @escaping () -> Void,
        help: @escaping () -> Void
    ) -> Int {
        unregisterAll()
        failedRegistrationCount = 0
        handlers = [
            1: pauseResume,
            2: skip,
            3: voiceInput,
            4: markDistraction,
            5: help
        ]
        HotKeyManager.current = self
        installEventHandlerIfNeeded()
        var registeredKeys = Set<String>()
        register(key: shortcuts.pauseResume, id: 1, registeredKeys: &registeredKeys)
        register(key: shortcuts.skip, id: 2, registeredKeys: &registeredKeys)
        register(key: shortcuts.voiceInput, id: 3, registeredKeys: &registeredKeys)
        register(key: shortcuts.markDistraction, id: 4, registeredKeys: &registeredKeys)
        register(key: shortcuts.help, id: 5, registeredKeys: &registeredKeys)
        return failedRegistrationCount
    }

    func unregisterAll() {
        for ref in refs {
            if let ref {
                UnregisterEventHotKey(ref)
            }
        }
        refs = []
        handlers = [:]
    }

    private func register(key: String, id: UInt32, registeredKeys: inout Set<String>) {
        guard registeredKeys.insert(key).inserted else {
            failedRegistrationCount += 1
            return
        }
        guard let keyCode = Self.keyCode(for: key) else {
            failedRegistrationCount += 1
            return
        }
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x46464C57), id: id)
        let modifiers = UInt32(cmdKey | shiftKey)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status == noErr {
            refs.append(hotKeyRef)
        } else {
            failedRegistrationCount += 1
        }
    }

    private static func keyCode(for key: String) -> UInt32? {
        switch key.uppercased() {
        case "A": UInt32(kVK_ANSI_A)
        case "B": UInt32(kVK_ANSI_B)
        case "C": UInt32(kVK_ANSI_C)
        case "D": UInt32(kVK_ANSI_D)
        case "E": UInt32(kVK_ANSI_E)
        case "F": UInt32(kVK_ANSI_F)
        case "G": UInt32(kVK_ANSI_G)
        case "H": UInt32(kVK_ANSI_H)
        case "I": UInt32(kVK_ANSI_I)
        case "J": UInt32(kVK_ANSI_J)
        case "K": UInt32(kVK_ANSI_K)
        case "L": UInt32(kVK_ANSI_L)
        case "M": UInt32(kVK_ANSI_M)
        case "N": UInt32(kVK_ANSI_N)
        case "O": UInt32(kVK_ANSI_O)
        case "P": UInt32(kVK_ANSI_P)
        case "Q": UInt32(kVK_ANSI_Q)
        case "R": UInt32(kVK_ANSI_R)
        case "S": UInt32(kVK_ANSI_S)
        case "T": UInt32(kVK_ANSI_T)
        case "U": UInt32(kVK_ANSI_U)
        case "V": UInt32(kVK_ANSI_V)
        case "W": UInt32(kVK_ANSI_W)
        case "X": UInt32(kVK_ANSI_X)
        case "Y": UInt32(kVK_ANSI_Y)
        case "Z": UInt32(kVK_ANSI_Z)
        default: nil
        }
    }

    func handle(id: UInt32) {
        handlers[id]?()
    }

    private func installEventHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }
            DispatchQueue.main.async {
                Task { @MainActor in
                    HotKeyManager.current?.handle(id: hotKeyID.id)
                }
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, nil, &handlerRef)
    }
}
