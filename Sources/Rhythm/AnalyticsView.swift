import SwiftUI
import RhythmCore

struct AnalyticsView: View {
    @EnvironmentObject var store: AppStore
    @State private var period = 30
    @State private var snapshot: AnalyticsSnapshot?
    @State private var selectedActivity: ActivityDay?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("Statistics")).font(AppTypography.pageTitle)
                    Text(L10n.text("Through ") + store.selectedDay.formatted(.dateTime.locale(L10n.locale).day().month(.wide).year()))
                        .font(AppTypography.detail).foregroundStyle(.secondary)
                }
                Spacer()
                QuietIconButton(symbol: "arrow.clockwise", help: L10n.text("Refresh analytics")) { rebuild() }
            }
            if let report = snapshot {
                heatmap(report)
                AppSegments(selection: $period, options: [7, 30, 90, 365], title: { $0 == 365 ? L10n.text("Year") : L10n.text("\($0) days") }).accessibilityLabel(L10n.text("Analytics period"))
                VStack(alignment: .leading, spacing: 7) {
                    Text(L10n.text("FOCUS OVER \(period) DAYS")).font(AppTypography.section).foregroundStyle(.secondary)
                    Text(TimeText.duration(report.totalSeconds)).timeDisplay(size: AppTypography.totalSize)
                    Text(comparison(report)).font(AppTypography.detail).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading).cardSurface(padding: 16)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    metric(L10n.text("Active days"), value: "\(report.activeDays) / \(period)")
                    metric(L10n.text("Daily average"), value: TimeText.duration(report.averageDay))
                    metric(L10n.text("Average session"), value: TimeText.duration(report.averageSession))
                    metric(L10n.text("Longest session"), value: TimeText.duration(report.longestSession))
                    metric(L10n.text("Completed Pomodoros"), value: "\(report.completedPomodoros)")
                    metric(L10n.text("Current streak"), value: "\(report.currentStreak)")
                }
                Text(L10n.text("Longest streak: \(report.bestStreak) days · Sessions: \(report.sessionCount)"))
                    .font(AppTypography.small).foregroundStyle(.secondary)
                categoryRanking(report)
                weekdays(report)
            }
        }
        .onAppear { rebuild() }
        .onChange(of: period) { _, _ in rebuild() }
        .onChange(of: store.selectedDay) { _, _ in rebuild() }
        .onChange(of: store.ledger.sessions) { _, _ in rebuild() }
        .onChange(of: store.active) { _, _ in rebuild() }
    }

    private func rebuild() {
        snapshot = AnalyticsSnapshot(ledger: store.ledger, endingOn: store.selectedDay, periodDays: period, at: Date())
    }

    private func comparison(_ report: AnalyticsSnapshot) -> String {
        guard report.previousSeconds > 0 else {
            return report.totalSeconds > 0 ? L10n.text("No sessions in the previous period") : L10n.text("No sessions in this period")
        }
        let change = Int(((report.totalSeconds / report.previousSeconds - 1) * 100).rounded())
        return L10n.text("\(change > 0 ? "+" : "")\(change)% vs. the previous \(period) days")
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(AppTypography.detail).foregroundStyle(.secondary)
            Text(value).timeDisplay(size: AppTypography.metricSize).lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading).cardSurface(padding: 12)
    }

    private func heatmap(_ report: AnalyticsSnapshot) -> some View {
        let weeks = heatmapWeeks(report.days)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.text("PAST YEAR")).font(AppTypography.section).foregroundStyle(.secondary)
                Spacer()
                Text(L10n.text("\(report.days.filter { $0.seconds > 0 }.count) days")).font(AppTypography.small).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 5) {
                VStack(spacing: 3) {
                    Color.clear.frame(height: 10)
                    ForEach(0..<7) { row in
                        Text(row == 0 ? L10n.text("Mon") : row == 2 ? L10n.text("Wed") : row == 4 ? L10n.text("Fri") : "")
                            .font(.system(size: 8)).foregroundStyle(.tertiary).frame(width: 16, height: 8)
                    }
                }.frame(width: 16)
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 3) {
                            ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                                VStack(spacing: 3) {
                                    Text(monthLabel(week)).font(.system(size: 7)).foregroundStyle(.secondary)
                                        .fixedSize().frame(width: 8, height: 10, alignment: .leading)
                                    ForEach(0..<7) { row in
                                        if let day = week[row] {
                                            Button { selectedActivity = day } label: {
                                                RoundedRectangle(cornerRadius: 2).fill(activityColor(day.seconds))
                                                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(selectedActivity?.date == day.date ? Color.primary.opacity(0.7) : .clear, lineWidth: 1))
                                                    .frame(width: 8, height: 8)
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel(day.date.formatted(.dateTime.locale(L10n.locale).day().month().year()) + ": " + TimeText.duration(day.seconds))
                                        } else { Color.clear.frame(width: 8, height: 8) }
                                    }
                                }.id(index)
                            }
                        }
                    }.scrollIndicators(.hidden)
                        .onAppear { proxy.scrollTo(weeks.count - 1, anchor: .trailing) }
                }
            }.frame(height: 88)
            HStack(spacing: 4) {
                Text(L10n.text("Less")).font(.system(size: 8)).foregroundStyle(.tertiary)
                ForEach([0.0, 300, 1200, 2400, 5400], id: \.self) { seconds in
                    RoundedRectangle(cornerRadius: 2).fill(activityColor(seconds)).frame(width: 7, height: 7)
                }
                Text(L10n.text("More")).font(.system(size: 8)).foregroundStyle(.tertiary)
                Spacer()
            }
            if let selectedActivity {
                HStack(spacing: 6) {
                    Text(selectedActivity.date.formatted(.dateTime.locale(L10n.locale).day().month()) + " · " + TimeText.duration(selectedActivity.seconds))
                        .font(AppTypography.small).foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.text("View Day")) {
                        store.selectedDay = selectedActivity.date
                        store.page = .summary
                    }.buttonStyle(.plain).font(AppTypography.small).foregroundStyle(store.accentColor)
                }
            } else {
                Text(L10n.text("Select a day to see its total.")).font(AppTypography.small).foregroundStyle(.secondary)
            }
        }.cardSurface(padding: 12)
    }

    private func heatmapWeeks(_ days: [ActivityDay]) -> [[ActivityDay?]] {
        guard let first = days.first else { return [] }
        let leading = (Calendar.current.component(.weekday, from: first.date) + 5) % 7
        var padded = Array<ActivityDay?>(repeating: nil, count: leading) + days.map(Optional.some)
        while padded.count % 7 != 0 { padded.append(nil) }
        return stride(from: 0, to: padded.count, by: 7).map { Array(padded[$0..<($0 + 7)]) }
    }

    private func monthLabel(_ week: [ActivityDay?]) -> String {
        guard let day = week.compactMap({ $0 }).first(where: { Calendar.current.component(.day, from: $0.date) == 1 }) else { return "" }
        return day.date.formatted(.dateTime.locale(L10n.locale).month(.abbreviated))
    }

    private func activityColor(_ seconds: TimeInterval) -> Color {
        guard seconds > 0 else { return .primary.opacity(0.065) }
        return store.accentColor.opacity(seconds < 900 ? 0.25 : seconds < 1800 ? 0.45 : seconds < 3600 ? 0.7 : 1)
    }

    private func categoryRanking(_ report: AnalyticsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionCaption(title: L10n.text("BY CATEGORY"))
            if report.categories.isEmpty {
                Text(L10n.text("No tracked time in this period.")).font(AppTypography.detail).foregroundStyle(.secondary)
            }
            ForEach(report.categories) { item in
                let category = store.ledger.category(item.categoryID)
                VStack(spacing: 6) {
                    HStack {
                        Text(category?.name ?? L10n.text("Category")).font(AppTypography.detail).lineLimit(1)
                        Spacer()
                        Text(TimeText.duration(item.seconds)).font(AppTypography.small).monospacedDigit()
                        Text("\(Int(item.seconds / max(1, report.totalSeconds) * 100))%")
                            .font(.system(size: 9)).monospacedDigit().foregroundStyle(.secondary).frame(width: 30, alignment: .trailing)
                    }
                    GeometryReader { geometry in
                        Capsule().fill(category?.color.tint ?? store.accentColor)
                            .frame(width: geometry.size.width * item.seconds / max(1, report.totalSeconds))
                    }.frame(height: 3)
                }
            }
        }.cardSurface(padding: 13)
    }

    private func weekdays(_ report: AnalyticsSnapshot) -> some View {
        let labels = [L10n.text("MON"), L10n.text("TUE"), L10n.text("WED"), L10n.text("THU"), L10n.text("FRI"), L10n.text("SAT"), L10n.text("SUN")]
        let maximum = max(1, report.weekdayAverages.max() ?? 0)
        return VStack(alignment: .leading, spacing: 12) {
            SectionCaption(title: L10n.text("WEEKDAY AVERAGES"))
            HStack(alignment: .bottom, spacing: 13) {
                ForEach(0..<7) { index in
                    VStack(spacing: 7) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 4).fill(.primary.opacity(0.04))
                            RoundedRectangle(cornerRadius: 4).fill(store.accentColor.opacity(0.75))
                                .frame(height: report.weekdayAverages[index] > 0 ? max(3, 55 * report.weekdayAverages[index] / maximum) : 0)
                        }.frame(height: 55)
                        Text(labels[index]).font(.system(size: 8)).foregroundStyle(.secondary)
                    }.accessibilityElement(children: .ignore)
                        .accessibilityLabel(labels[index] + L10n.text(": average ") + TimeText.duration(report.weekdayAverages[index]))
                }
            }
            Text(L10n.text("Average time per weekday")).font(AppTypography.small).foregroundStyle(.secondary)
        }.cardSurface(padding: 13)
    }
}
