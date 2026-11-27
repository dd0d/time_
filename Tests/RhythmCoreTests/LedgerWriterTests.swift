import XCTest
@testable import RhythmCore

final class LedgerWriterTests: XCTestCase {
    func testConcurrentEnqueuesCannotOvertakeFinalSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = LedgerFile(url: directory.appendingPathComponent("ledger.json"))
        let writer = LedgerWriter(file: file)
        let initial = Ledger()
        DispatchQueue.concurrentPerform(iterations: 100) { index in
            var snapshot = initial
            snapshot.preferences.defaultMinutes = index + 1
            writer.save(snapshot, at: Date()) { _ in }
        }
        var final = initial
        final.preferences.defaultMinutes = 480
        writer.save(final, at: Date(timeIntervalSince1970: 1234)) { _ in }
        writer.flush()
        XCTAssertEqual(try file.load()?.ledger, final)
        XCTAssertEqual(try file.load()?.savedAt, Date(timeIntervalSince1970: 1234))
    }

    func testRapidSnapshotsFlushLatestVersionAndValidRecoveryCopy() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = LedgerFile(url: directory.appendingPathComponent("ledger.json"))
        var ledger = Ledger()
        try file.save(ledger, at: Date(timeIntervalSince1970: 1))
        let writer = LedgerWriter(file: file)
        for index in 0..<200 {
            ledger.preferences.defaultMinutes = index + 1
            writer.save(ledger, at: Date(timeIntervalSince1970: Double(index + 2))) { _ in }
        }
        writer.flush()
        XCTAssertEqual(try file.load()?.ledger, ledger)
        XCTAssertEqual(try file.load()?.savedAt, Date(timeIntervalSince1970: 201))
        XCTAssertNotNil(try file.loadBackup())
    }

    func testWriteFailureIsReportedAndLaterRetrySucceeds() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("blocked")
        try Data("not a directory".utf8).write(to: directory)
        let file = LedgerFile(url: directory.appendingPathComponent("ledger.json"))
        let writer = LedgerWriter(file: file)
        let failure = expectation(description: "Failure reported")
        writer.save(Ledger(), at: Date()) { result in
            if case .failure = result { failure.fulfill() }
        }
        writer.flush()
        wait(for: [failure], timeout: 1)
        try FileManager.default.removeItem(at: directory)
        let success = expectation(description: "Retry succeeded")
        writer.save(Ledger(), at: Date()) { result in
            if case .success = result { success.fulfill() }
        }
        writer.flush()
        wait(for: [success], timeout: 1)
        XCTAssertNotNil(try file.load())
    }
}
