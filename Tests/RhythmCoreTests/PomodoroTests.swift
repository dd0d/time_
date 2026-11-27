import XCTest
@testable import RhythmCore

final class PomodoroTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_700_000_000)
    private let category = UUID()

    func testFourFocusRoundsLeadToLongBreakAndBreaksNeverEnterWorkTotals() {
        var ledger = Ledger()
        var cursor = origin
        for round in 1...4 {
            ledger.activeSession = WorkSession(title: "", categoryID: category, mode: .pomodoro, targetSeconds: 1500, startedAt: cursor, pomodoroPhase: .focus)
            cursor += 1500
            let completed = ledger.completeExpiredTimer(at: cursor.addingTimeInterval(7))
            XCTAssertEqual(completed?.elapsed(at: cursor), 1500)
            XCTAssertEqual(ledger.pomodoroProgress?.completedFocusCount, round)
            let phase = round == 4 ? PomodoroPhase.longBreak : .shortBreak
            XCTAssertEqual(ledger.pomodoroProgress?.nextPhase, phase)
            let breakLength = ledger.preferences.pomodoro.seconds(for: phase)
            ledger.activeSession = WorkSession(title: "", categoryID: category, mode: .pomodoro, targetSeconds: breakLength, startedAt: cursor, pomodoroPhase: phase)
            cursor += breakLength
            XCTAssertTrue(ledger.completeExpiredTimer(at: cursor)?.isBreak == true)
            XCTAssertEqual(ledger.pomodoroProgress?.nextPhase, .focus)
            XCTAssertEqual(ledger.sessions.count, round)
        }
        XCTAssertEqual(ledger.sessions.reduce(0) { $0 + $1.elapsed(at: cursor) }, 6000)
    }

    func testPartialFocusSavesWorkWithoutCompletingRoundAndSkippingBreakAddsNoWork() {
        var ledger = Ledger(activeSession: WorkSession(title: "", categoryID: category, mode: .pomodoro, targetSeconds: 1500, startedAt: origin, pomodoroPhase: .focus))
        ledger.finishActiveSession(at: origin.addingTimeInterval(100))
        XCTAssertEqual(ledger.sessions.count, 1)
        XCTAssertEqual(ledger.sessions[0].elapsed(at: origin.addingTimeInterval(9999)), 100)
        XCTAssertEqual(ledger.pomodoroProgress?.completedFocusCount, 0)
        ledger.activeSession = WorkSession(title: "", categoryID: category, mode: .pomodoro, targetSeconds: 300, startedAt: origin.addingTimeInterval(100), pomodoroPhase: .shortBreak)
        ledger.finishActiveSession(at: origin.addingTimeInterval(200))
        XCTAssertEqual(ledger.sessions.count, 1)
        XCTAssertEqual(ledger.pomodoroProgress?.nextPhase, .focus)
    }

    func testPomodoroPauseMovesDeadlineAndRecoveryDoesNotInventWork() {
        var session = WorkSession(title: "", categoryID: category, mode: .pomodoro, targetSeconds: 1500, startedAt: origin, pomodoroPhase: .focus)
        session.pause(at: origin.addingTimeInterval(100))
        session.resume(at: origin.addingTimeInterval(500))
        XCTAssertEqual(session.deadline, origin.addingTimeInterval(1900))
        var ledger = Ledger(activeSession: session)
        ledger.recoverAfterRelaunch(lastCheckpoint: origin.addingTimeInterval(700), at: origin.addingTimeInterval(4000))
        XCTAssertEqual(ledger.activeSession?.elapsed(at: origin.addingTimeInterval(4000)), 300)
        XCTAssertTrue(ledger.activeSession?.isPaused == true)
        XCTAssertNil(ledger.pomodoroProgress)
    }

    func testBreaksAreExcludedFromActiveTotalsAndCSV() {
        let pause = WorkSession(title: "", categoryID: category, mode: .pomodoro, targetSeconds: 300, startedAt: origin, pomodoroPhase: .shortBreak)
        let ledger = Ledger(activeSession: pause)
        XCTAssertEqual(ledger.total(on: origin, at: origin.addingTimeInterval(60)), 0)
        XCTAssertEqual(CSVExport.sessions([pause], categories: []).split(separator: "\n").count, 1)
        XCTAssertEqual(pause.displayTitle, "Короткий перерыв")
        XCTAssertEqual(WorkSession(title: "  ", categoryID: category, mode: .stopwatch, startedAt: origin).displayTitle, "Фокус")
    }

    func testVersion12LedgerLoadsWithoutPomodoroFields() throws {
        let session = WorkSession(title: "SQL", categoryID: category, mode: .countdown, targetSeconds: 1500, startedAt: origin)
        let ledger = Ledger(sessions: [session])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ledger)) as? [String: Any])
        var preferences = try XCTUnwrap(json["preferences"] as? [String: Any])
        preferences.removeValue(forKey: "pomodoro")
        json["preferences"] = preferences
        json.removeValue(forKey: "pomodoroProgress")
        let decoded = try JSONDecoder().decode(Ledger.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.sessions, [session])
        XCTAssertEqual(decoded.preferences.pomodoro, PomodoroSettings())
        XCTAssertNil(decoded.pomodoroProgress)
    }
}
