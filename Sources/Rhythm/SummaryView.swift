import SwiftUI
import RhythmCore

struct SummaryView: View {
    @EnvironmentObject var store: AppStore
    @State private var deletingSession: WorkSession?

    private var daySessions: [WorkSession] {
        guard let bounds = Calendar.current.dateInterval(of: .day, for: store.selectedDay) else { return [] }
        return (store.ledger.sessions + (store.active.map { [$0] } ?? []))
            .filter { !$0.isBreak && $0.duration(in: bounds, at: store.now) > 0 }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private var relevantCategories: [TimeCategory] {
        store.ledger.categories.filter { !$0.isArchived || store.ledger.total(on: store.selectedDay, categoryID: $0.id, at: store.now) > 0 }
    }

    private var planned: Int {
        relevantCategories.reduce(0) { $0 + store.ledger.plannedMinutes(for: $1.id, on: store.selectedDay) }
    }

    var body: some View {
        let sessions = daySessions
        VStack(spacing: 18) {
            DayNavigation()
            Button { store.page = .analytics } label: {
                HStack(spacing: 9) {
                    Image(systemName: "square.grid.3x3.fill").foregroundStyle(store.accentColor)
                    Text("Analytics").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                .cardSurface(padding: 12)
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Focus time").font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(TimeText.duration(store.totalSelectedDay)).timeDisplay(size: 27)
                        if planned > 0 {
                            Text("of " + TimeText.duration(Double(planned * 60)) + " planned")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    ZStack {
                        Circle().stroke(.primary.opacity(0.05), lineWidth: 5)
                        Circle().trim(from: 0, to: planned > 0 ? min(1, store.totalSelectedDay / Double(planned * 60)) : 0)
                            .stroke(store.accentColor, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                        if planned > 0 {
                            Text("\(Int(min(1, store.totalSelectedDay / Double(planned * 60)) * 100))%")
                                .font(.system(size: 12, weight: .medium)).monospacedDigit()
                        } else {
                            Image(systemName: "leaf").font(.system(size: 19, weight: .ultraLight)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 58, height: 58).padding(.top, 6)
                    .accessibilityLabel("Goal progress")
                }
                if store.totalSelectedDay > 0 { distributionBar }
            }
            .cardSurface(padding: 17)

            VStack(spacing: 13) {
                HStack {
                    SectionCaption(title: "CATEGORIES")
                    Button { store.showCategories = true } label: { Image(systemName: "slider.horizontal.3").font(.system(size: 11)).foregroundStyle(.tertiary) }
                        .buttonStyle(.plain).accessibilityLabel("Goals and categories")
                }
                ForEach(relevantCategories) { category in CategoryProgress(category: category, day: store.selectedDay) }
            }

            weekChart

            VStack(spacing: 11) {
                SectionCaption(title: "SESSIONS", trailing: "\(sessions.count)")
                if sessions.isEmpty {
                    EmptyNote(symbol: "clock", title: "No sessions", subtitle: "Start the timer to record time.")
                        .cardSurface(padding: 0)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                            sessionRow(session)
                            if index < sessions.count - 1 { Divider().padding(.leading, 26) }
                        }
                    }
                    .cardSurface(padding: 12)
                }
            }
        }
        .alert("Delete session?", isPresented: Binding(get: { deletingSession != nil }, set: { if !$0 { deletingSession = nil } })) {
            Button("Cancel", role: .cancel) { deletingSession = nil }
            Button("Delete", role: .destructive) { if let session = deletingSession { store.deleteSession(session.id) }; deletingSession = nil }
        } message: { Text("This removes its time from totals.") }
    }

    private var distributionBar: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(relevantCategories.filter { store.ledger.total(on: store.selectedDay, categoryID: $0.id, at: store.now) > 0 }) { category in
                    let total = store.ledger.total(on: store.selectedDay, categoryID: category.id, at: store.now)
                    category.color.tint
                        .frame(width: max(0, (geometry.size.width - CGFloat(max(0, relevantCategories.count - 1) * 2)) * total / max(1, store.totalSelectedDay)))
                        .accessibilityLabel(category.name + ": " + TimeText.duration(total))
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 6)
    }

    private var weekChart: some View {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: store.selectedDay)?.start ?? store.selectedDay
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
        let maximum = max(3600, days.map { store.ledger.total(on: $0, at: store.now) }.max() ?? 0)
        let weekTotal = days.reduce(0.0) { $0 + store.ledger.total(on: $1, at: store.now) }
        return VStack(spacing: 13) {
            SectionCaption(title: calendar.isDate(store.selectedDay, equalTo: Date(), toGranularity: .weekOfYear) ? "THIS WEEK" : "WEEK", trailing: TimeText.duration(weekTotal))
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(days, id: \.self) { day in
                    let total = store.ledger.total(on: day, at: store.now)
                    let selected = Calendar.current.isDate(day, inSameDayAs: store.selectedDay)
                    Button {
                        if day <= Calendar.current.startOfDay(for: Date()) { store.selectedDay = day }
                    } label: {
                        VStack(spacing: 7) {
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 4).fill(.primary.opacity(0.035))
                                RoundedRectangle(cornerRadius: 4).fill(store.accentColor.opacity(selected ? 1 : 0.5))
                                    .frame(height: total > 0 ? max(4, 48 * total / maximum) : 0)
                            }
                            .frame(height: 48)
                            Text(day.formatted(.dateTime.locale(Locale(identifier: "en")).weekday(.narrow)).uppercased())
                                .font(.system(size: 10, weight: selected ? .semibold : .regular))
                                .foregroundStyle(selected ? Color.primary : Color.secondary)
                        }
                    }
                    .buttonStyle(.plain).disabled(day > Calendar.current.startOfDay(for: Date()))
                    .accessibilityLabel(day.formatted(.dateTime.locale(Locale(identifier: "en")).weekday(.wide)) + ": " + TimeText.duration(total))
                }
            }
        }
        .cardSurface(padding: 13)
    }

    private func sessionRow(_ session: WorkSession) -> some View {
        let active = session.endedAt == nil
        let dayStart = Calendar.current.startOfDay(for: store.selectedDay)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
        return HStack(alignment: .center, spacing: 9) {
            RoundedRectangle(cornerRadius: 2).fill(store.ledger.category(session.categoryID)?.color.tint ?? store.accentColor).frame(width: 3, height: 29)
            VStack(alignment: .leading, spacing: 5) {
                Text(session.displayTitle).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(max(dayStart, session.startedAt).formatted(.dateTime.locale(Locale(identifier: "en")).hour().minute()) + " · " + (active ? (session.isPaused ? "paused" : "now") : min(dayEnd, session.endedAt!).formatted(.dateTime.locale(Locale(identifier: "en")).hour().minute())))
                    .font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 4)
            Text(TimeText.duration(session.duration(on: store.selectedDay, at: store.now)))
                .font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(.vertical, 9)
        .contextMenu {
            if !active {
                Button("Repeat Task", systemImage: "arrow.clockwise") {
                    guard store.active == nil else { return }
                    store.title = session.title
                    store.selectedCategoryID = session.categoryID
                    store.selectedTaskID = session.taskID
                    store.mode = session.mode
                    if session.mode == .countdown { store.minutes = max(1, min(480, Int(session.targetSeconds / 60))) }
                    store.page = .focus
                }
                .disabled(store.active != nil)
                Divider()
                Button("Delete Session…", systemImage: "trash", role: .destructive) { deletingSession = session }
            } else {
                Button("Open Timer") { store.page = .focus }
            }
        }
    }
}
