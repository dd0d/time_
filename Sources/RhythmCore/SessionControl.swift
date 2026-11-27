import Foundation

public struct IdleReview: Codable, Equatable, Sendable {
    public var sessionID: UUID
    public var startedAt: Date
    public var detectedAt: Date
    public var returnedAt: Date?

    public init(sessionID: UUID, startedAt: Date, detectedAt: Date, returnedAt: Date? = nil) {
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.detectedAt = detectedAt
        self.returnedAt = returnedAt
    }

    public func duration(at now: Date) -> TimeInterval { max(0, (returnedAt ?? now).timeIntervalSince(startedAt)) }
}

extension Ledger {
    /// Pause at the last input, retaining the disputed span until the user chooses.
    @discardableResult
    public mutating func detectIdle(at date: Date, idleFor seconds: TimeInterval) -> Bool {
        guard preferences.idleCheckEnabled, idleReview == nil,
              seconds.isFinite, seconds >= 0,
              var active = activeSession, active.isRunning, !active.isBreak,
              let interval = active.intervals.last else { return false }
        let start = max(interval.start, date.addingTimeInterval(-seconds))
        if let deadline = active.deadline, deadline <= start { return false }
        guard date.timeIntervalSince(start) >= Double(min(30, max(1, preferences.idleMinutes)) * 60) else { return false }
        active.pause(at: start)
        activeSession = active
        idleReview = IdleReview(sessionID: active.id, startedAt: start, detectedAt: date)
        return true
    }

    @discardableResult
    public mutating func detectReturn(at date: Date, idleFor seconds: TimeInterval) -> Bool {
        guard let review = idleReview, review.returnedAt == nil, seconds.isFinite, seconds >= 0 else { return false }
        let inputDate = date.addingTimeInterval(-seconds)
        guard inputDate > review.detectedAt else { return false }
        idleReview?.returnedAt = min(date, max(review.startedAt, inputDate))
        return true
    }

    public mutating func endIdleObservation(at date: Date) {
        if let review = idleReview, review.returnedAt == nil { idleReview?.returnedAt = max(review.startedAt, date) }
    }

    @discardableResult
    public mutating func resolveIdle(includeTime: Bool, resume: Bool, at date: Date) -> WorkSession? {
        guard let review = idleReview else { return nil }
        defer { idleReview = nil }
        guard var active = activeSession, active.id == review.sessionID else { return nil }
        let end = min(date, review.returnedAt ?? date)
        if includeTime, end > review.startedAt {
            let included = active.mode.isTimed ? min(end.timeIntervalSince(review.startedAt), active.remaining(at: date)) : end.timeIntervalSince(review.startedAt)
            active.intervals.append(WorkInterval(start: review.startedAt, end: review.startedAt.addingTimeInterval(included)))
        }
        if active.mode.isTimed, active.elapsed(at: date) >= active.targetSeconds {
            active.resume(at: active.intervals.last?.end ?? date)
            activeSession = active
            return completeExpiredTimer(at: date)
        }
        if resume { active.resume(at: date) }
        activeSession = active
        return nil
    }

    /// Keep the elapsed work in its old category and carry the remaining timer forward.
    @discardableResult
    public mutating func changeActiveCategory(to categoryID: UUID, at date: Date) -> WorkSession? {
        guard idleReview == nil, var current = activeSession, current.categoryID != categoryID else { return nil }
        if current.isBreak {
            current.categoryID = categoryID
            activeSession = current
            return nil
        }
        let running = current.isRunning
        let remaining = current.mode.isTimed ? current.remaining(at: date) : 0
        current.finish(at: date)
        if current.elapsed(at: date) > 0 { sessions.append(current) }
        var next = WorkSession(title: current.taskID == nil ? current.title : "", categoryID: categoryID, mode: current.mode,
                               targetSeconds: remaining, startedAt: date, pomodoroPhase: current.pomodoroPhase)
        if !running { next.pause(at: date) }
        activeSession = next
        return current
    }

    /// An automatic transition may start rest, but never another work session.
    @discardableResult
    public mutating func startAutomaticBreak(after completed: WorkSession) -> Bool {
        guard preferences.pomodoro.autoStartBreaks, activeSession == nil, idleReview == nil,
              completed.mode == .pomodoro, completed.pomodoroPhase == .focus,
              let start = completed.endedAt, let phase = pomodoroProgress?.nextPhase, phase.isBreak else { return false }
        activeSession = WorkSession(title: completed.title, categoryID: completed.categoryID, mode: .pomodoro,
                                    targetSeconds: preferences.pomodoro.seconds(for: phase), startedAt: start, pomodoroPhase: phase)
        return true
    }
}
