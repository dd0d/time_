import Foundation

public enum TrackingMode: String, Codable, CaseIterable, Sendable {
    case countdown, stopwatch, pomodoro
    public var isTimed: Bool { self != .stopwatch }
}

public enum PomodoroPhase: String, Codable, Sendable {
    case focus, shortBreak, longBreak
    public var isBreak: Bool { self != .focus }
    public var title: String {
        switch self {
        case .focus: return "Помодоро"
        case .shortBreak: return "Короткий перерыв"
        case .longBreak: return "Длинный перерыв"
        }
    }
}

public struct PomodoroSettings: Codable, Equatable, Sendable {
    public var focusMinutes = 25
    public var shortBreakMinutes = 5
    public var longBreakMinutes = 15
    public var roundsBeforeLongBreak = 4
    public var autoStartBreaks = true
    public init() {}

    private enum CodingKeys: String, CodingKey { case focusMinutes, shortBreakMinutes, longBreakMinutes, roundsBeforeLongBreak, autoStartBreaks }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        focusMinutes = min(120, max(1, try values.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? 25))
        shortBreakMinutes = min(30, max(1, try values.decodeIfPresent(Int.self, forKey: .shortBreakMinutes) ?? 5))
        longBreakMinutes = min(60, max(1, try values.decodeIfPresent(Int.self, forKey: .longBreakMinutes) ?? 15))
        roundsBeforeLongBreak = min(8, max(2, try values.decodeIfPresent(Int.self, forKey: .roundsBeforeLongBreak) ?? 4))
        autoStartBreaks = try values.decodeIfPresent(Bool.self, forKey: .autoStartBreaks) ?? true
    }

    public func seconds(for phase: PomodoroPhase) -> TimeInterval {
        switch phase {
        case .focus: return Double(min(120, max(1, focusMinutes)) * 60)
        case .shortBreak: return Double(min(30, max(1, shortBreakMinutes)) * 60)
        case .longBreak: return Double(min(60, max(1, longBreakMinutes)) * 60)
        }
    }
}

public struct PomodoroProgress: Codable, Equatable, Sendable {
    public var completedFocusCount = 0
    public var nextPhase: PomodoroPhase = .focus
    public init() {}

    public mutating func complete(_ phase: PomodoroPhase, settings: PomodoroSettings) {
        if phase == .focus {
            completedFocusCount += 1
            nextPhase = completedFocusCount % min(8, max(2, settings.roundsBeforeLongBreak)) == 0 ? .longBreak : .shortBreak
        } else { nextPhase = .focus }
    }
}

public enum CategoryColor: String, Codable, CaseIterable, Sendable {
    case mint, blue, lavender, peach, rose, yellow
}

public enum AccentChoice: String, Codable, CaseIterable, Sendable {
    case system, blue, purple, pink, red, orange, yellow, green, graphite, custom
}

public enum MenuBarIcon: String, Codable, CaseIterable, Sendable {
    case rhythm, timer, circle
}

public struct GlassStyle: Equatable, Sendable {
    public static let defaultOpacity = 0.65
    public static let defaultBlur = 1.0
    public let opacity: Double
    public let blur: Double

    public init(opacity: Double = defaultOpacity, blur: Double = defaultBlur) {
        self.opacity = min(1, max(0, opacity.isFinite ? opacity : Self.defaultOpacity))
        self.blur = min(1, max(0, blur.isFinite ? blur : Self.defaultBlur))
    }

    // At the default values this is exactly the original macOS glass material.
    public var materialOpacity: Double { blur * min(1, opacity / Self.defaultOpacity) }
    public var tintOpacity: Double {
        let solidOverlay = max(0, (opacity - Self.defaultOpacity) / (1 - Self.defaultOpacity))
        return opacity * (1 - blur) + solidOverlay * blur
    }
}

public struct GlowStyle: Equatable, Sendable {
    public static let defaultWidth = 86.0
    public static let defaultIntensity = 0.24
    public let width: Double
    public let intensity: Double

    public init(width: Double = defaultWidth, intensity: Double = defaultIntensity) {
        self.width = min(320, max(24, width.isFinite ? width : Self.defaultWidth))
        self.intensity = min(1, max(0, intensity.isFinite ? intensity : Self.defaultIntensity))
    }
}

public struct TimeCategory: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var color: CategoryColor
    public var dailyGoalMinutes: Int
    public var isArchived: Bool

    public init(id: UUID = UUID(), name: String, color: CategoryColor, dailyGoalMinutes: Int = 0, isArchived: Bool = false) {
        self.id = id
        self.name = name
        self.color = color
        self.dailyGoalMinutes = dailyGoalMinutes
        self.isArchived = isArchived
    }
}

public struct PlanTask: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var categoryID: UUID
    public var plannedMinutes: Int
    public var day: Date
    public var completedAt: Date?
    public var createdAt: Date
    public var dailyScheduleID: UUID?

    public init(id: UUID = UUID(), title: String, categoryID: UUID, plannedMinutes: Int, day: Date, completedAt: Date? = nil, createdAt: Date = Date(), dailyScheduleID: UUID? = nil) {
        self.id = id
        self.title = title
        self.categoryID = categoryID
        self.plannedMinutes = plannedMinutes
        self.day = day
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.dailyScheduleID = dailyScheduleID
    }
}

public struct WorkInterval: Codable, Equatable, Sendable {
    public var start: Date
    public var end: Date?

    public init(start: Date, end: Date? = nil) {
        self.start = start
        self.end = end
    }

    public func duration(at now: Date) -> TimeInterval {
        max(0, min(end ?? now, now).timeIntervalSince(start))
    }

    public func overlap(with day: DateInterval, at now: Date) -> TimeInterval {
        max(0, min(end ?? now, min(now, day.end)).timeIntervalSince(max(start, day.start)))
    }
}

public struct WorkSession: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var categoryID: UUID
    public var taskID: UUID?
    public var mode: TrackingMode
    public var pomodoroPhase: PomodoroPhase?
    public var targetSeconds: TimeInterval
    public var startedAt: Date
    public var endedAt: Date?
    public var intervals: [WorkInterval]

    public init(id: UUID = UUID(), title: String, categoryID: UUID, taskID: UUID? = nil, mode: TrackingMode, targetSeconds: TimeInterval = 0, startedAt: Date, pomodoroPhase: PomodoroPhase? = nil) {
        self.id = id
        self.title = title
        self.categoryID = categoryID
        self.taskID = taskID
        self.mode = mode
        self.pomodoroPhase = pomodoroPhase
        self.targetSeconds = targetSeconds
        self.startedAt = startedAt
        self.intervals = [WorkInterval(start: startedAt)]
    }

    public var isRunning: Bool { endedAt == nil && intervals.last?.end == nil }
    public var isPaused: Bool { endedAt == nil && !isRunning }
    public var isBreak: Bool { mode == .pomodoro && pomodoroPhase?.isBreak == true }
    public var displayTitle: String {
        if isBreak { return pomodoroPhase!.title }
        return title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (mode == .pomodoro ? "Помодоро" : "Фокус") : title
    }

    public func elapsed(at now: Date) -> TimeInterval {
        intervals.reduce(0) { $0 + $1.duration(at: now) }
    }

    public func remaining(at now: Date) -> TimeInterval {
        max(0, targetSeconds - elapsed(at: now))
    }

    public var deadline: Date? {
        guard mode.isTimed, isRunning, let current = intervals.last else { return nil }
        let previous = intervals.dropLast().reduce(0.0) { $0 + $1.duration(at: current.start) }
        return current.start.addingTimeInterval(max(0, targetSeconds - previous))
    }

    public mutating func pause(at date: Date) {
        guard isRunning, !intervals.isEmpty else { return }
        intervals[intervals.count - 1].end = max(intervals[intervals.count - 1].start, date)
    }

    public mutating func resume(at date: Date) {
        guard isPaused else { return }
        intervals.append(WorkInterval(start: max(intervals.last?.end ?? date, date)))
    }

    public mutating func finish(at date: Date) {
        guard endedAt == nil else { return }
        pause(at: date)
        endedAt = max(startedAt, date)
    }

    public func duration(on day: Date, calendar: Calendar = .current, at now: Date) -> TimeInterval {
        guard let bounds = calendar.dateInterval(of: .day, for: day) else { return 0 }
        return duration(in: bounds, at: now)
    }

    public func duration(in bounds: DateInterval, at now: Date) -> TimeInterval {
        guard startedAt < bounds.end, (endedAt ?? now) > bounds.start else { return 0 }
        return intervals.reduce(0) { $0 + $1.overlap(with: bounds, at: now) }
    }
}

public struct Preferences: Codable, Equatable, Sendable {
    public var appearance = "system"
    public var accentChoice: AccentChoice = .system
    public var customAccentHex = "6E64D4"
    public var backgroundOpacity = GlassStyle.defaultOpacity
    public var backgroundBlur = GlassStyle.defaultBlur
    public var showMenuBarTime = true
    public var breakEdgeGlowEnabled = true
    public var glowWidth = GlowStyle.defaultWidth
    public var glowIntensity = GlowStyle.defaultIntensity
    public var animateLogo = true
    public var menuBarIcon: MenuBarIcon = .rhythm
    public var pomodoro = PomodoroSettings()
    public var soundEnabled = true
    public var notificationsEnabled = true
    public var pauseOnLock = true
    public var idleCheckEnabled = true
    public var idleMinutes = 5
    public var defaultMinutes = 25
    public var lastMode: TrackingMode = .countdown
    public var lastCategoryID: UUID?
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case appearance, accentChoice, customAccentHex, backgroundOpacity, backgroundBlur, showMenuBarTime, breakEdgeGlowEnabled, glowWidth, glowIntensity, animateLogo, menuBarIcon, pomodoro, soundEnabled, notificationsEnabled
        case pauseOnLock, idleCheckEnabled, idleMinutes, defaultMinutes, lastMode, lastCategoryID
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        appearance = try values.decodeIfPresent(String.self, forKey: .appearance) ?? "system"
        accentChoice = try values.decodeIfPresent(AccentChoice.self, forKey: .accentChoice) ?? .system
        customAccentHex = try values.decodeIfPresent(String.self, forKey: .customAccentHex) ?? "6E64D4"
        let glass = GlassStyle(opacity: try values.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? GlassStyle.defaultOpacity,
                               blur: try values.decodeIfPresent(Double.self, forKey: .backgroundBlur) ?? GlassStyle.defaultBlur)
        backgroundOpacity = glass.opacity
        backgroundBlur = glass.blur
        showMenuBarTime = try values.decodeIfPresent(Bool.self, forKey: .showMenuBarTime) ?? true
        breakEdgeGlowEnabled = try values.decodeIfPresent(Bool.self, forKey: .breakEdgeGlowEnabled) ?? true
        let glow = GlowStyle(width: try values.decodeIfPresent(Double.self, forKey: .glowWidth) ?? GlowStyle.defaultWidth,
                             intensity: try values.decodeIfPresent(Double.self, forKey: .glowIntensity) ?? GlowStyle.defaultIntensity)
        glowWidth = glow.width
        glowIntensity = glow.intensity
        animateLogo = try values.decodeIfPresent(Bool.self, forKey: .animateLogo) ?? true
        menuBarIcon = try values.decodeIfPresent(MenuBarIcon.self, forKey: .menuBarIcon) ?? .rhythm
        pomodoro = try values.decodeIfPresent(PomodoroSettings.self, forKey: .pomodoro) ?? PomodoroSettings()
        soundEnabled = try values.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        notificationsEnabled = try values.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        pauseOnLock = try values.decodeIfPresent(Bool.self, forKey: .pauseOnLock) ?? true
        idleCheckEnabled = try values.decodeIfPresent(Bool.self, forKey: .idleCheckEnabled) ?? true
        idleMinutes = min(30, max(1, try values.decodeIfPresent(Int.self, forKey: .idleMinutes) ?? 5))
        defaultMinutes = try values.decodeIfPresent(Int.self, forKey: .defaultMinutes) ?? 25
        lastMode = try values.decodeIfPresent(TrackingMode.self, forKey: .lastMode) ?? .countdown
        lastCategoryID = try values.decodeIfPresent(UUID.self, forKey: .lastCategoryID)
    }
}

public struct Ledger: Codable, Equatable, Sendable {
    public var version = 1
    public var categories: [TimeCategory]
    public var tasks: [PlanTask]
    public var dailyTaskSchedules: [DailyTaskSchedule]
    public var sessions: [WorkSession]
    public var activeSession: WorkSession?
    public var pomodoroProgress: PomodoroProgress?
    public var idleReview: IdleReview?
    public var preferences: Preferences

    public init(categories: [TimeCategory] = [
        TimeCategory(name: "Работа", color: .lavender),
        TimeCategory(name: "Учёба", color: .blue),
        TimeCategory(name: "Личное", color: .rose)
    ], tasks: [PlanTask] = [], sessions: [WorkSession] = [], activeSession: WorkSession? = nil, preferences: Preferences = Preferences(), pomodoroProgress: PomodoroProgress? = nil, idleReview: IdleReview? = nil, dailyTaskSchedules: [DailyTaskSchedule] = []) {
        self.categories = categories
        self.tasks = tasks
        self.dailyTaskSchedules = dailyTaskSchedules
        self.sessions = sessions
        self.activeSession = activeSession
        self.pomodoroProgress = pomodoroProgress
        self.idleReview = idleReview
        self.preferences = preferences
    }

    private enum CodingKeys: String, CodingKey {
        case version, categories, tasks, dailyTaskSchedules, sessions, activeSession, pomodoroProgress, idleReview, preferences
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        categories = try values.decode([TimeCategory].self, forKey: .categories)
        tasks = try values.decode([PlanTask].self, forKey: .tasks)
        dailyTaskSchedules = try values.decodeIfPresent([DailyTaskSchedule].self, forKey: .dailyTaskSchedules) ?? []
        sessions = try values.decode([WorkSession].self, forKey: .sessions)
        activeSession = try values.decodeIfPresent(WorkSession.self, forKey: .activeSession)
        pomodoroProgress = try values.decodeIfPresent(PomodoroProgress.self, forKey: .pomodoroProgress)
        idleReview = try values.decodeIfPresent(IdleReview.self, forKey: .idleReview)
        preferences = try values.decode(Preferences.self, forKey: .preferences)
    }

    public var visibleCategories: [TimeCategory] { categories.filter { !$0.isArchived } }

    public func category(_ id: UUID) -> TimeCategory? { categories.first { $0.id == id } }

    public func tasks(on day: Date, calendar: Calendar = .current) -> [PlanTask] {
        tasks.filter { calendar.isDate($0.day, inSameDayAs: day) }
            .sorted { lhs, rhs in
                if (lhs.completedAt == nil) != (rhs.completedAt == nil) { return lhs.completedAt == nil }
                return lhs.createdAt < rhs.createdAt
            }
    }

    public func total(on day: Date, categoryID: UUID? = nil, calendar: Calendar = .current, at now: Date) -> TimeInterval {
        guard let bounds = calendar.dateInterval(of: .day, for: day) else { return 0 }
        var total = 0.0
        for session in sessions where !session.isBreak && (categoryID == nil || session.categoryID == categoryID) {
            total += session.duration(in: bounds, at: now)
        }
        if let activeSession, !activeSession.isBreak, categoryID == nil || activeSession.categoryID == categoryID {
            total += activeSession.duration(in: bounds, at: now)
        }
        return total
    }

    public func tracked(for taskID: UUID, at now: Date) -> TimeInterval {
        var total = 0.0
        for session in sessions where !session.isBreak && session.taskID == taskID { total += session.elapsed(at: now) }
        if let activeSession, !activeSession.isBreak, activeSession.taskID == taskID { total += activeSession.elapsed(at: now) }
        return total
    }

    public func plannedMinutes(for categoryID: UUID, on day: Date, calendar: Calendar = .current) -> Int {
        if let category = category(categoryID), category.dailyGoalMinutes > 0 { return category.dailyGoalMinutes }
        let stored = tasks.lazy.filter { $0.categoryID == categoryID && calendar.isDate($0.day, inSameDayAs: day) }.reduce(0) { $0 + $1.plannedMinutes }
        return stored + dailyTaskSchedules.lazy.filter { schedule in
            schedule.categoryID == categoryID && schedule.includes(day, calendar: calendar)
                && !tasks.contains { $0.dailyScheduleID == schedule.id && calendar.isDate($0.day, inSameDayAs: day) }
        }.reduce(0) { $0 + $1.plannedMinutes }
    }

    /// Completes a countdown at its actual deadline even if a tick is delayed.
    @discardableResult
    public mutating func completeExpiredTimer(at now: Date) -> WorkSession? {
        guard var active = activeSession, let deadline = active.deadline, now >= deadline else { return nil }
        active.finish(at: deadline)
        if !active.isBreak { sessions.append(active) }
        if active.mode == .pomodoro {
            var progress = pomodoroProgress ?? PomodoroProgress()
            progress.complete(active.pomodoroPhase ?? .focus, settings: preferences.pomodoro)
            pomodoroProgress = progress
        }
        activeSession = nil
        return active
    }

    /// Stopping a partial focus keeps its actual work, without completing a pomodoro.
    @discardableResult
    public mutating func finishActiveSession(at date: Date) -> WorkSession? {
        guard var active = activeSession else { return nil }
        active.finish(at: date)
        if !active.isBreak { sessions.append(active) }
        if active.mode == .pomodoro {
            var progress = pomodoroProgress ?? PomodoroProgress()
            progress.nextPhase = .focus
            pomodoroProgress = progress
        }
        activeSession = nil
        return active
    }

    /// A reopened app never counts unobserved time as work.
    public mutating func recoverAfterRelaunch(lastCheckpoint: Date, at now: Date) {
        // Unobserved time after a crash must never be offered as recorded idle time.
        if let review = idleReview, review.returnedAt == nil { idleReview?.returnedAt = max(review.startedAt, min(lastCheckpoint, now)) }
        guard let active = activeSession, active.isRunning else { return }
        if let deadline = active.deadline, deadline <= lastCheckpoint {
            completeExpiredTimer(at: lastCheckpoint)
        } else {
            activeSession?.pause(at: min(now, max(active.intervals.last?.start ?? lastCheckpoint, lastCheckpoint)))
        }
    }
}

public enum TimeText {
    public static func clock(_ seconds: TimeInterval, countdown: Bool = false) -> String {
        let whole = max(0, Int(countdown ? ceil(seconds) : floor(seconds)))
        let hours = whole / 3600, minutes = (whole % 3600) / 60, rest = whole % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%02d:%02d", minutes, rest)
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        if seconds > 0 && minutes == 0 { return "< 1 мин" }
        if minutes >= 60 { return minutes % 60 == 0 ? "\(minutes / 60) ч" : "\(minutes / 60) ч \(minutes % 60) мин" }
        return "\(minutes) мин"
    }
}
