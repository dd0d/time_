import Foundation

public struct DailyTaskSchedule: Identifiable, Codable, Equatable, Sendable {
    private struct Revision: Codable, Equatable, Sendable {
        let startsOn: Date
        let title: String
        let categoryID: UUID
        let plannedMinutes: Int
    }

    public var id: UUID
    public var title: String
    public var categoryID: UUID
    public var plannedMinutes: Int
    public var startsOn: Date
    public var endsBefore: Date?
    public var createdAt: Date
    private var revisions: [Revision]?

    var isValidForRestore: Bool {
        (0...480).contains(plannedMinutes) && LedgerEnvelope.validDate(startsOn)
            && endsBefore.map(LedgerEnvelope.validDate) != false
            && revisions?.allSatisfy { (0...480).contains($0.plannedMinutes) && LedgerEnvelope.validDate($0.startsOn) } != false
    }

    public init(id: UUID = UUID(), task: PlanTask) {
        self.id = id
        title = task.title
        categoryID = task.categoryID
        plannedMinutes = task.plannedMinutes
        startsOn = task.day
        createdAt = task.createdAt
    }

    public func includes(_ day: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: day)
        return day >= calendar.startOfDay(for: startsOn)
            && (endsBefore == nil || day < calendar.startOfDay(for: endsBefore!))
    }

    func template(on day: Date, calendar: Calendar) -> (title: String, categoryID: UUID, plannedMinutes: Int) {
        let day = calendar.startOfDay(for: day)
        if let revision = revisions?.last(where: { calendar.startOfDay(for: $0.startsOn) <= day }) {
            return (revision.title, revision.categoryID, revision.plannedMinutes)
        }
        return (title, categoryID, plannedMinutes)
    }

    mutating func update(from task: PlanTask, calendar: Calendar) {
        let day = calendar.startOfDay(for: task.day)
        if day <= calendar.startOfDay(for: startsOn) {
            title = task.title
            categoryID = task.categoryID
            plannedMinutes = task.plannedMinutes
            revisions = nil
        } else {
            var earlier = (revisions ?? []).filter { calendar.startOfDay(for: $0.startsOn) < day }
            earlier.append(Revision(startsOn: day, title: task.title, categoryID: task.categoryID, plannedMinutes: task.plannedMinutes))
            revisions = earlier
        }
    }
}

extension Ledger {
    public mutating func addPlanTask(_ task: PlanTask, repeatsDaily: Bool = false, calendar: Calendar = .current) {
        var task = task
        task.day = calendar.startOfDay(for: task.day)
        if repeatsDaily {
            let schedule = DailyTaskSchedule(task: task)
            dailyTaskSchedules.append(schedule)
            task.dailyScheduleID = schedule.id
        }
        tasks.append(task)
    }

    /// Creates only the requested day's occurrences; opening the app after a long
    /// absence never produces a backlog of unchecked tasks for every missed day.
    @discardableResult
    public mutating func materializeDailyTasks(on day: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: day)
        var changed = false
        for schedule in dailyTaskSchedules where schedule.includes(day, calendar: calendar) {
            guard !tasks.contains(where: { $0.dailyScheduleID == schedule.id && calendar.isDate($0.day, inSameDayAs: day) }) else { continue }
            let template = schedule.template(on: day, calendar: calendar)
            tasks.append(PlanTask(title: template.title, categoryID: template.categoryID,
                                  plannedMinutes: template.plannedMinutes, day: day,
                                  createdAt: schedule.createdAt, dailyScheduleID: schedule.id))
            changed = true
        }
        return changed
    }

    /// Existing days keep their completion and session IDs. Changes to a daily
    /// task apply to this occurrence, prepared future occurrences and future days.
    public mutating func updatePlanTask(_ task: PlanTask, repeatsDaily: Bool, calendar: Calendar = .current) {
        guard let original = tasks.first(where: { $0.id == task.id }) else { return }
        var updated = task
        updated.day = calendar.startOfDay(for: task.day)
        if repeatsDaily {
            if let scheduleID = original.dailyScheduleID,
               let index = dailyTaskSchedules.firstIndex(where: { $0.id == scheduleID }) {
                // A recurring occurrence stays on its day; the editor exposes
                // date changes for new series and one-time tasks only.
                updated.day = original.day
                updated.dailyScheduleID = scheduleID
                dailyTaskSchedules[index].update(from: updated, calendar: calendar)
                let effectiveDay = calendar.startOfDay(for: original.day)
                for index in tasks.indices where tasks[index].dailyScheduleID == scheduleID && calendar.startOfDay(for: tasks[index].day) >= effectiveDay {
                    tasks[index].title = updated.title
                    tasks[index].categoryID = updated.categoryID
                    tasks[index].plannedMinutes = updated.plannedMinutes
                }
            } else {
                let schedule = DailyTaskSchedule(task: updated)
                dailyTaskSchedules.append(schedule)
                updated.dailyScheduleID = schedule.id
            }
        } else {
            if let scheduleID = original.dailyScheduleID {
                stopDailySchedule(scheduleID, from: original.day, keeping: original.id, calendar: calendar)
            }
            updated.dailyScheduleID = nil
        }
        if let index = tasks.firstIndex(where: { $0.id == updated.id }) { tasks[index] = updated }
    }

    public mutating func deletePlanTask(_ id: UUID, calendar: Calendar = .current) {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        if let scheduleID = task.dailyScheduleID {
            stopDailySchedule(scheduleID, from: task.day, calendar: calendar)
        } else {
            tasks.removeAll { $0.id == id }
        }
    }

    private mutating func stopDailySchedule(_ id: UUID, from day: Date, keeping taskID: UUID? = nil, calendar: Calendar) {
        let day = calendar.startOfDay(for: day)
        if let index = dailyTaskSchedules.firstIndex(where: { $0.id == id }) {
            dailyTaskSchedules[index].endsBefore = min(dailyTaskSchedules[index].endsBefore ?? day, day)
        }
        tasks.removeAll { $0.dailyScheduleID == id && calendar.startOfDay(for: $0.day) >= day && $0.id != taskID }
    }

    /// Daily progress uses the displayed day, including work spanning midnight.
    /// One-time tasks keep their total even when moved to another day.
    public func tracked(for task: PlanTask, calendar: Calendar = .current, at now: Date) -> TimeInterval {
        guard let scheduleID = task.dailyScheduleID else { return tracked(for: task.id, at: now) }
        guard let bounds = calendar.dateInterval(of: .day, for: task.day) else { return 0 }
        let ids = Set(tasks.lazy.filter { $0.dailyScheduleID == scheduleID }.map(\.id))
        var total = 0.0
        for session in sessions where !session.isBreak && session.taskID.map(ids.contains) == true {
            total += session.duration(in: bounds, at: now)
        }
        if let activeSession, !activeSession.isBreak, activeSession.taskID.map(ids.contains) == true {
            total += activeSession.duration(in: bounds, at: now)
        }
        return total
    }
}
