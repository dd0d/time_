import Foundation

public struct LedgerEnvelope: Codable, Sendable {
    public var savedAt: Date
    public var ledger: Ledger

    public init(savedAt: Date, ledger: Ledger) {
        self.savedAt = savedAt
        self.ledger = ledger
    }
}

public struct LedgerFile: Sendable {
    public let url: URL
    public var backupURL: URL { url.deletingPathExtension().appendingPathExtension("backup.json") }

    public init(url: URL) { self.url = url }

    public func load() throws -> LedgerEnvelope? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(LedgerEnvelope.self, from: Data(contentsOf: url))
    }

    public func loadBackup() throws -> LedgerEnvelope? {
        guard FileManager.default.fileExists(atPath: backupURL.path) else { return nil }
        return try JSONDecoder().decode(LedgerEnvelope.self, from: Data(contentsOf: backupURL))
    }

    public func save(_ ledger: Ledger, at date: Date) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Only a valid previous file may replace the recovery copy.
        if let previous = try? Data(contentsOf: url), (try? JSONDecoder().decode(LedgerEnvelope.self, from: previous)) != nil {
            try previous.write(to: backupURL, options: .atomic)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(LedgerEnvelope(savedAt: date, ledger: ledger))
        try data.write(to: url, options: .atomic)
    }
}

public enum CSVExport {
    public static func field(_ value: String) -> String {
        // Spreadsheet applications must treat user-authored titles as text.
        let safe = ["=", "+", "-", "@", "\t", "\r"].contains(where: value.hasPrefix) ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    public static func sessions(_ sessions: [WorkSession], categories: [TimeCategory]) -> String {
        let formatter = ISO8601DateFormatter()
        let rows = sessions.filter { !$0.isBreak }.map { session -> String in
            [
                field(session.displayTitle),
                field(categories.first { $0.id == session.categoryID }?.name ?? "Uncategorized"),
                field(formatter.string(from: session.startedAt)),
                field(formatter.string(from: session.endedAt ?? session.startedAt)),
                String(Int(session.elapsed(at: session.endedAt ?? session.startedAt))),
                field(session.mode == .pomodoro ? "Pomodoro" : session.mode == .countdown ? "Timer" : "Stopwatch")
            ].joined(separator: ",")
        }
        return "\u{FEFF}Task,Category,Start,End,Seconds,Mode\r\n" + rows.joined(separator: "\r\n")
    }
}
