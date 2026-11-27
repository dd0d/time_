import XCTest
@testable import RhythmCore

final class TaskRecurrenceTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func day(_ number: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: number))!
    }

    private func makeTask(_ ledger: Ledger, on day: Date) -> PlanTask {
        PlanTask(title: "SQL", categoryID: ledger.categories[0].id, plannedMinutes: 60, day: day)
    }

    func testDailyCompletionDoesNotCompleteTomorrowOrDuplicateOccurrences() throws {
        var ledger = Ledger()
        let first = makeTask(ledger, on: day(7))
        ledger.addPlanTask(first, repeatsDaily: true, calendar: calendar)
        ledger.tasks[0].completedAt = day(7).addingTimeInterval(3600)
        XCTAssertFalse(ledger.materializeDailyTasks(on: day(7), calendar: calendar))
        XCTAssertTrue(ledger.materializeDailyTasks(on: day(8), calendar: calendar))
        XCTAssertFalse(ledger.materializeDailyTasks(on: day(8).addingTimeInterval(12 * 3600), calendar: calendar))
        let tomorrow = try XCTUnwrap(ledger.tasks(on: day(8), calendar: calendar).first)
        XCTAssertNotEqual(tomorrow.id, first.id)
        XCTAssertEqual(tomorrow.dailyScheduleID, ledger.tasks[0].dailyScheduleID)
        XCTAssertNil(tomorrow.completedAt)
        XCTAssertEqual(tomorrow.plannedMinutes, 60)
        XCTAssertNotNil(ledger.tasks(on: day(7), calendar: calendar).first?.completedAt)
        XCTAssertEqual(ledger.tasks.count, 2)
    }

    func testOneTimeAndFutureDailyStartRemainSeparate() {
        var ledger = Ledger()
        var oneTime = makeTask(ledger, on: day(7))
        oneTime.completedAt = day(7)
        ledger.addPlanTask(oneTime, calendar: calendar)
        ledger.addPlanTask(makeTask(ledger, on: day(10)), repeatsDaily: true, calendar: calendar)
        XCTAssertFalse(ledger.materializeDailyTasks(on: day(8), calendar: calendar))
        XCTAssertTrue(ledger.tasks(on: day(8), calendar: calendar).isEmpty)
        XCTAssertTrue(ledger.materializeDailyTasks(on: day(20), calendar: calendar))
        XCTAssertEqual(ledger.tasks.count, 3, "Missed days must not be generated as a backlog")
        XCTAssertEqual(ledger.tasks(on: day(20), calendar: calendar).count, 1)
    }

    func testDailyProgressResetsAcrossMidnightAndDST() throws {
        var ledger = Ledger()
        ledger.addPlanTask(makeTask(ledger, on: day(7)), repeatsDaily: true, calendar: calendar)
        ledger.materializeDailyTasks(on: day(8), calendar: calendar)
        ledger.materializeDailyTasks(on: day(9), calendar: calendar)
        let first = ledger.tasks[0]
        let second = ledger.tasks[1]
        let third = ledger.tasks[2]
        let midnight = day(8)
        var session = WorkSession(title: first.title, categoryID: first.categoryID, taskID: first.id,
                                  mode: .stopwatch, startedAt: midnight.addingTimeInterval(-600))
        session.finish(at: midnight.addingTimeInterval(1200))
        ledger.sessions.append(session)
        XCTAssertEqual(ledger.tracked(for: first, calendar: calendar, at: day(10)), 600)
        XCTAssertEqual(ledger.tracked(for: second, calendar: calendar, at: day(10)), 1200)
        XCTAssertEqual(ledger.tracked(for: third, calendar: calendar, at: day(10)), 0)
        XCTAssertEqual(calendar.dateInterval(of: .day, for: day(8))!.duration, 23 * 3600)
        XCTAssertEqual(ledger.plannedMinutes(for: first.categoryID, on: day(9), calendar: calendar), 60)
        XCTAssertEqual(ledger.plannedMinutes(for: first.categoryID, on: day(10), calendar: calendar), 60,
                       "The next day's target is available even before its occurrence is stored")
    }

    func testEditingDailyTaskUpdatesFutureAndKeepsPreviousCompletionAndIDs() throws {
        var ledger = Ledger()
        ledger.addPlanTask(makeTask(ledger, on: day(7)), repeatsDaily: true, calendar: calendar)
        ledger.tasks[0].completedAt = day(7)
        ledger.materializeDailyTasks(on: day(8), calendar: calendar)
        ledger.materializeDailyTasks(on: day(9), calendar: calendar)
        let original = ledger.tasks[0]
        let futureID = ledger.tasks[2].id
        var task = ledger.tasks[1]
        task.title = "SQL практика"
        task.plannedMinutes = 90
        ledger.updatePlanTask(task, repeatsDaily: true, calendar: calendar)
        XCTAssertEqual(ledger.tasks[0], original)
        XCTAssertEqual(ledger.tasks[2].id, futureID)
        XCTAssertEqual(ledger.tasks[2].title, "SQL практика")
        ledger.materializeDailyTasks(on: day(10), calendar: calendar)
        XCTAssertEqual(ledger.tasks.last?.plannedMinutes, 90)
        XCTAssertEqual(ledger.tasks.last?.title, "SQL практика")
        XCTAssertEqual(ledger.dailyTaskSchedules.count, 1)
    }

    func testDisablingDailyKeepsThisDayAndPastButRemovesFutureOccurrences() {
        var ledger = Ledger()
        ledger.addPlanTask(makeTask(ledger, on: day(7)), repeatsDaily: true, calendar: calendar)
        ledger.materializeDailyTasks(on: day(8), calendar: calendar)
        ledger.materializeDailyTasks(on: day(9), calendar: calendar)
        let original = ledger.tasks[0]
        let task = ledger.tasks[1]
        ledger.updatePlanTask(task, repeatsDaily: false, calendar: calendar)
        XCTAssertEqual(ledger.tasks[0], original)
        XCTAssertEqual(ledger.tasks.count, 2)
        XCTAssertNil(ledger.tasks[1].dailyScheduleID)
        XCTAssertFalse(ledger.materializeDailyTasks(on: day(10), calendar: calendar))
        XCTAssertEqual(ledger.plannedMinutes(for: task.categoryID, on: day(10), calendar: calendar), 0)
        XCTAssertEqual(ledger.tasks[1].id, task.id)
    }

    func testDeletingDailyStopsRepeatsAndKeepsPastAndRecordedTime() {
        var ledger = Ledger()
        ledger.addPlanTask(makeTask(ledger, on: day(7)), repeatsDaily: true, calendar: calendar)
        ledger.materializeDailyTasks(on: day(8), calendar: calendar)
        let task = ledger.tasks[1]
        var session = WorkSession(title: task.title, categoryID: task.categoryID, taskID: task.id,
                                  mode: .stopwatch, startedAt: day(8))
        session.finish(at: day(8).addingTimeInterval(600))
        ledger.sessions.append(session)
        ledger.deletePlanTask(task.id, calendar: calendar)
        XCTAssertEqual(ledger.tasks.count, 1)
        XCTAssertEqual(ledger.tasks.first?.day, day(7))
        XCTAssertEqual(ledger.sessions, [session])
        XCTAssertFalse(ledger.materializeDailyTasks(on: day(9), calendar: calendar))
    }

    func testConvertingCompletedOneTimeToDailyKeepsItsCompletionOnlyForThatDay() throws {
        var ledger = Ledger()
        var task = makeTask(ledger, on: day(7))
        task.completedAt = day(7)
        ledger.addPlanTask(task, calendar: calendar)
        ledger.updatePlanTask(task, repeatsDaily: true, calendar: calendar)
        ledger.materializeDailyTasks(on: day(8), calendar: calendar)
        XCTAssertEqual(ledger.tasks[0].id, task.id)
        XCTAssertEqual(ledger.tasks[0].completedAt, task.completedAt)
        XCTAssertNil(ledger.tasks[1].completedAt)
        let decoded = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger))
        XCTAssertEqual(decoded, ledger)
        XCTAssertFalse(try XCTUnwrap(decoded.dailyTaskSchedules.first).includes(day(6), calendar: calendar))
    }

    func testLegacyLedgerDecodesWithExistingTasksAsOneTime() throws {
        var ledger = Ledger()
        ledger.addPlanTask(makeTask(ledger, on: day(7)), calendar: calendar)
        let encoded = try JSONEncoder().encode(ledger)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json.removeValue(forKey: "dailyTaskSchedules")
        let legacy = try JSONSerialization.data(withJSONObject: json)
        var decoded = try JSONDecoder().decode(Ledger.self, from: legacy)
        XCTAssertEqual(decoded.tasks, ledger.tasks)
        XCTAssertNil(decoded.tasks[0].dailyScheduleID)
        XCTAssertTrue(decoded.dailyTaskSchedules.isEmpty)
        XCTAssertFalse(decoded.materializeDailyTasks(on: day(8), calendar: calendar))
    }

    func testDailyTaskWithoutTimeGoalRepeatsWithoutAddingMinutesToPlan() throws {
        var ledger = Ledger()
        var task = makeTask(ledger, on: day(7))
        task.plannedMinutes = 0
        ledger.addPlanTask(task, repeatsDaily: true, calendar: calendar)
        var timed = makeTask(ledger, on: day(8))
        timed.plannedMinutes = 25
        ledger.addPlanTask(timed, calendar: calendar)
        ledger.materializeDailyTasks(on: day(8), calendar: calendar)
        XCTAssertEqual(ledger.tasks(on: day(8), calendar: calendar).count, 2)
        XCTAssertEqual(ledger.plannedMinutes(for: task.categoryID, on: day(8), calendar: calendar), 25)
        let repeated = try XCTUnwrap(ledger.tasks.last)
        XCTAssertEqual(repeated.plannedMinutes, 0)
        let decoded = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger))
        XCTAssertEqual(decoded, ledger)
    }
}
