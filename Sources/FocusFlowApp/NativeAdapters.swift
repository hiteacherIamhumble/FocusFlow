import AppKit
import Carbon
import FocusFlowCore
import SwiftUI
import UserNotifications

@MainActor
final class FloatingTimerWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var onFrameChanged: ((NSRect) -> Void)?
    private var expandedFrame: NSRect?
    private var userClosedWindow = false
    private var compactModeApplied: Bool?

    private let defaultSize = NSSize(width: 540, height: 680)
    private let minSize = NSSize(width: 420, height: 480)
    private let minimizedSize = NSSize(width: 190, height: 112)

    func show(
        model: FocusFlowAppModel,
        savedOrigin: CGPoint?,
        onFrameChanged: @escaping (NSRect) -> Void
    ) {
        self.onFrameChanged = onFrameChanged

        if window == nil {
            let hosting = NSHostingController(
                rootView: FloatingExecutionPanel()
                    .environmentObject(model)
            )
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: defaultSize),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.title = "FocusFlow"
            panel.titleVisibility = .visible
            panel.titlebarAppearsTransparent = false
            panel.isMovableByWindowBackground = true
            panel.contentViewController = hosting
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = true
            panel.backgroundColor = NSColor.windowBackgroundColor
            panel.hasShadow = true
            panel.minSize = minSize
            panel.isReleasedWhenClosed = false
            panel.delegate = self
            if let savedOrigin {
                panel.setFrame(NSRect(origin: savedOrigin, size: defaultSize), display: false)
            } else {
                panel.center()
            }
            window = panel
        }

        guard !userClosedWindow else { return }
        guard window?.isMiniaturized != true else { return }
        setMinimized(model.floatingTimerMinimized, animated: false)
        guard window?.isVisible != true else { return }
        window?.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }

    func bringToFront() {
        userClosedWindow = false
        if window?.isMiniaturized == true {
            window?.deminiaturize(nil)
        }
        window?.orderFrontRegardless()
    }

    func setMinimized(_ minimized: Bool, animated: Bool = true) {
        guard let window else { return }
        guard compactModeApplied != minimized else { return }
        compactModeApplied = minimized
        if minimized {
            if expandedFrame == nil, window.frame.size != minimizedSize {
                expandedFrame = window.frame
            }
            window.styleMask.remove(.resizable)
            window.minSize = minimizedSize
            window.maxSize = minimizedSize
            let frame = framePreservingTopLeft(from: window.frame, size: minimizedSize)
            window.setFrame(frame, display: true, animate: animated)
        } else {
            window.styleMask.insert(.resizable)
            window.minSize = minSize
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            let frame = expandedFrame ?? framePreservingTopLeft(from: window.frame, size: defaultSize)
            expandedFrame = nil
            window.setFrame(frame, display: true, animate: animated)
        }
    }

    private func framePreservingTopLeft(from frame: NSRect, size: NSSize) -> NSRect {
        NSRect(
            x: frame.minX,
            y: frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        onFrameChanged?(window.frame)
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        onFrameChanged?(window.frame)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        userClosedWindow = true
        sender.orderOut(nil)
        return false
    }
}

struct FloatingExecutionPanel: View {
    @EnvironmentObject private var model: FocusFlowAppModel

    var body: some View {
        Group {
            if model.floatingTimerMinimized {
                FloatingMiniTimer()
            } else {
                ExecutionWorkspaceView()
                    .overlay(alignment: .topTrailing) {
                        Button {
                            model.setFloatingTimerMinimized(true)
                        } label: {
                            Image(systemName: "minus.rectangle")
                                .font(.title3.weight(.semibold))
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppColor.textSecondary)
                        .background(AppColor.surfaceCard.opacity(0.92), in: Circle())
                        .overlay(Circle().stroke(AppColor.borderSubtle.opacity(0.7)))
                        .padding(12)
                        .accessibilityLabel("Minimize floating timer")
                        .accessibilityHint("Shows only the countdown. Dragging the minimized timer moves it.")
                        .accessibilityIdentifier("floating_timer_minimize_button")
                    }
            }
        }
        .background(
            AppColor.bgBase.opacity(min(1, max(0.35, model.settings.floatingTimerOpacity)))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColor.borderSubtle.opacity(0.5)))
    }
}

struct FloatingMiniTimer: View {
    @EnvironmentObject private var model: FocusFlowAppModel

    private var displaySeconds: Int {
        if let remaining = model.breakRemainingSeconds, remaining > 0 {
            return remaining
        }
        return model.remainingSeconds ?? currentStage?.estimatedSeconds ?? 0
    }

    private var currentStage: StagePlan? {
        model.currentTask?.stages.sorted(by: { $0.order < $1.order }).first {
            $0.status == .running || $0.status == .paused || $0.status == .overtime
        } ?? model.currentTask?.stages.sorted(by: { $0.order < $1.order }).first {
            $0.status == .idle || $0.status == .adjusted
        }
    }

    private var displayText: String {
        let display = max(0, displaySeconds)
        return String(format: "%02d:%02d", display / 60, display % 60)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "timer")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppColor.actionPrimary)
            Text(displayText)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(displaySeconds <= 120 ? AppColor.warning : AppColor.actionPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .overlay(MiniTimerInteractionLayer {
            model.setFloatingTimerMinimized(false)
        })
        .accessibilityLabel("Floating timer minimized. \(displaySeconds / 60) minutes \(displaySeconds % 60) seconds remaining.")
        .accessibilityHint("Click to expand the floating timer. Drag to move it.")
        .accessibilityIdentifier("floating_timer_minimized_button")
    }
}

struct MiniTimerInteractionLayer: NSViewRepresentable {
    let onTap: () -> Void

    func makeNSView(context: Context) -> MiniTimerInteractionView {
        MiniTimerInteractionView(onTap: onTap)
    }

    func updateNSView(_ nsView: MiniTimerInteractionView, context: Context) {
        nsView.onTap = onTap
    }
}

final class MiniTimerInteractionView: NSView {
    var onTap: () -> Void
    private var mouseDownLocation: NSPoint?
    private var initialWindowOrigin: NSPoint?
    private let dragThreshold: CGFloat = 4

    init(onTap: @escaping () -> Void) {
        self.onTap = onTap
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        self.onTap = {}
        super.init(coder: coder)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = NSEvent.mouseLocation
        initialWindowOrigin = window?.frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownLocation, let initialWindowOrigin, let window else { return }
        let current = NSEvent.mouseLocation
        let delta = NSPoint(x: current.x - mouseDownLocation.x, y: current.y - mouseDownLocation.y)
        window.setFrameOrigin(NSPoint(x: initialWindowOrigin.x + delta.x, y: initialWindowOrigin.y + delta.y))
    }

    override func mouseUp(with event: NSEvent) {
        guard let mouseDownLocation else {
            onTap()
            return
        }
        let current = NSEvent.mouseLocation
        let distance = hypot(current.x - mouseDownLocation.x, current.y - mouseDownLocation.y)
        self.mouseDownLocation = nil
        initialWindowOrigin = nil
        if distance <= dragThreshold {
            onTap()
        }
    }
}

final class FocusFlowNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = FocusFlowNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if #available(macOS 11.0, *) {
            completionHandler([.banner, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }
}

struct LocalNotificationService {
    private var canUseNotificationCenter: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private func configureForegroundPresentation() {
        UNUserNotificationCenter.current().delegate = FocusFlowNotificationDelegate.shared
    }

    func currentAuthorizationStatus() async -> Bool? {
        guard canUseNotificationCenter else {
            return nil
        }
        configureForegroundPresentation()
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return nil
        @unknown default:
            return nil
        }
    }

    func requestAuthorization() async -> Bool {
        guard canUseNotificationCenter else {
            return false
        }
        configureForegroundPresentation()
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
        configureForegroundPresentation()
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

    func cancelPendingStageReminders() async {
        await cancelPendingReminders(matchingPrefix: "focusflow.stage.")
    }

    func cancelPendingFocusFlowReminders() async {
        await cancelPendingReminders(matchingPrefix: "focusflow.")
    }

    private func cancelPendingReminders(matchingPrefix prefix: String) async {
        guard canUseNotificationCenter else {
            return
        }
        configureForegroundPresentation()
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let identifiers = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
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
