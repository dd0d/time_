import Foundation

/// Serial, coalescing disk writes. Each snapshot keeps its own checkpoint date.
/// flush() is used on termination so the final paused state is durable.
public final class LedgerWriter: @unchecked Sendable {
    private struct Pending {
        let ledger: Ledger
        let date: Date
        let completion: @Sendable (Result<Void, Error>) -> Void
    }
    private let file: LedgerFile
    private let queue = DispatchQueue(label: "software.rhythm.persistence", qos: .utility)
    private let lock = NSLock()
    private var pending: Pending?
    private var working = false

    public init(file: LedgerFile) { self.file = file }

    public func save(_ ledger: Ledger, at date: Date, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        lock.lock()
        pending = Pending(ledger: ledger, date: date, completion: completion)
        let start = !working
        working = true
        if start { queue.async { self.drain() } }
        lock.unlock()
    }

    public func flush() { queue.sync {} }

    private func drain() {
        while true {
            lock.lock()
            guard let next = pending else {
                working = false
                lock.unlock()
                return
            }
            pending = nil
            lock.unlock()
            let result = Result { try file.save(next.ledger, at: next.date) }
            next.completion(result)
        }
    }
}
