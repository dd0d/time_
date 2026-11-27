import XCTest
@testable import RhythmCore

final class TrackingTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_700_000_000)
    private let categoryID = UUID()

    func testPauseAndResumeOnlyCountsWorkedIntervals() {
        var session = WorkSession(title: "Задача", categoryID: categoryID, mode: .stopwatch, startedAt: origin)
        session.pause(at: origin.addingTimeInterval(90))
        XCTAssertEqual(session.elapsed(at: origin.addingTimeInterval(900)), 90)
        session.pause(at: origin.addingTimeInterval(910))
        XCTAssertEqual(session.intervals.count, 1)
        session.resume(at: origin.addingTimeInterval(1000))
        session.resume(at: origin.addingTimeInterval(1001))
        XCTAssertEqual(session.intervals.count, 2)
        session.finish(at: origin.addingTimeInterval(1030))
        XCTAssertEqual(session.elapsed(at: origin.addingTimeInterval(2000)), 120)
        XCTAssertFalse(session.isRunning)
        XCTAssertFalse(session.isPaused)
    }

    func testDelayedTimerTickFinishesExactlyAtDeadlineOnce() {
        let session = WorkSession(title: "Таймер", categoryID: categoryID, mode: .countdown, targetSeconds: 1500, startedAt: origin)
        var ledger = Ledger(activeSession: session)
        XCTAssertNil(ledger.completeExpiredTimer(at: origin.addingTimeInterval(1499)))
        let completed = ledger.completeExpiredTimer(at: origin.addingTimeInterval(1507))
        XCTAssertEqual(completed?.endedAt, origin.addingTimeInterval(1500))
        XCTAssertEqual(completed?.elapsed(at: origin.addingTimeInterval(9999)), 1500)
        XCTAssertNil(ledger.completeExpiredTimer(at: origin.addingTimeInterval(1600)))
        XCTAssertEqual(ledger.sessions.count, 1)
        XCTAssertNil(ledger.activeSession)
    }

    func testCountdownDeadlineMovesAfterPauseAndExtension() {
        var session = WorkSession(title: "Таймер", categoryID: categoryID, mode: .countdown, targetSeconds: 600, startedAt: origin)
        session.pause(at: origin.addingTimeInterval(200))
        XCTAssertNil(session.deadline)
        session.resume(at: origin.addingTimeInterval(500))
        XCTAssertEqual(session.deadline, origin.addingTimeInterval(900))
        session.targetSeconds += 300
        XCTAssertEqual(session.deadline, origin.addingTimeInterval(1200))
        XCTAssertEqual(session.remaining(at: origin.addingTimeInterval(600)), 600)
    }

    func testCrashRecoveryDoesNotCountTimeWhileAppWasClosed() {
        var ledger = Ledger(activeSession: WorkSession(title: "Проект", categoryID: categoryID, mode: .stopwatch, startedAt: origin))
        ledger.recoverAfterRelaunch(lastCheckpoint: origin.addingTimeInterval(120), at: origin.addingTimeInterval(3600))
        XCTAssertEqual(ledger.activeSession?.elapsed(at: origin.addingTimeInterval(3600)), 120)
        XCTAssertTrue(ledger.activeSession!.isPaused)
        ledger.activeSession?.resume(at: origin.addingTimeInterval(3700))
        XCTAssertEqual(ledger.activeSession?.elapsed(at: origin.addingTimeInterval(3730)), 150)
    }

    func testRecoveryPreservesAlreadyPausedSession() {
        var session = WorkSession(title: "Проект", categoryID: categoryID, mode: .stopwatch, startedAt: origin)
        session.pause(at: origin.addingTimeInterval(70))
        var ledger = Ledger(activeSession: session)
        ledger.recoverAfterRelaunch(lastCheckpoint: origin.addingTimeInterval(100), at: origin.addingTimeInterval(4000))
        XCTAssertEqual(ledger.activeSession?.elapsed(at: origin.addingTimeInterval(4000)), 70)
    }

    func testSessionCrossingMidnightSplitsIntoCorrectDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 10800)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 23, minute: 50))!
        var session = WorkSession(title: "Ночная задача", categoryID: categoryID, mode: .stopwatch, startedAt: start)
        session.finish(at: start.addingTimeInterval(1800))
        let nextDay = calendar.date(byAdding: .day, value: 1, to: start)!
        XCTAssertEqual(session.duration(on: start, calendar: calendar, at: nextDay), 600)
        XCTAssertEqual(session.duration(on: nextDay, calendar: calendar, at: nextDay), 1200)
        let ledger = Ledger(sessions: [session])
        XCTAssertEqual(ledger.total(on: start, calendar: calendar, at: nextDay) + ledger.total(on: nextDay, calendar: calendar, at: nextDay), 1800)
    }

    func testDayWithDSTTransitionUsesActualCalendarBounds() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25))!
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        var session = WorkSession(title: "DST", categoryID: categoryID, mode: .stopwatch, startedAt: start)
        session.finish(at: end)
        XCTAssertEqual(session.duration(on: start, calendar: calendar, at: end), 25 * 3600)
    }

    func testGoalsUseTaskEstimatesUntilAnExplicitGoalIsSet() {
        var ledger = Ledger(categories: [TimeCategory(id: categoryID, name: "Работа", color: .mint)])
        ledger.tasks = [
            PlanTask(title: "A", categoryID: categoryID, plannedMinutes: 25, day: origin),
            PlanTask(title: "B", categoryID: categoryID, plannedMinutes: 45, day: origin, completedAt: origin),
            PlanTask(title: "Завтра", categoryID: categoryID, plannedMinutes: 100, day: origin.addingTimeInterval(86400))
        ]
        XCTAssertEqual(ledger.plannedMinutes(for: categoryID, on: origin), 70)
        ledger.categories[0].dailyGoalMinutes = 120
        XCTAssertEqual(ledger.plannedMinutes(for: categoryID, on: origin), 120)
    }

    func testTaskTotalsSurviveRenameAndCategoryArchive() {
        let taskID = UUID()
        var session = WorkSession(title: "Старое имя", categoryID: categoryID, taskID: taskID, mode: .stopwatch, startedAt: origin)
        session.finish(at: origin.addingTimeInterval(75))
        let ledger = Ledger(categories: [TimeCategory(id: categoryID, name: "Архив", color: .blue, isArchived: true)], sessions: [session])
        XCTAssertEqual(ledger.tracked(for: taskID, at: origin.addingTimeInterval(1000)), 75)
        XCTAssertTrue(ledger.visibleCategories.isEmpty)
        XCTAssertNotNil(ledger.category(categoryID))
    }

    func testTimeFormattingDoesNotPrematurelyFinishCountdown() {
        XCTAssertEqual(TimeText.clock(0.1, countdown: true), "00:01")
        XCTAssertEqual(TimeText.clock(0.9), "00:00")
        XCTAssertEqual(TimeText.clock(3661), "1:01:01")
        XCTAssertEqual(TimeText.duration(59), "< 1 мин")
        XCTAssertEqual(TimeText.duration(3660), "1 ч 1 мин")
    }
}
