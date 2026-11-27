import XCTest
@testable import RhythmCore

final class AnalyticsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }
    private let category = TimeCategory(name: "SQL", color: .blue, isArchived: true)

    private func date(_ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func session(from start: Date, seconds: Double, mode: TrackingMode = .stopwatch, phase: PomodoroPhase? = nil) -> WorkSession {
        var session = WorkSession(title: "", categoryID: category.id, mode: mode, targetSeconds: seconds, startedAt: start, pomodoroPhase: phase)
        session.finish(at: start.addingTimeInterval(seconds))
        return session
    }

    func testCalendarHeatmapSplitsMidnightAndDSTWithoutLosingOrDuplicatingTime() {
        let start = date(24, hour: 23)
        let end = date(25, hour: 4) // Includes the repeated hour during DST.
        let work = session(from: start, seconds: end.timeIntervalSince(start))
        let ledger = Ledger(categories: [category], sessions: [work])
        let report = AnalyticsSnapshot(ledger: ledger, endingOn: date(25), periodDays: 7, at: date(26), calendar: calendar)
        XCTAssertEqual(report.days.count, 365)
        XCTAssertEqual(report.days.first?.date, calendar.date(byAdding: .day, value: -364, to: date(25)))
        XCTAssertEqual(report.days.last?.date, date(25))
        XCTAssertEqual(report.days.first(where: { $0.date == date(24) })?.seconds, 3600)
        XCTAssertEqual(report.days.last?.seconds, 5 * 3600)
        XCTAssertEqual(report.totalSeconds, 6 * 3600)
        XCTAssertEqual(report.sessionCount, 1)
        XCTAssertEqual(report.categories.first?.categoryID, category.id)
    }

    func testAnalyticsCountsOnlyWorkedIntervalsAndCompletedFocusPomodoros() {
        var work = WorkSession(title: "", categoryID: category.id, mode: .pomodoro, targetSeconds: 1500, startedAt: date(27, hour: 9), pomodoroPhase: .focus)
        work.pause(at: work.startedAt.addingTimeInterval(100))
        work.resume(at: work.startedAt.addingTimeInterval(700))
        work.finish(at: work.startedAt.addingTimeInterval(2100))
        let rest = session(from: date(27, hour: 10), seconds: 300, mode: .pomodoro, phase: .shortBreak)
        let partial = session(from: date(26, hour: 9), seconds: 100, mode: .pomodoro, phase: .focus)
        var shorter = partial
        shorter.targetSeconds = 1500
        let report = AnalyticsSnapshot(ledger: Ledger(sessions: [work, rest, shorter]), endingOn: date(27), periodDays: 7, at: date(27, hour: 18), calendar: calendar)
        XCTAssertEqual(report.totalSeconds, 1600)
        XCTAssertEqual(report.sessionCount, 2)
        XCTAssertEqual(report.completedPomodoros, 1)
        XCTAssertEqual(report.longestSession, 1500)
        XCTAssertEqual(report.averageSession, 800)
        XCTAssertEqual(report.activeDays, 2)
    }

    func testComparisonPeriodsAndCurrentSeriesAllowAnEmptyToday() {
        let ledger = Ledger(sessions: [
            session(from: date(26, hour: 9), seconds: 1800),
            session(from: date(25, hour: 9), seconds: 3600),
            session(from: date(18, hour: 9), seconds: 900)
        ])
        let report = AnalyticsSnapshot(ledger: ledger, endingOn: date(27), periodDays: 7, at: date(27, hour: 10), calendar: calendar)
        XCTAssertEqual(report.totalSeconds, 5400)
        XCTAssertEqual(report.previousSeconds, 900)
        XCTAssertEqual(report.currentStreak, 2)
        XCTAssertEqual(report.bestStreak, 2)
        XCTAssertEqual(report.weekdayAverages.count, 7)
        XCTAssertEqual(report.weekdayAverages[0], 1800)
        XCTAssertEqual(report.weekdayAverages[6], 3600)
    }

    func testActiveSessionIsClippedAtNowAndFutureDaysAreNotCreated() {
        let work = WorkSession(title: "", categoryID: category.id, mode: .stopwatch, startedAt: date(27, hour: 9))
        let report = AnalyticsSnapshot(ledger: Ledger(activeSession: work), endingOn: date(29), at: date(27, hour: 10), calendar: calendar)
        XCTAssertEqual(report.totalSeconds, 3600)
        XCTAssertEqual(report.days.last?.date, date(27))
        XCTAssertEqual(report.currentStreak, 1)
    }
}
