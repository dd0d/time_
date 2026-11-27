import Foundation

public struct ActivityDay: Identifiable, Equatable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let seconds: TimeInterval
}

public struct CategoryActivity: Identifiable, Equatable, Sendable {
    public var id: UUID { categoryID }
    public let categoryID: UUID
    public let seconds: TimeInterval
}

/// A snapshot is calculated when analytics opens or its period/data changes, never every tick.
public struct AnalyticsSnapshot: Sendable {
    public let days: [ActivityDay]
    public let periodDays: Int
    public let totalSeconds: TimeInterval
    public let previousSeconds: TimeInterval
    public let activeDays: Int
    public let sessionCount: Int
    public let completedPomodoros: Int
    public let longestSession: TimeInterval
    public let currentStreak: Int
    public let bestStreak: Int
    public let categories: [CategoryActivity]
    /// Monday through Sunday, averaged across occurrences in the selected period.
    public let weekdayAverages: [TimeInterval]

    public var averageDay: TimeInterval { totalSeconds / Double(periodDays) }
    public var averageSession: TimeInterval { sessionCount > 0 ? totalSeconds / Double(sessionCount) : 0 }

    public init(ledger: Ledger, endingOn date: Date, periodDays requestedDays: Int = 30, at now: Date, calendar: Calendar = .current) {
        periodDays = max(1, min(365, requestedDays))
        let lastDay = calendar.startOfDay(for: min(date, now))
        let end = min(now, calendar.date(byAdding: .day, value: 1, to: lastDay)!)
        let periodStart = calendar.date(byAdding: .day, value: 1 - periodDays, to: lastDay)!
        let previousStart = calendar.date(byAdding: .day, value: -periodDays, to: periodStart)!
        let heatmapStart = calendar.date(byAdding: .day, value: -364, to: lastDay)!
        let historyStart = min(previousStart, heatmapStart)
        var daily: [Date: TimeInterval] = [:]
        var byCategory: [UUID: TimeInterval] = [:]
        var total = 0.0, previous = 0.0, longest = 0.0
        var count = 0, pomodoros = 0

        for session in ledger.sessions + (ledger.activeSession.map { [$0] } ?? []) where !session.isBreak {
            var inPeriod = 0.0
            for interval in session.intervals {
                let start = max(historyStart, interval.start)
                let stop = min(end, interval.end ?? session.endedAt ?? now)
                guard start < stop else { continue }
                inPeriod += max(0, stop.timeIntervalSince(max(start, periodStart)))
                previous += max(0, min(stop, periodStart).timeIntervalSince(max(start, previousStart)))
                var cursor = start
                while cursor < stop {
                    let day = calendar.startOfDay(for: cursor)
                    let next = calendar.date(byAdding: .day, value: 1, to: day)!
                    let segmentEnd = min(next, stop)
                    daily[day, default: 0] += segmentEnd.timeIntervalSince(cursor)
                    cursor = segmentEnd
                }
            }
            if inPeriod > 0 {
                count += 1
                total += inPeriod
                longest = max(longest, inPeriod)
                byCategory[session.categoryID, default: 0] += inPeriod
            }
            if session.mode == .pomodoro, session.pomodoroPhase == .focus,
               let ended = session.endedAt, ended >= periodStart, ended <= end,
               session.targetSeconds > 0, session.elapsed(at: ended) >= session.targetSeconds {
                pomodoros += 1
            }
        }

        days = (0..<365).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: heatmapStart)!
            return ActivityDay(date: day, seconds: daily[day, default: 0])
        }
        var weekdayTotals = Array(repeating: 0.0, count: 7)
        var weekdayCounts = Array(repeating: 0, count: 7)
        var activeCount = 0
        for offset in 0..<periodDays {
            let day = calendar.date(byAdding: .day, value: offset, to: periodStart)!
            let seconds = daily[day, default: 0]
            if seconds > 0 { activeCount += 1 }
            let weekday = (calendar.component(.weekday, from: day) + 5) % 7
            weekdayTotals[weekday] += seconds
            weekdayCounts[weekday] += 1
        }
        weekdayAverages = (0..<7).map { weekdayCounts[$0] > 0 ? weekdayTotals[$0] / Double(weekdayCounts[$0]) : 0 }

        var best = 0, run = 0
        for day in days {
            run = day.seconds > 0 ? run + 1 : 0
            best = max(best, run)
        }
        var streak = 0
        // Today's unfinished day does not break a series that ended yesterday.
        let streakDays = days.last?.seconds == 0 && calendar.isDate(lastDay, inSameDayAs: now) ? Array(days.dropLast()) : days
        for day in streakDays.reversed() {
            guard day.seconds > 0 else { break }
            streak += 1
        }
        totalSeconds = total
        previousSeconds = previous
        activeDays = activeCount
        sessionCount = count
        completedPomodoros = pomodoros
        longestSession = longest
        currentStreak = streak
        bestStreak = best
        categories = byCategory.map { CategoryActivity(categoryID: $0.key, seconds: $0.value) }.sorted { $0.seconds > $1.seconds }
    }
}
