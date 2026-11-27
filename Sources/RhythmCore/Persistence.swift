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
        try LedgerEnvelope(savedAt: date, ledger: ledger).write(to: url)
    }

    public func replace(with restored: LedgerEnvelope, preserving current: Ledger?) throws {
        let manager = FileManager.default
        let directory = url.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let snapshot = directory.appendingPathComponent("ledger-before-restore-\(UUID().uuidString)")
        let primary = try manager.fileExists(atPath: url.path) ? Data(contentsOf: url) : nil
        if let primary {
            try primary.write(to: snapshot.appendingPathExtension("json"), options: .atomic)
        }
        let persisted = primary.flatMap { try? JSONDecoder().decode(LedgerEnvelope.self, from: $0) }
        if let current, current != persisted?.ledger {
            try LedgerEnvelope(savedAt: restored.savedAt, ledger: current)
                .write(to: snapshot.appendingPathExtension("in-memory.json"))
        }
        try restored.write(to: url)
    }
}

extension LedgerEnvelope {
    public func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    public static func readBackup(from url: URL) throws -> LedgerEnvelope {
        let envelope = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        let ledger = envelope.ledger
        guard ledger.version == 1 else { throw BackupError.unsupportedVersion }
        let sessions = ledger.sessions + (ledger.activeSession.map { [$0] } ?? [])
        let progress = ledger.pomodoroProgress?.completedFocusCount ?? 0
        guard ledger.categories.allSatisfy({ (0...1440).contains($0.dailyGoalMinutes) }),
              ledger.tasks.allSatisfy({ (0...480).contains($0.plannedMinutes) && Self.validDate($0.day) }),
              ledger.dailyTaskSchedules.allSatisfy(\.isValidForRestore),
              Self.validDate(envelope.savedAt),
              (0..<Int.max).contains(progress),
              sessions.allSatisfy({ session in
                  (0...Double(Int.max / 2)).contains(session.targetSeconds)
                      && Self.validDate(session.startedAt)
                      && session.endedAt.map(Self.validDate) != false
                      && !session.intervals.isEmpty
                      && session.intervals.allSatisfy { Self.validDate($0.start) && $0.end.map(Self.validDate) != false }
              }),
              ledger.activeSession?.endedAt == nil,
              ledger.idleReview.map({ review in
                  review.sessionID == ledger.activeSession?.id && Self.validDate(review.startedAt)
                      && Self.validDate(review.detectedAt) && review.returnedAt.map(Self.validDate) != false
              }) != false
        else { throw BackupError.invalidData }
        return envelope
    }

    static func validDate(_ date: Date) -> Bool {
        (Date.distantPast...Date.distantFuture).contains(date)
    }
}

private enum BackupError: LocalizedError {
    case unsupportedVersion, invalidData

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return L10n.text("This backup uses an unsupported data version.")
        case .invalidData: return L10n.text("This backup contains invalid data.")
        }
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
                field(categories.first { $0.id == session.categoryID }?.name ?? L10n.text("Uncategorized")),
                field(formatter.string(from: session.startedAt)),
                field(formatter.string(from: session.endedAt ?? session.startedAt)),
                String(Int(session.elapsed(at: session.endedAt ?? session.startedAt))),
                field(session.mode == .pomodoro ? L10n.text("Pomodoro") : session.mode == .countdown ? L10n.text("Timer") : L10n.text("Stopwatch"))
            ].joined(separator: ",")
        }
        return "\u{FEFF}" + L10n.text("Task,Category,Start,End,Seconds,Mode") + "\r\n" + rows.joined(separator: "\r\n")
    }
}
