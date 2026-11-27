import XCTest
import RhythmCore
@testable import Rhythm

final class DailyTaskTests: XCTestCase {
    @MainActor
    func testTaskWithoutTimeGoalCanBeCompletedAndStartsAsStopwatchWhenRequested() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("ledger.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = AppStore(dataURL: url, idleTimeProvider: { 0 })
        store.ledger.preferences.notificationsEnabled = false
        store.addTask(title: "Прочитать статью", categoryID: store.categories[0].id, minutes: 0, day: store.selectedDay, isDaily: true)
        let task = try XCTUnwrap(store.dayTasks.first)
        XCTAssertEqual(task.plannedMinutes, 0)
        XCTAssertEqual(store.ledger.plannedMinutes(for: task.categoryID, on: store.selectedDay), 0)
        store.toggleTask(task.id)
        XCTAssertNotNil(store.dayTasks[0].completedAt)
        XCTAssertNil(store.active, "Completing a task never requires running a timer")
        store.toggleTask(task.id)
        store.mode = .countdown
        store.useTask(store.dayTasks[0], startImmediately: true)
        XCTAssertEqual(store.active?.mode, .stopwatch)
        XCTAssertEqual(store.active?.targetSeconds, 0)
        XCTAssertEqual(store.active?.taskID, task.id)
        store.prepareToQuit()
    }

    @MainActor
    func testDailyAppearsInTomorrowPlanAndCompletionRemainsIndependent() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("ledger.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = AppStore(dataURL: url, idleTimeProvider: { 0 })
        store.addTask(title: "SQL", categoryID: store.categories[0].id, minutes: 60, day: store.selectedDay, isDaily: true)
        let todayTask = try XCTUnwrap(store.dayTasks.first)
        store.toggleTask(todayTask.id)
        store.changeDay(1, allowsFuture: true)
        let tomorrowTask = try XCTUnwrap(store.dayTasks.first)
        XCTAssertNil(tomorrowTask.completedAt)
        XCTAssertNotEqual(todayTask.id, tomorrowTask.id)
        store.changeDay(-1, allowsFuture: true)
        XCTAssertNotNil(store.dayTasks[0].completedAt)
        store.prepareToQuit()
        let restored = AppStore(dataURL: url, idleTimeProvider: { 0 })
        restored.changeDay(1, allowsFuture: true)
        XCTAssertEqual(restored.dayTasks.first?.id, tomorrowTask.id)
        restored.prepareToQuit()
    }

    @MainActor
    func testDayChangesWithoutRunningTimerAndDoesNotRegenerateCompletedOneTime() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("ledger.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = AppStore(dataURL: url, idleTimeProvider: { 0 })
        store.addTask(title: "Один раз", categoryID: store.categories[0].id, minutes: 15, day: store.selectedDay)
        store.toggleTask(store.dayTasks[0].id)
        store.addTask(title: "Ежедневная", categoryID: store.categories[0].id, minutes: 30, day: store.selectedDay, isDaily: true)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: store.selectedDay)!
        store.synchronizeTaskDay(at: tomorrow)
        XCTAssertTrue(Calendar.current.isDate(store.selectedDay, inSameDayAs: tomorrow))
        XCTAssertEqual(store.dayTasks.map(\.title), ["Ежедневная"])
        XCTAssertNil(store.dayTasks[0].completedAt)
        XCTAssertNil(store.ticker)
        store.prepareToQuit()
    }

    @MainActor
    func testLaunchCreatesOnlyCurrentDailyOccurrenceAfterAbsence() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("ledger.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var ledger = Ledger()
        let oldDay = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        ledger.addPlanTask(PlanTask(title: "Учёба", categoryID: ledger.categories[0].id, plannedMinutes: 25, day: oldDay), repeatsDaily: true)
        ledger.tasks[0].completedAt = oldDay
        try LedgerFile(url: url).save(ledger, at: oldDay)
        let store = AppStore(dataURL: url, idleTimeProvider: { 0 })
        XCTAssertEqual(store.ledger.tasks.count, 2)
        XCTAssertEqual(store.dayTasks.count, 1)
        XCTAssertNil(store.dayTasks[0].completedAt)
        store.refresh()
        store.refresh()
        XCTAssertEqual(store.ledger.tasks.count, 2)
        store.prepareToQuit()
    }
}
