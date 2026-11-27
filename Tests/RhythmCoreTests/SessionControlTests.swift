import XCTest
@testable import RhythmCore

final class SessionControlTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_700_000_000)
    private let first = UUID(), second = UUID()

    private func workingLedger(mode: TrackingMode = .stopwatch, target: Double = 0) -> Ledger {
        Ledger(activeSession: WorkSession(title: "SQL", categoryID: first, mode: mode, targetSeconds: target, startedAt: origin, pomodoroPhase: mode == .pomodoro ? .focus : nil))
    }

    func testCategorySwitchPreservesOldWorkAndOriginalCountdownDeadline() {
        var ledger = workingLedger(mode: .countdown, target: 1500)
        ledger.changeActiveCategory(to: second, at: origin.addingTimeInterval(300))
        XCTAssertEqual(ledger.sessions.count, 1)
        XCTAssertEqual(ledger.sessions[0].categoryID, first)
        XCTAssertEqual(ledger.sessions[0].elapsed(at: origin.addingTimeInterval(9999)), 300)
        XCTAssertEqual(ledger.activeSession?.categoryID, second)
        XCTAssertEqual(ledger.activeSession?.targetSeconds, 1200)
        XCTAssertEqual(ledger.activeSession?.deadline, origin.addingTimeInterval(1500))
        ledger.completeExpiredTimer(at: origin.addingTimeInterval(1600))
        XCTAssertEqual(ledger.sessions.reduce(0) { $0 + $1.elapsed(at: origin.addingTimeInterval(9999)) }, 1500)
    }

    func testSwitchingPausedTaskKeepsPauseAndOldTaskAssociationOnlyOnSavedWork() {
        var ledger = workingLedger(mode: .pomodoro, target: 1500)
        let task = UUID()
        ledger.activeSession?.taskID = task
        ledger.activeSession?.pause(at: origin.addingTimeInterval(300))
        ledger.changeActiveCategory(to: second, at: origin.addingTimeInterval(900))
        XCTAssertTrue(ledger.activeSession?.isPaused == true)
        XCTAssertEqual(ledger.activeSession?.elapsed(at: origin.addingTimeInterval(9999)), 0)
        XCTAssertEqual(ledger.activeSession?.targetSeconds, 1200)
        XCTAssertNil(ledger.activeSession?.taskID)
        XCTAssertEqual(ledger.activeSession?.title, "")
        XCTAssertEqual(ledger.sessions[0].taskID, task)
        ledger.activeSession?.resume(at: origin.addingTimeInterval(1000))
        ledger.completeExpiredTimer(at: origin.addingTimeInterval(2201))
        XCTAssertEqual(ledger.pomodoroProgress?.completedFocusCount, 1)
    }

    func testSwitchDuringBreakDoesNotCreateWorkAndSelectingSameCategoryIsNoOp() {
        var ledger = workingLedger()
        let original = ledger
        XCTAssertNil(ledger.changeActiveCategory(to: first, at: origin.addingTimeInterval(100)))
        XCTAssertEqual(ledger, original)
        ledger.activeSession?.mode = .pomodoro
        ledger.activeSession?.pomodoroPhase = .shortBreak
        ledger.changeActiveCategory(to: second, at: origin.addingTimeInterval(100))
        XCTAssertTrue(ledger.sessions.isEmpty)
        XCTAssertEqual(ledger.activeSession?.categoryID, second)
    }

    func testIdlePauseIsProvisionalAndExcludingKeepsOnlyWorkAndResumedTime() {
        var ledger = workingLedger()
        XCTAssertTrue(ledger.detectIdle(at: origin.addingTimeInterval(900), idleFor: 600))
        XCTAssertEqual(ledger.activeSession?.elapsed(at: origin.addingTimeInterval(1200)), 300)
        XCTAssertEqual(ledger.idleReview?.startedAt, origin.addingTimeInterval(300))
        XCTAssertFalse(ledger.detectReturn(at: origin.addingTimeInterval(1100), idleFor: 500))
        XCTAssertTrue(ledger.detectReturn(at: origin.addingTimeInterval(1200), idleFor: 0))
        XCTAssertFalse(ledger.detectReturn(at: origin.addingTimeInterval(1201), idleFor: 0))
        ledger.resolveIdle(includeTime: false, resume: true, at: origin.addingTimeInterval(1300))
        XCTAssertNil(ledger.idleReview)
        XCTAssertEqual(ledger.activeSession?.elapsed(at: origin.addingTimeInterval(1350)), 350)
    }

    func testIncludingIdleExcludesTheTimeSpentWaitingForADecision() {
        var ledger = workingLedger()
        ledger.detectIdle(at: origin.addingTimeInterval(900), idleFor: 600)
        ledger.detectReturn(at: origin.addingTimeInterval(1200), idleFor: 0)
        ledger.resolveIdle(includeTime: true, resume: true, at: origin.addingTimeInterval(1300))
        XCTAssertEqual(ledger.activeSession?.elapsed(at: origin.addingTimeInterval(1350)), 1250)
    }

    func testIncludedIdleCompletesPomodoroAtItsRealDeadlineWithoutOvercounting() {
        var ledger = workingLedger(mode: .pomodoro, target: 600)
        XCTAssertTrue(ledger.detectIdle(at: origin.addingTimeInterval(650), idleFor: 350))
        ledger.detectReturn(at: origin.addingTimeInterval(950), idleFor: 0)
        let completed = ledger.resolveIdle(includeTime: true, resume: false, at: origin.addingTimeInterval(1000))
        XCTAssertEqual(completed?.endedAt, origin.addingTimeInterval(600))
        XCTAssertEqual(completed?.elapsed(at: origin.addingTimeInterval(2000)), 600)
        XCTAssertNil(ledger.activeSession)
        XCTAssertEqual(ledger.pomodoroProgress?.nextPhase, .shortBreak)
    }

    func testIdleDoesNotTriggerInBreaksPausedSessionsOrBeforeThreshold() {
        var ledger = workingLedger()
        XCTAssertFalse(ledger.detectIdle(at: origin.addingTimeInterval(200), idleFor: 1000))
        ledger.preferences.idleCheckEnabled = false
        XCTAssertFalse(ledger.detectIdle(at: origin.addingTimeInterval(1000), idleFor: 600))
        ledger.preferences.idleCheckEnabled = true
        ledger.activeSession?.pause(at: origin.addingTimeInterval(200))
        XCTAssertFalse(ledger.detectIdle(at: origin.addingTimeInterval(1000), idleFor: 600))
        ledger.activeSession?.resume(at: origin.addingTimeInterval(200))
        ledger.activeSession?.mode = .pomodoro
        ledger.activeSession?.pomodoroPhase = .shortBreak
        XCTAssertFalse(ledger.detectIdle(at: origin.addingTimeInterval(1000), idleFor: 600))
    }

    func testPendingReviewSurvivesRelaunchAndDoesNotIncludeTimeAfterTheCheckpoint() throws {
        var ledger = workingLedger()
        ledger.detectIdle(at: origin.addingTimeInterval(900), idleFor: 600)
        var decoded = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger))
        decoded.recoverAfterRelaunch(lastCheckpoint: origin.addingTimeInterval(1000), at: origin.addingTimeInterval(10000))
        XCTAssertEqual(decoded.idleReview?.returnedAt, origin.addingTimeInterval(1000))
        XCTAssertEqual(decoded.idleReview?.duration(at: origin.addingTimeInterval(10000)), 700)
        XCTAssertEqual(decoded.activeSession?.elapsed(at: origin.addingTimeInterval(10000)), 300)
    }

    func testIdleCanStayPausedAndBlocksCategoryChangesUntilResolved() {
        var ledger = workingLedger()
        ledger.detectIdle(at: origin.addingTimeInterval(900), idleFor: 600)
        XCTAssertNil(ledger.changeActiveCategory(to: second, at: origin.addingTimeInterval(1000)))
        XCTAssertEqual(ledger.activeSession?.categoryID, first)
        ledger.resolveIdle(includeTime: false, resume: false, at: origin.addingTimeInterval(1100))
        XCTAssertTrue(ledger.activeSession?.isPaused == true)
    }

    func testAutomaticBreakUsesDeadlineAndNeverStartsNextFocus() {
        var ledger = workingLedger(mode: .pomodoro, target: 1500)
        let completed = ledger.completeExpiredTimer(at: origin.addingTimeInterval(1600))!
        XCTAssertTrue(ledger.startAutomaticBreak(after: completed))
        XCTAssertEqual(ledger.activeSession?.startedAt, origin.addingTimeInterval(1500))
        XCTAssertEqual(ledger.activeSession?.remaining(at: origin.addingTimeInterval(1600)), 200)
        XCTAssertFalse(ledger.startAutomaticBreak(after: completed))
        let rest = ledger.completeExpiredTimer(at: origin.addingTimeInterval(2000))!
        XCTAssertFalse(ledger.startAutomaticBreak(after: rest))
        XCTAssertNil(ledger.activeSession)
        XCTAssertEqual(ledger.pomodoroProgress?.nextPhase, .focus)
        XCTAssertEqual(ledger.sessions.count, 1)
    }

    func testAutomaticLongBreakAndManualOverride() {
        var ledger = workingLedger(mode: .pomodoro, target: 1500)
        var progress = PomodoroProgress()
        progress.completedFocusCount = 3
        ledger.pomodoroProgress = progress
        let completed = ledger.completeExpiredTimer(at: origin.addingTimeInterval(1500))!
        ledger.preferences.pomodoro.autoStartBreaks = false
        XCTAssertFalse(ledger.startAutomaticBreak(after: completed))
        ledger.preferences.pomodoro.autoStartBreaks = true
        XCTAssertTrue(ledger.startAutomaticBreak(after: completed))
        XCTAssertEqual(ledger.activeSession?.pomodoroPhase, .longBreak)
        XCTAssertEqual(ledger.activeSession?.targetSeconds, 900)
    }

    func testVersion13SettingsUpgradeWithoutChangingDurations() throws {
        let json = Data(#"{"focusMinutes":40,"shortBreakMinutes":7,"longBreakMinutes":20,"roundsBeforeLongBreak":3}"#.utf8)
        let settings = try JSONDecoder().decode(PomodoroSettings.self, from: json)
        XCTAssertTrue(settings.autoStartBreaks)
        XCTAssertEqual(settings.focusMinutes, 40)
        XCTAssertEqual(settings.shortBreakMinutes, 7)
        XCTAssertEqual(settings.longBreakMinutes, 20)
        XCTAssertEqual(settings.roundsBeforeLongBreak, 3)
        let preferences = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        XCTAssertTrue(preferences.idleCheckEnabled)
        XCTAssertEqual(preferences.idleMinutes, 5)
        XCTAssertTrue(preferences.breakEdgeGlowEnabled)
        XCTAssertTrue(preferences.animateLogo)
    }
}
