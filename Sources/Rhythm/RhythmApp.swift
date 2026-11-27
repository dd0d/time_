import AppKit
import SwiftUI
import Combine
import RhythmCore
import UserNotifications
import Carbon

@main
enum RhythmApplication {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval { 0.16 }
}

final class GlassHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    private let store: AppStore = {
        #if DEBUG
        if let dataFile = Bundle.main.object(forInfoDictionaryKey: "RhythmQADataFile") as? String {
            return AppStore(dataURL: URL(fileURLWithPath: dataFile))
        }
        #endif
        return AppStore()
    }()
    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel!
    private var statusFingerprint = ""
    private var preferenceObservation: AnyCancellable?
    private var outsideClickMonitor: Any?
    private var escapeMonitor: Any?
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private let breakEdgeGlow = BreakEdgeGlow()
    #if DEBUG
    private var auditMonitor: AuditMonitor?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        store.isPinned = Bundle.main.object(forInfoDictionaryKey: "RhythmQAAlwaysVisible") as? Bool == true
        if let path = Bundle.main.object(forInfoDictionaryKey: "RhythmQAMetricsFile") as? String {
            auditMonitor = AuditMonitor(url: URL(fileURLWithPath: path))
        }
        #endif
        configureMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.target = self
            button.action = #selector(togglePanel(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: RootView.compactSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "time_"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = store.isPinned
        panel.isMovable = store.isPinned
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = store.isPinned ? .floating : .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = GlassHostingView(rootView: RootView().environmentObject(store))
        panel.delegate = self

        store.onStatusChanged = { [weak self] in self?.updateStatus() }
        store.onOpenRequested = { [weak self] in self?.showPanel(keepPage: true) }
        store.onCloseRequested = { [weak self] in self?.hidePanel(force: true) }
        store.onPinChanged = { [weak self] in
            guard let self else { return }
            self.panel.level = self.store.isPinned ? .floating : .popUpMenu
            self.panel.isMovable = self.store.isPinned
            self.panel.isMovableByWindowBackground = self.store.isPinned
            if !self.store.isPinned { self.positionPanel() }
        }
        store.onPageChanged = { [weak self] _ in self?.resizePanel() }
        store.onPanelLayoutChanged = { [weak self] in self?.resizePanel() }
        store.onTimerFinished = { [weak self] session in self?.notifyFinished(session) }
        store.onNotificationPermissionNeeded = { [weak self] in self?.requestNotifications() }
        store.onIdleReviewReady = { [weak self] review in self?.notifyIdleReview(review) }
        preferenceObservation = store.$ledger.map(\.preferences).removeDuplicates()
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.applyAppearance(); self?.updateStatus() }
        UNUserNotificationCenter.current().delegate = self

        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(screenLocked), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(calendarChanged), name: .NSCalendarDayChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(calendarChanged), name: .NSSystemTimeZoneDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(systemColorsChanged), name: NSColor.systemColorsDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hidePanel() }
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, let self, self.panel.isKeyWindow else { return event }
            if self.store.page == .focus, self.store.compactEditor != nil { self.store.compactEditor = nil }
            else if self.store.page == .focus { self.hidePanel(force: true) }
            else { self.store.page = .focus }
            return nil
        }
        registerHotKey()
        updateStatus()
        applyAppearance()
        #if DEBUG
        if store.isPinned { showPanel() }
        #endif
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Launching or reopening the app only exposes its menu bar item.
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.prepareToQuit()
        breakEdgeGlow.hide(immediately: true)
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc private func togglePanel(_ sender: Any?) {
        if NSApplication.shared.currentEvent?.type == .rightMouseUp { showContextMenu() }
        else if panel.isVisible && !store.isPinned { hidePanel(force: true) }
        else { showPanel() }
    }

    private func showPanel(keepPage: Bool = false) {
        store.isPanelVisible = true
        if !panel.isVisible && !keepPage { store.page = .focus }
        store.refresh()
        if !store.isPinned || !panel.isVisible { positionPanel() }
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func hidePanel(force: Bool = false) {
        guard force || !store.isPinned else { return }
        store.isPanelVisible = false
        panel.orderOut(nil)
        store.compactEditor = nil
        store.page = .focus
    }

    private func anchoredFrame(size: NSSize) -> NSRect {
        let statusWindow = statusItem.button?.window
        let screen = statusWindow?.screen ?? NSScreen.main!
        let available = screen.visibleFrame
        var centerX = available.maxX - size.width / 2 - 8
        if let button = statusItem.button, let statusWindow {
            let anchor = statusWindow.convertToScreen(button.convert(button.bounds, to: nil))
            let barHeight = max(screen.safeAreaInsets.top, NSStatusBar.system.thickness)
            let menuBarArea = NSRect(x: screen.frame.minX, y: screen.frame.maxY - barHeight - 8, width: screen.frame.width, height: barHeight + 16)
            if anchor.width > 0, anchor.intersects(menuBarArea), anchor.midX > available.minX, anchor.midX < available.maxX {
                centerX = anchor.midX
            }
        }
        let originX = min(max(available.minX + 8, centerX - size.width / 2), available.maxX - size.width - 8)
        let safeTop = min(available.maxY, screen.frame.maxY - screen.safeAreaInsets.top)
        return NSRect(x: originX, y: max(available.minY + 8, safeTop - size.height - 6), width: size.width, height: size.height)
    }

    private func positionPanel() {
        panel.setFrame(anchoredFrame(size: RootView.size(for: store)), display: true)
    }

    private func resizePanel() {
        guard let panel else { return }
        let size = RootView.size(for: store)
        var frame = anchoredFrame(size: size)
        if store.isPinned {
            let available = (panel.screen ?? NSScreen.main!).visibleFrame
            frame.origin.x = min(max(available.minX + 8, panel.frame.minX), available.maxX - size.width - 8)
            frame.origin.y = min(max(available.minY + 8, panel.frame.maxY - size.height), available.maxY - size.height - 8)
        }
        let animate = panel.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(frame, display: true, animate: animate)
    }

    private func updateStatus() {
        let now = Date()
        let preferences = store.ledger.preferences
        breakEdgeGlow.update(visible: preferences.breakEdgeGlowEnabled && (store.isGlowPreviewing || (store.active?.isBreak == true && store.active?.isRunning == true)),
                             color: store.accentNSColor, style: GlowStyle(width: preferences.glowWidth, intensity: preferences.glowIntensity))
        guard let button = statusItem?.button else { return }
        var title = ""
        var symbol = store.ledger.preferences.menuBarIcon.symbol
        let hint: String
        if let review = store.pendingIdle {
            symbol = "exclamationmark.circle"
            hint = "Простой · " + TimeText.duration(review.duration(at: now)) + ". Таймер на паузе; откройте меню, чтобы разобрать время."
        } else if let active = store.active {
            let time = active.mode.isTimed ? active.remaining(at: now) : active.elapsed(at: now)
            if store.ledger.preferences.showMenuBarTime { title = " " + TimeText.clock(time, countdown: active.mode.isTimed) }
            if active.isPaused { symbol = "pause.circle" }
            hint = active.displayTitle + " · " + (store.ledger.category(active.categoryID)?.name ?? "Категория") + " · " + store.phaseCaption
        } else {
            hint = "time_ · сегодня " + TimeText.duration(store.totalToday) + " · ⌃⌥Пробел"
        }
        let fingerprint = title + "|" + symbol + "|" + hint
        guard fingerprint != statusFingerprint else { return }
        statusFingerprint = fingerprint
        button.title = title
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "time_")
        button.image?.isTemplate = true
        button.toolTip = hint
    }

    private func applyAppearance() {
        AppAppearance.apply(store.ledger.preferences.appearance, to: NSApplication.shared)
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Открыть time_", action: #selector(openFromMenu), keyEquivalent: "")
        if let active = store.active {
            menu.addItem(withTitle: active.isRunning ? "Пауза" : "Продолжить", action: #selector(pauseFromMenu), keyEquivalent: "")
            menu.addItem(withTitle: "Завершить и сохранить", action: #selector(finishFromMenu), keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "План на день…", action: #selector(planFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "История…", action: #selector(summaryFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "Настройки…", action: #selector(settingsFromMenu), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Завершить time_", action: #selector(quitFromMenu), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openFromMenu() { store.page = .focus; showPanel() }
    @objc private func pauseFromMenu() { store.pauseOrResume() }
    @objc private func finishFromMenu() { store.finish() }
    @objc private func settingsFromMenu() { store.page = .settings; showPanel(keepPage: true) }
    @objc private func planFromMenu() { store.page = .plan; showPanel(keepPage: true) }
    @objc private func summaryFromMenu() { store.page = .summary; showPanel(keepPage: true) }
    @objc private func quitFromMenu() { NSApplication.shared.terminate(nil) }
    @objc private func closeFromMenu() {
        if NSApplication.shared.keyWindow === panel {
            if store.page == .focus { hidePanel(force: true) } else { store.page = .focus }
        }
        else { NSApplication.shared.keyWindow?.performClose(nil) }
    }
    @objc private func willSleep() { store.pauseForInactivity() }
    @objc private func didWake() { store.refresh() }
    @objc private func screenLocked() { if store.ledger.preferences.pauseOnLock { store.pauseForInactivity() } }
    @objc private func systemColorsChanged() { store.objectWillChange.send() }
    @objc private func screensChanged() { breakEdgeGlow.screensChanged() }
    @objc private func calendarChanged() {
        let followedToday = Calendar.current.isDate(store.selectedDay, inSameDayAs: store.now)
        store.refresh()
        if followedToday { store.selectedDay = Calendar.current.startOfDay(for: store.now) }
    }

    private func configureMainMenu() {
        let main = NSMenu()
        let applicationItem = NSMenuItem()
        let application = NSMenu(title: "time_")
        application.addItem(withTitle: "Настройки…", action: #selector(settingsFromMenu), keyEquivalent: ",").target = self
        application.addItem(.separator())
        application.addItem(withTitle: "Завершить time_", action: #selector(quitFromMenu), keyEquivalent: "q").target = self
        applicationItem.submenu = application
        main.addItem(applicationItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Правка")
        edit.addItem(withTitle: "Отменить", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Повторить", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Вырезать", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Копировать", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Вставить", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Выбрать всё", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Окно")
        window.addItem(withTitle: "Таймер", action: #selector(openFromMenu), keyEquivalent: "1").target = self
        window.addItem(withTitle: "План", action: #selector(planFromMenu), keyEquivalent: "2").target = self
        window.addItem(withTitle: "История", action: #selector(summaryFromMenu), keyEquivalent: "3").target = self
        window.addItem(.separator())
        window.addItem(withTitle: "Закрыть окно", action: #selector(closeFromMenu), keyEquivalent: "w").target = self
        windowItem.submenu = window
        main.addItem(windowItem)
        NSApplication.shared.mainMenu = main
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notifyFinished(_ session: WorkSession) {
        if store.ledger.preferences.soundEnabled { NSSound(named: "Glass")?.play() }
        if store.ledger.preferences.notificationsEnabled {
            let content = UNMutableNotificationContent()
            content.title = session.isBreak ? "Перерыв окончен" : "Время для паузы"
            content.body = session.displayTitle + " · " + TimeText.duration(session.elapsed(at: session.endedAt ?? Date()))
            if session.mode == .pomodoro {
                if session.isBreak {
                    content.title = "Отдых окончен"
                    content.body = "Следующий помодоро готов. Нажмите кружок, когда будете готовы к фокусу."
                } else if let rest = store.active, rest.isBreak {
                    content.title = "Перерыв начался"
                    content.body = rest.displayTitle + " · " + TimeText.duration(rest.targetSeconds) + ". Отсчёт уже запущен."
                } else {
                    content.body += "\nДальше: " + store.pomodoroPhase.title.lowercased() + ". Нажмите кружок, когда будете готовы."
                }
            }
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "rhythm-timer-complete", content: content, trigger: nil))
        }
    }

    private func notifyIdleReview(_ review: IdleReview) {
        guard store.ledger.preferences.notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Разобрать простой"
        content.body = TimeText.duration(review.duration(at: Date())) + " без активности. Таймер на паузе; выберите, учитывать ли это время."
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "rhythm-idle-review", content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let isIdle = response.notification.request.identifier == "rhythm-idle-review"
        Task { @MainActor [weak self] in
            if isIdle, self?.store.pendingIdle != nil { self?.store.presentIdleReview() }
            else { self?.showPanel() }
        }
        completionHandler()
    }

    private func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in delegate.togglePanel(nil) }
            return noErr
        }, 1, &spec, pointer, &hotKeyHandler)
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), EventHotKeyID(signature: 0x52595448, id: 1), GetApplicationEventTarget(), 0, &hotKey)
    }
}
