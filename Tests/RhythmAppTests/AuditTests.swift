import XCTest
import RhythmCore
@testable import Rhythm

final class AuditTests: XCTestCase {
    @MainActor
    func testHiddenOrStaticUIStillExpiresTimerWithoutPublishingEverySecond() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(dataURL: directory.appendingPathComponent("ledger.json"), idleTimeProvider: { 0 })
        store.ledger.preferences.notificationsEnabled = false
        store.mode = .countdown
        store.start()
        var clock = store.now
        store.tick()
        XCTAssertEqual(store.now, clock)
        store.isPanelVisible = true
        store.page = .analytics
        clock = store.now
        var changes = 0
        let observation = store.objectWillChange.sink { changes += 1 }
        defer { observation.cancel() }
        store.tick()
        XCTAssertEqual(store.now, clock)
        XCTAssertEqual(changes, 0, "A quiet tick must not rebuild static pages via an unchanged ledger")
        store.ledger.activeSession?.startedAt = Date().addingTimeInterval(-10)
        store.ledger.activeSession?.intervals[0].start = Date().addingTimeInterval(-10)
        store.ledger.activeSession?.targetSeconds = 1
        store.tick()
        XCTAssertNil(store.active)
        XCTAssertEqual(store.ledger.sessions.count, 1)
        XCTAssertEqual(store.ledger.sessions[0].elapsed(at: Date()), 1, accuracy: 0.001)
        store.prepareToQuit()
    }

    @MainActor
    func testFuturePlanIsReachableAndHistoryReturnsToToday() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(dataURL: directory.appendingPathComponent("ledger.json"))
        let today = Calendar.current.startOfDay(for: Date())
        store.page = .plan
        store.changeDay(1, allowsFuture: true)
        XCTAssertTrue(store.selectedDay > today)
        store.addTask(title: "Завтра", categoryID: store.categories[0].id, minutes: 25, day: store.selectedDay)
        XCTAssertEqual(store.dayTasks.count, 1)
        store.page = .summary
        XCTAssertEqual(store.selectedDay, today)
        store.changeDay(1)
        XCTAssertEqual(store.selectedDay, today)
        store.prepareToQuit()
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor
    func testMissingPrimaryRecoversBackupAndPreservesHistory() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = LedgerFile(url: directory.appendingPathComponent("ledger.json"))
        var ledger = Ledger()
        let start = Date().addingTimeInterval(-100)
        var session = WorkSession(title: "Сохранённая работа", categoryID: ledger.categories[0].id, mode: .stopwatch, startedAt: start)
        session.finish(at: start.addingTimeInterval(60))
        ledger.sessions.append(session)
        try file.save(ledger, at: Date())
        try file.save(ledger, at: Date())
        try FileManager.default.removeItem(at: file.url)
        let store = AppStore(dataURL: file.url)
        XCTAssertEqual(store.ledger.sessions, [session])
        XCTAssertNotNil(store.storageError)
        store.prepareToQuit()
        XCTAssertEqual(try file.load()?.ledger.sessions, [session])
        XCTAssertEqual(try file.loadBackup()?.ledger.sessions, [session])
    }

    @MainActor
    func testUnreadableStorageRejectsEditsAndRestoresFromExport() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = LedgerFile(url: directory.appendingPathComponent("ledger.json"))
        let invalid = Data("unreadable".utf8)
        try invalid.write(to: file.url)
        let store = AppStore(dataURL: file.url)
        XCTAssertTrue(store.isStorageReadOnly)
        XCTAssertFalse(store.canStart)
        store.addTask(title: "Cannot be saved", categoryID: store.categories[0].id, minutes: 15, day: Date())
        store.addCategory(name: "Cannot be saved", color: .mint, goal: 0)
        XCTAssertTrue(store.ledger.tasks.isEmpty)
        XCTAssertEqual(store.categories.count, 3)
        XCTAssertThrowsError(try store.restoreBackup(from: file.url))
        XCTAssertEqual(try Data(contentsOf: file.url), invalid)
        XCTAssertTrue(store.isStorageReadOnly)

        let date = Date().addingTimeInterval(-60)
        var ledger = Ledger()
        ledger.activeSession = WorkSession(title: "Reading", categoryID: ledger.categories[0].id, mode: .stopwatch, startedAt: date.addingTimeInterval(-30))
        let export = directory.appendingPathComponent("export.json")
        try LedgerEnvelope(savedAt: date, ledger: ledger).write(to: export)
        try store.restoreBackup(from: export)
        XCTAssertFalse(store.isStorageReadOnly)
        XCTAssertNil(store.storageError)
        XCTAssertTrue(store.active?.isPaused == true)
        XCTAssertEqual(store.active?.elapsed(at: Date()), 30)
        XCTAssertEqual(try file.load()?.ledger, store.ledger)
        let snapshot = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.hasPrefix("ledger-before-restore-") })
        XCTAssertEqual(try Data(contentsOf: snapshot), invalid)
    }

    @MainActor
    func testRestorePreservesTheCurrentLedgerAndRejectsInvalidValues() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = LedgerFile(url: directory.appendingPathComponent("ledger.json"))
        let store = AppStore(dataURL: file.url)
        store.addTask(title: "Latest task", categoryID: store.categories[0].id, minutes: 15, day: Date())
        let previous = store.ledger
        let export = directory.appendingPathComponent("export.json")
        var imported = Ledger()
        imported.addPlanTask(PlanTask(title: "Imported task", categoryID: imported.categories[0].id, plannedMinutes: Int.max, day: Date()))
        try LedgerEnvelope(savedAt: Date(), ledger: imported).write(to: export)
        XCTAssertThrowsError(try store.restoreBackup(from: export))
        XCTAssertEqual(store.ledger, previous)

        imported.tasks[0].plannedMinutes = 20
        try LedgerEnvelope(savedAt: Date(), ledger: imported).write(to: export)
        try store.restoreBackup(from: export)
        store.prepareToQuit()
        XCTAssertEqual(try file.load()?.ledger, imported)
        let snapshot = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.hasPrefix("ledger-before-restore-") })
        XCTAssertEqual(try LedgerFile(url: snapshot).load()?.ledger, previous)
    }

    @MainActor
    func testCategoryChangeCannotChargeTimeToPreviouslySelectedTask() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(dataURL: directory.appendingPathComponent("ledger.json"), idleTimeProvider: { 0 })
        store.ledger.preferences.notificationsEnabled = false
        store.addTask(title: "SQL", categoryID: store.categories[0].id, minutes: 25, day: Date())
        store.useTask(store.ledger.tasks[0])
        store.selectedCategoryID = store.categories[1].id
        store.start()
        XCTAssertNil(store.active?.taskID)
        XCTAssertEqual(store.active?.categoryID, store.categories[1].id)
        store.prepareToQuit()
    }

    @MainActor
    func testExtremeTypedDurationCannotOverflowCompactClock() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(dataURL: directory.appendingPathComponent("ledger.json"))
        store.mode = .countdown
        store.minutes = Int.max
        XCTAssertEqual(store.idleSeconds, 480 * 60)
        store.minutes = Int.min
        XCTAssertEqual(store.idleSeconds, 60)
        store.prepareToQuit()
    }

    @MainActor
    func testRepeatedStoreLifetimesReleaseOwnerAndInvalidateScheduledTimer() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for index in 0..<30 {
            weak var owner: AppStore?
            var timer: Timer?
            autoreleasepool {
                var store: AppStore? = AppStore(dataURL: directory.appendingPathComponent("\(index).json"), idleTimeProvider: { 0 })
                owner = store
                store!.ledger.preferences.notificationsEnabled = false
                store!.start()
                timer = store!.ticker
                XCTAssertTrue(timer?.isValid == true)
                store!.showGlowPreview()
                store = nil
            }
            XCTAssertNil(owner)
            XCTAssertFalse(timer?.isValid ?? true)
        }
        // Let scheduled completion tasks drain; their captures must remain weak.
        try await Task.sleep(for: .milliseconds(100))
    }

    @MainActor
    func testQuitFlushesFinalPausedStateAfterManyQuickEdits() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = LedgerFile(url: directory.appendingPathComponent("ledger.json"))
        let store = AppStore(dataURL: file.url, idleTimeProvider: { 0 })
        store.ledger.preferences.notificationsEnabled = false
        store.mode = .stopwatch
        store.start()
        for index in 0..<100 {
            store.updateSessionDetails(title: "Правка \(index)", categoryID: store.currentCategoryID)
        }
        store.prepareToQuit()
        let saved = try XCTUnwrap(file.load())
        XCTAssertEqual(saved.ledger.activeSession?.title, "Правка 99")
        XCTAssertTrue(saved.ledger.activeSession?.isPaused == true)
        XCTAssertEqual(saved.ledger, store.ledger)
    }
}
