import Foundation
import Darwin

// Compiled with RhythmCore's sources and -O; no user data or UI is used.
@main
enum AuditBenchmark {
    static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    static func main() throws {
        let count = 10_000
        let now = Date(timeIntervalSince1970: 1_798_617_600)
        var ledger = Ledger()
        for index in 0..<count {
            let start = now.addingTimeInterval(-Double(index / 12) * 86400 - Double(index % 12) * 3600 - 3600)
            var session = WorkSession(title: "Аудит \(index)", categoryID: ledger.categories[index % 3].id,
                                      mode: .stopwatch, startedAt: start)
            session.pause(at: start.addingTimeInterval(1200))
            session.resume(at: start.addingTimeInterval(1500))
            session.finish(at: start.addingTimeInterval(2700))
            ledger.sessions.append(session)
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("time-audit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = LedgerFile(url: directory.appendingPathComponent("ledger.json"))
        var results: [String: Any] = ["sessions": count, "system": ProcessInfo.processInfo.operatingSystemVersionString]
        var checksum = 0.0
        func measure(_ name: String, repeats: Int, action: () throws -> Void) rethrows {
            var samples: [Double] = []
            for _ in 0..<repeats {
                let start = CFAbsoluteTimeGetCurrent()
                try autoreleasepool { try action() }
                samples.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
            }
            samples.sort()
            results[name + "_median_ms"] = samples[samples.count / 2]
        }
        measure("day_total", repeats: 30) { checksum += ledger.total(on: now, at: now) }
        measure("week_totals", repeats: 15) {
            for day in 0..<7 { checksum += ledger.total(on: now.addingTimeInterval(Double(-day) * 86400), at: now) }
        }
        measure("analytics_year", repeats: 10) {
            checksum += AnalyticsSnapshot(ledger: ledger, endingOn: now, periodDays: 365, at: now).totalSeconds
        }
        try measure("save_with_backup", repeats: 5) { try file.save(ledger, at: now) }
        try measure("load", repeats: 5) { checksum += Double(try file.load()!.ledger.sessions.count) }
        let writer = LedgerWriter(file: file)
        measure("enqueue_save", repeats: 30) { writer.save(ledger, at: now) { _ in } }
        writer.flush()
        results["json_bytes"] = try Data(contentsOf: file.url).count
        var memory: [UInt64] = []
        for _ in 0..<6 {
            for _ in 0..<50 {
                autoreleasepool {
                    checksum += AnalyticsSnapshot(ledger: ledger, endingOn: now, periodDays: 365, at: now).totalSeconds
                }
            }
            memory.append(footprint())
        }
        results["footprint_after_each_50_reports_bytes"] = memory
        results["checksum"] = checksum
        let output = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: output, as: UTF8.self))
    }
}
