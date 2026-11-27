import AppKit
import Combine
import RhythmCore
import UniformTypeIdentifiers

enum AppPage: String, CaseIterable {
    case focus = "Compact", session = "Focus", plan = "Plan", summary = "History", analytics = "Analytics", categories = "Categories", settings = "Settings", idleReview = "Idle detection"
    var title: String { L10n.label(rawValue) }
    var symbol: String {
        switch self {
        case .focus, .session: return "circle.dotted.circle"
        case .plan: return "checklist"
        case .summary: return "chart.bar.xaxis"
        case .analytics: return "square.grid.3x3.fill"
        case .categories: return "tag"
        case .settings: return "gearshape"
        case .idleReview: return "moon.zzz"
        }
    }
}

enum CompactEditor: Hashable {
    case details, timer
}

@MainActor
final class AppStore: ObservableObject {
    @Published var ledger: Ledger
    @Published var now = Date()
    @Published var page: AppPage = .focus {
        didSet {
            now = Date()
            synchronizeTaskDay(at: now)
            if [.summary, .analytics].contains(page), selectedDay > Calendar.current.startOfDay(for: Date()) {
                selectedDay = Calendar.current.startOfDay(for: Date())
            }
            if page != .focus { compactEditor = nil }
            if [.session, .plan, .summary].contains(page) { lastMainPage = page }
            onPageChanged?(page)
        }
    }
    @Published var lastMainPage: AppPage = .session
    @Published var compactEditor: CompactEditor? {
        didSet {
            if compactEditor == nil { compactEditorHeight = 0 }
            if page == .focus { onPanelLayoutChanged?() }
        }
    }
    @Published private(set) var compactEditorHeight: CGFloat = 0
    @Published var title = ""
    @Published var selectedCategoryID: UUID
    @Published var mode: TrackingMode
    @Published var minutes: Int
    @Published var selectedTaskID: UUID?
    @Published var selectedDay = Calendar.current.startOfDay(for: Date()) {
        didSet { materializeDailyTasks(on: selectedDay) }
    }
    @Published var lastCompleted: WorkSession?
    @Published var storageError: String?
    var showSettings: Bool {
        get { page == .settings }
        set { if newValue { page = .settings } }
    }
    var showCategories: Bool {
        get { page == .categories }
        set { if newValue { page = .categories } }
    }
    @Published var isPinned = false
    var isPanelVisible = false

    var onTimerFinished: ((WorkSession) -> Void)?
    var onStatusChanged: (() -> Void)?
    var onPinChanged: (() -> Void)?
    var onOpenRequested: (() -> Void)?
    var onCloseRequested: (() -> Void)?
    var onPageChanged: ((AppPage) -> Void)?
    var onPanelLayoutChanged: (() -> Void)?
    var onNotificationPermissionNeeded: (() -> Void)?
    var onIdleReviewReady: ((IdleReview) -> Void)?
    @Published private(set) var isGlowPreviewing = false
    let file: LedgerFile
    private(set) var ticker: Timer?
    private let writer: LedgerWriter
    private var lastScheduledLedger: Ledger?
    private var saveRevision = 0
    private var saveFailed = false
    private var lastCheckpoint = Date()
    private var writesBlocked = false
    private let idleTimeProvider: () -> TimeInterval
    private var glowPreviewTask: Task<Void, Never>?
    private var taskDay = Calendar.current.startOfDay(for: Date())

    var active: WorkSession? { ledger.activeSession }
    var categories: [TimeCategory] { ledger.visibleCategories }
    var selectedCategory: TimeCategory? { ledger.category(selectedCategoryID) }
    var currentCategoryID: UUID { active?.categoryID ?? selectedCategoryID }
    var currentCategory: TimeCategory? { ledger.category(currentCategoryID) }
    var todayTasks: [PlanTask] { ledger.tasks(on: now) }
    var dayTasks: [PlanTask] { ledger.tasks(on: selectedDay) }
    var totalToday: TimeInterval { ledger.total(on: now, at: now) }
    var totalSelectedDay: TimeInterval { ledger.total(on: selectedDay, at: now) }
    var isToday: Bool { Calendar.current.isDateInToday(selectedDay) }
    var pendingIdle: IdleReview? { ledger.idleReview }
    var canStart: Bool { active == nil && pendingIdle == nil && !writesBlocked && selectedCategory != nil }
    var pomodoroPhase: PomodoroPhase { active?.mode == .pomodoro ? (active?.pomodoroPhase ?? .focus) : (ledger.pomodoroProgress?.nextPhase ?? .focus) }
    var idleSeconds: TimeInterval {
        mode == .pomodoro ? ledger.preferences.pomodoro.seconds(for: pomodoroPhase) : (mode == .countdown ? Double(min(480, max(1, minutes))) * 60 : 0)
    }
    var pomodoroRound: Int {
        let rounds = min(8, max(2, ledger.preferences.pomodoro.roundsBeforeLongBreak))
        let completed = ledger.pomodoroProgress?.completedFocusCount ?? 0
        if pomodoroPhase.isBreak { return (max(1, completed) - 1) % rounds + 1 }
        return completed % rounds + 1
    }
    var phaseCaption: String {
        if let pendingIdle { return L10n.text("Idle time ") + TimeText.duration(pendingIdle.duration(at: now)) }
        if let active, active.isPaused { return L10n.text("Paused") }
        if (active?.mode ?? mode) == .pomodoro {
            return (pomodoroPhase.isBreak ? L10n.text("Break") : L10n.text("Focus")) + " \(pomodoroRound)/\(ledger.preferences.pomodoro.roundsBeforeLongBreak)"
        }
        if active?.isRunning == true { return L10n.text("Focusing") }
        return mode == .countdown ? L10n.text("Timer") : L10n.text("Stopwatch")
    }

    init(dataURL: URL? = nil, idleTimeProvider: @escaping () -> TimeInterval = SystemActivity.idleSeconds) {
        self.idleTimeProvider = idleTimeProvider
        let defaultDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Rhythm", isDirectory: true)
        file = LedgerFile(url: dataURL ?? defaultDirectory.appendingPathComponent("ledger.json"))
        writer = LedgerWriter(file: file)
        var initial = Ledger()
        var errorMessage: String?
        var blocked = false
        do {
            if let envelope = try file.load() {
                initial = envelope.ledger
                initial.recoverAfterRelaunch(lastCheckpoint: envelope.savedAt, at: Date())
            } else if let backup = try file.loadBackup() {
                initial = backup.ledger
                initial.recoverAfterRelaunch(lastCheckpoint: backup.savedAt, at: Date())
                errorMessage = L10n.text("Data restored from backup because the main file was missing.")
            }
        } catch {
            // Preserve the original before attempting to restore a recovery copy.
            let preservedURL = file.url.deletingLastPathComponent().appendingPathComponent("ledger-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            do {
                try FileManager.default.copyItem(at: file.url, to: preservedURL)
                if let backup = try file.loadBackup() {
                    initial = backup.ledger
                    initial.recoverAfterRelaunch(lastCheckpoint: backup.savedAt, at: Date())
                    errorMessage = L10n.text("Data restored from backup. The original file was kept.")
                } else {
                    blocked = true
                    errorMessage = L10n.text("Could not read your data. The original file was kept. Open the data folder in Settings.")
                }
            } catch {
                blocked = true
                errorMessage = L10n.text("Could not access your data file. Check the data folder in Settings.")
            }
        }
        if initial.visibleCategories.isEmpty { initial.categories.append(TimeCategory(name: L10n.text("Personal"), color: .mint)) }
        let createdDailyTasks = initial.materializeDailyTasks(on: Date())
        ledger = initial
        selectedCategoryID = initial.preferences.lastCategoryID.flatMap { id in initial.visibleCategories.first { $0.id == id }?.id } ?? initial.visibleCategories[0].id
        mode = initial.preferences.lastMode
        minutes = max(1, min(480, initial.preferences.defaultMinutes))
        storageError = errorMessage
        writesBlocked = blocked
        if let active = initial.activeSession {
            title = active.title
            selectedCategoryID = active.categoryID
            selectedTaskID = active.taskID
            mode = active.mode
        }
        configureTicker()
        if createdDailyTasks { save() }
    }

    deinit {
        ticker?.invalidate()
        glowPreviewTask?.cancel()
    }

    func start() {
        guard canStart else { return }
        now = Date()
        synchronizeTaskDay(at: now)
        if let id = selectedTaskID,
           let previous = ledger.tasks.first(where: { $0.id == id }), let scheduleID = previous.dailyScheduleID {
            selectedTaskID = ledger.tasks(on: now).first(where: { $0.dailyScheduleID == scheduleID && $0.completedAt == nil })?.id
        }
        let cleanedTitle = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
        if let id = selectedTaskID,
           !ledger.tasks.contains(where: { $0.id == id && $0.completedAt == nil && $0.categoryID == selectedCategoryID && $0.title == cleanedTitle }) {
            selectedTaskID = nil
        }
        minutes = max(1, min(480, minutes))
        ledger.preferences.defaultMinutes = minutes
        ledger.preferences.lastMode = mode
        ledger.preferences.lastCategoryID = selectedCategoryID
        let phase: PomodoroPhase? = mode == .pomodoro ? pomodoroPhase : nil
        ledger.activeSession = WorkSession(title: cleanedTitle, categoryID: selectedCategoryID, taskID: phase?.isBreak == true ? nil : selectedTaskID, mode: mode, targetSeconds: idleSeconds, startedAt: now, pomodoroPhase: phase)
        lastCompleted = nil
        save()
        configureTicker()
        if (mode.isTimed || ledger.preferences.idleCheckEnabled) && ledger.preferences.notificationsEnabled { onNotificationPermissionNeeded?() }
        onStatusChanged?()
    }

    func quickToggle() {
        if pendingIdle != nil { presentIdleReview(); return }
        if active != nil { pauseOrResume() }
        else { start() }
    }

    func selectCategoryQuickly(_ id: UUID) {
        guard categories.contains(where: { $0.id == id }) else { return }
        if pendingIdle != nil { presentIdleReview(); return }
        guard id != currentCategoryID else {
            selectedCategoryID = id
            ledger.preferences.lastCategoryID = id
            save()
            return
        }
        now = Date()
        _ = finishExpired(at: now)
        let wasTask = active?.taskID != nil || selectedTaskID != nil
        ledger.changeActiveCategory(to: id, at: now)
        if wasTask, selectedCategoryID != id { title = "" }
        selectedTaskID = nil
        selectedCategoryID = id
        ledger.preferences.lastCategoryID = id
        save()
        configureTicker()
        onStatusChanged?()
    }

    func presentIdleReview() {
        guard pendingIdle != nil else { return }
        if ledger.idleReview?.returnedAt == nil {
            ledger.endIdleObservation(at: Date())
            save()
            configureTicker()
        }
        page = .idleReview
        onOpenRequested?()
    }

    func resolveIdle(includeTime: Bool, resume: Bool) {
        now = Date()
        let completed = ledger.resolveIdle(includeTime: includeTime, resume: resume, at: now)
        if let completed {
            lastCompleted = completed
            onTimerFinished?(completed)
        }
        save()
        configureTicker()
        page = .focus
        onStatusChanged?()
    }

    func skipPomodoroBreak() {
        guard pomodoroPhase.isBreak else { return }
        if active?.isBreak == true { finish() }
        else {
            var progress = ledger.pomodoroProgress ?? PomodoroProgress()
            progress.nextPhase = .focus
            ledger.pomodoroProgress = progress
            save()
        }
    }

    func resetPomodoro() {
        guard active == nil else { return }
        ledger.pomodoroProgress = PomodoroProgress()
        save()
    }

    func updateSessionDetails(title newTitle: String, categoryID: UUID) {
        let clean = String(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
        if let selectedTaskID, let task = ledger.tasks.first(where: { $0.id == selectedTaskID }), task.title != clean || task.categoryID != categoryID {
            self.selectedTaskID = nil
        }
        if let active, active.title != clean || active.categoryID != categoryID {
            ledger.activeSession?.title = clean
            ledger.activeSession?.categoryID = categoryID
            ledger.activeSession?.taskID = nil
            selectedTaskID = nil
        }
        title = clean
        selectedCategoryID = categoryID
        ledger.preferences.lastCategoryID = categoryID
        save()
        onStatusChanged?()
    }

    func saveTimerPreferences() {
        minutes = max(1, min(480, minutes))
        ledger.preferences.defaultMinutes = minutes
        ledger.preferences.lastMode = mode
        save()
    }

    func updateCompactEditorHeight(_ height: CGFloat) {
        guard compactEditor != nil, height.isFinite, height > 0 else { return }
        let measured = min(500, ceil(height))
        guard abs(measured - compactEditorHeight) > 0.5 else { return }
        compactEditorHeight = measured
        onPanelLayoutChanged?()
    }

    func showGlowPreview() {
        guard ledger.preferences.breakEdgeGlowEnabled else { return }
        glowPreviewTask?.cancel()
        isGlowPreviewing = true
        onStatusChanged?()
        glowPreviewTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            self?.stopGlowPreview()
        }
    }

    func stopGlowPreview() {
        glowPreviewTask?.cancel()
        glowPreviewTask = nil
        guard isGlowPreviewing else { return }
        isGlowPreviewing = false
        onStatusChanged?()
    }

    func pauseOrResume() {
        if pendingIdle != nil { presentIdleReview(); return }
        guard active != nil else { return }
        now = Date()
        if finishExpired(at: now) { return }
        if active!.isRunning { ledger.activeSession?.pause(at: now) }
        else { ledger.activeSession?.resume(at: now) }
        save()
        configureTicker()
        onStatusChanged?()
    }

    func finish() {
        if pendingIdle != nil { presentIdleReview(); return }
        guard active != nil else { return }
        now = Date()
        if finishExpired(at: now) { return }
        lastCompleted = ledger.finishActiveSession(at: now)
        save()
        configureTicker()
        onStatusChanged?()
    }

    func extendTimer() {
        guard active?.mode == .countdown else { return }
        ledger.activeSession?.targetSeconds += 5 * 60
        save()
        onStatusChanged?()
    }

    func pauseForInactivity() {
        now = Date()
        ledger.endIdleObservation(at: now)
        guard !finishExpired(at: now, allowAutomaticBreak: false), active?.isRunning == true else { save(); configureTicker(); return }
        ledger.activeSession?.pause(at: now)
        save()
        configureTicker()
        onStatusChanged?()
    }

    func refresh() {
        now = Date()
        synchronizeTaskDay(at: now)
        checkActivity(at: now)
        _ = finishExpired(at: now)
        onStatusChanged?()
    }

    func prepareToQuit() {
        stopGlowPreview()
        pauseForInactivity()
        save()
        writer.flush()
    }

    private func configureTicker() {
        ticker?.invalidate()
        ticker = nil
        guard active?.isRunning == true || (pendingIdle != nil && pendingIdle?.returnedAt == nil) else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    func tick() {
        let date = Date()
        if !Calendar.current.isDate(taskDay, inSameDayAs: date) { synchronizeTaskDay(at: date) }
        // Keep timing/idle detection live even with the menu closed. Static pages
        // need only a minute refresh for their footer, not a rebuilt heatmap each second.
        if isPanelVisible && (![.analytics, .settings, .categories].contains(page) || date.timeIntervalSince(now) >= 60) {
            now = date
        }
        checkActivity(at: date)
        guard !finishExpired(at: date) else { return }
        if date.timeIntervalSince(lastCheckpoint) >= 15 { save() }
        onStatusChanged?()
    }

    private func checkActivity(at date: Date) {
        guard (pendingIdle != nil && pendingIdle?.returnedAt == nil) || (ledger.preferences.idleCheckEnabled && active?.isRunning == true && active?.isBreak == false) else { return }
        let seconds = idleTimeProvider()
        // Calling a mutating method directly on @Published emits a change even
        // when that method returns without changing the value.
        var updated = ledger
        if updated.detectReturn(at: date, idleFor: seconds) {
            ledger = updated
            save()
            configureTicker()
            if let pendingIdle { onIdleReviewReady?(pendingIdle) }
        } else if updated.detectIdle(at: date, idleFor: seconds) {
            ledger = updated
            save()
            configureTicker()
        }
    }

    @discardableResult
    private func finishExpired(at date: Date, allowAutomaticBreak: Bool = true) -> Bool {
        guard let deadline = active?.deadline, date >= deadline else { return false }
        guard let completed = ledger.completeExpiredTimer(at: date) else { return false }
        lastCompleted = completed
        var notification = completed
        if allowAutomaticBreak, ledger.startAutomaticBreak(after: completed), let rest = ledger.completeExpiredTimer(at: date) {
            lastCompleted = rest
            notification = rest
        }
        save()
        configureTicker()
        onStatusChanged?()
        onTimerFinished?(notification)
        return true
    }

    func save() {
        guard !writesBlocked else { return }
        let date = Date()
        let needsCheckpoint = (active?.isRunning == true || pendingIdle?.returnedAt == nil && pendingIdle != nil)
            && date.timeIntervalSince(lastCheckpoint) >= 15
        guard lastScheduledLedger != ledger || needsCheckpoint else { return }
        lastScheduledLedger = ledger
        lastCheckpoint = date
        saveRevision += 1
        let revision = saveRevision
        writer.save(ledger, at: date) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.saveRevision == revision else { return }
                switch result {
                case .success:
                    if self.saveFailed { self.storageError = nil }
                    self.saveFailed = false
                case .failure(let error):
                    self.lastScheduledLedger = nil
                    self.saveFailed = true
                    self.storageError = L10n.text("Could not save changes: \(error.localizedDescription)")
                }
            }
        }
    }

    func useTask(_ task: PlanTask, startImmediately: Bool = false) {
        guard active == nil else { return }
        title = task.title
        selectedCategoryID = task.categoryID
        selectedTaskID = task.id
        if mode == .pomodoro { skipPomodoroBreak() }
        if task.plannedMinutes > 0 { minutes = min(480, task.plannedMinutes) }
        else { mode = .stopwatch }
        page = .focus
        if startImmediately { start() }
    }

    func clearTaskAssociation() { selectedTaskID = nil }

    func addTask(title: String, categoryID: UUID, minutes: Int, day: Date, isDaily: Bool = false) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        ledger.addPlanTask(PlanTask(title: String(clean.prefix(240)), categoryID: categoryID, plannedMinutes: max(0, min(480, minutes)), day: Calendar.current.startOfDay(for: day)), repeatsDaily: isDaily)
        materializeDailyTasks(on: Date())
        save()
    }

    func updateTask(_ task: PlanTask, isDaily: Bool? = nil) {
        ledger.updatePlanTask(task, repeatsDaily: isDaily ?? (task.dailyScheduleID != nil))
        materializeDailyTasks(on: Date())
        clearMissingTaskAssociation()
        save()
    }

    func toggleTask(_ id: UUID) {
        guard let index = ledger.tasks.firstIndex(where: { $0.id == id }) else { return }
        ledger.tasks[index].completedAt = ledger.tasks[index].completedAt == nil ? Date() : nil
        save()
    }

    func moveTaskToToday(_ id: UUID) {
        guard let index = ledger.tasks.firstIndex(where: { $0.id == id }), ledger.tasks[index].dailyScheduleID == nil else { return }
        ledger.tasks[index].day = Calendar.current.startOfDay(for: Date())
        save()
    }

    func deleteTask(_ id: UUID) {
        ledger.deletePlanTask(id)
        clearMissingTaskAssociation()
        save()
    }

    func isActiveTask(_ task: PlanTask) -> Bool {
        guard let id = active?.taskID else { return false }
        guard let scheduleID = task.dailyScheduleID else { return id == task.id }
        return Calendar.current.isDate(task.day, inSameDayAs: now)
            && ledger.tasks.first(where: { $0.id == id })?.dailyScheduleID == scheduleID
    }

    private func clearMissingTaskAssociation() {
        if let selectedTaskID, !ledger.tasks.contains(where: { $0.id == selectedTaskID }) { self.selectedTaskID = nil }
    }

    private func materializeDailyTasks(on day: Date) {
        var updated = ledger
        guard updated.materializeDailyTasks(on: day) else { return }
        ledger = updated
        save()
    }

    func synchronizeTaskDay(at date: Date) {
        let calendar = Calendar.current
        if !calendar.isDate(taskDay, inSameDayAs: date) {
            let followsToday = calendar.isDate(selectedDay, inSameDayAs: taskDay)
            taskDay = calendar.startOfDay(for: date)
            if followsToday { selectedDay = taskDay }
        }
        materializeDailyTasks(on: date)
        materializeDailyTasks(on: selectedDay)
    }

    func addCategory(name: String, color: CategoryColor, goal: Int) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let category = TimeCategory(name: String(clean.prefix(40)), color: color, dailyGoalMinutes: max(0, min(1440, goal)))
        ledger.categories.append(category)
        selectedCategoryID = category.id
        save()
    }

    func updateCategory(_ category: TimeCategory) {
        guard let index = ledger.categories.firstIndex(where: { $0.id == category.id }) else { return }
        ledger.categories[index] = category
        save()
    }

    func archiveCategory(_ id: UUID) {
        guard categories.count > 1, active?.categoryID != id,
              let index = ledger.categories.firstIndex(where: { $0.id == id }) else { return }
        ledger.categories[index].isArchived = true
        if selectedCategoryID == id { selectedCategoryID = categories[0].id }
        save()
    }

    func restoreCategory(_ id: UUID) {
        guard let index = ledger.categories.firstIndex(where: { $0.id == id }) else { return }
        ledger.categories[index].isArchived = false
        save()
    }

    func deleteSession(_ id: UUID) {
        ledger.sessions.removeAll { $0.id == id }
        save()
        onStatusChanged?()
    }

    func changeDay(_ offset: Int, allowsFuture: Bool = false) {
        if let date = Calendar.current.date(byAdding: .day, value: offset, to: selectedDay), allowsFuture || date <= Calendar.current.startOfDay(for: Date()) {
            selectedDay = date
        }
    }

    func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = L10n.text("time_ history.csv")
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try CSVExport.sessions(ledger.sessions, categories: ledger.categories).write(to: url, atomically: true, encoding: .utf8) }
        catch { storageError = L10n.text("Could not export: \(error.localizedDescription)") }
    }

    func exportBackup() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = L10n.text("time_ backup.json")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(LedgerEnvelope(savedAt: Date(), ledger: ledger)).write(to: url, options: .atomic)
        } catch { storageError = L10n.text("Could not create backup: \(error.localizedDescription)") }
    }
}
