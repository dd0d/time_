import XCTest
import RhythmCore
@testable import Rhythm

final class QuickStartTests: XCTestCase {
    @MainActor
    func testCircleStartsUnnamedFocusAndPausesWithoutChangingCompactPage() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(dataURL: directory.appendingPathComponent("ledger.json"), idleTimeProvider: { 0 })
        store.ledger.preferences.notificationsEnabled = false
        XCTAssertTrue(store.canStart)
        store.quickToggle()
        XCTAssertEqual(store.active?.title, "")
        XCTAssertEqual(store.active?.displayTitle, "Focus")
        XCTAssertEqual(store.page, .focus)
        store.quickToggle()
        XCTAssertTrue(store.active?.isPaused == true)
        store.quickToggle()
        XCTAssertTrue(store.active?.isRunning == true)
        store.finish()
        XCTAssertEqual(store.ledger.sessions.count, 1)
    }

    @MainActor
    func testUnnamedPomodoroOffersBreakWithoutAutoStartingIt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(dataURL: directory.appendingPathComponent("ledger.json"), idleTimeProvider: { 0 })
        store.ledger.preferences.notificationsEnabled = false
        store.ledger.preferences.pomodoro.autoStartBreaks = false
        store.mode = .pomodoro
        store.start()
        XCTAssertEqual(store.active?.pomodoroPhase, .focus)
        XCTAssertEqual(store.active?.targetSeconds, 1500)
        store.ledger.activeSession?.intervals[0].start = Date().addingTimeInterval(-1501)
        store.ledger.activeSession?.startedAt = Date().addingTimeInterval(-1501)
        store.refresh()
        XCTAssertNil(store.active)
        XCTAssertEqual(store.pomodoroPhase, .shortBreak)
        XCTAssertEqual(store.ledger.sessions.count, 1)
        store.quickToggle()
        XCTAssertTrue(store.active?.isBreak == true)
        XCTAssertEqual(store.active?.targetSeconds, 300)
        store.skipPomodoroBreak()
        XCTAssertNil(store.active)
        XCTAssertEqual(store.pomodoroPhase, .focus)
        XCTAssertEqual(store.ledger.sessions.count, 1)
    }

    @MainActor
    func testAutomaticPomodoroStartsRestButWaitsForNextFocus() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(dataURL: directory.appendingPathComponent("ledger.json"), idleTimeProvider: { 0 })
        store.ledger.preferences.notificationsEnabled = false
        store.mode = .pomodoro
        store.start()
        let start = Date().addingTimeInterval(-1501)
        store.ledger.activeSession?.startedAt = start
        store.ledger.activeSession?.intervals[0].start = start
        store.refresh()
        XCTAssertTrue(store.active?.isBreak == true)
        XCTAssertEqual(store.active?.targetSeconds, 300)
        XCTAssertEqual(store.ledger.sessions.count, 1)
        let restStart = Date().addingTimeInterval(-301)
        store.ledger.activeSession?.startedAt = restStart
        store.ledger.activeSession?.intervals[0].start = restStart
        store.refresh()
        XCTAssertNil(store.active)
        XCTAssertEqual(store.pomodoroPhase, .focus)
        XCTAssertTrue(store.lastCompleted?.isBreak == true)
        XCTAssertEqual(store.ledger.sessions.count, 1)
    }

    @MainActor
    func testIdleReturnAndDecisionResumeWithoutOpeningAnotherPage() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var idle = 0.0
        let store = AppStore(dataURL: directory.appendingPathComponent("ledger.json"), idleTimeProvider: { idle })
        store.ledger.preferences.notificationsEnabled = false
        store.mode = .stopwatch
        store.start()
        let start = Date().addingTimeInterval(-900)
        store.ledger.activeSession?.startedAt = start
        store.ledger.activeSession?.intervals[0].start = start
        idle = 600
        store.refresh()
        XCTAssertNotNil(store.pendingIdle)
        XCTAssertTrue(store.active?.isPaused == true)
        XCTAssertEqual(store.page, .focus)
        idle = 0
        store.refresh()
        XCTAssertNotNil(store.pendingIdle?.returnedAt)
        store.presentIdleReview()
        XCTAssertEqual(store.page, .idleReview)
        store.resolveIdle(includeTime: false, resume: true)
        XCTAssertNil(store.pendingIdle)
        XCTAssertTrue(store.active?.isRunning == true)
        XCTAssertEqual(store.page, .focus)
        XCTAssertEqual(store.active!.elapsed(at: Date()), 300, accuracy: 1)
        store.finish()
    }
}
