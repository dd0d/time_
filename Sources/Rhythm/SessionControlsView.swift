import SwiftUI
import RhythmCore

struct QuickCategoryMenuContent: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        if store.pendingIdle != nil {
            Button(L10n.text("Review Idle Time…"), systemImage: "moon.zzz") { store.presentIdleReview() }
        } else {
            Text(L10n.text("Switch Category"))
            ForEach(store.categories) { category in
                let seconds = store.ledger.total(on: store.now, categoryID: category.id, at: store.now)
                let goal = store.ledger.plannedMinutes(for: category.id, on: store.now)
                let detail = TimeText.duration(seconds) + (goal > 0 ? " / " + TimeText.duration(Double(goal * 60)) : "")
                Button { store.selectCategoryQuickly(category.id) } label: {
                    Label(category.name + " · " + detail, systemImage: category.id == store.currentCategoryID ? "checkmark" : "circle")
                }
            }
            if store.active != nil {
                Divider()
                Text(L10n.text("Tracked time is saved"))
            }
        }
        Divider()
        Button(L10n.text("All Categories…"), systemImage: "tag") { store.page = .categories }
    }
}

struct IdleReviewView: View {
    @EnvironmentObject var store: AppStore
    @State private var resume = true

    var body: some View {
        if let review = store.pendingIdle {
            VStack(alignment: .leading, spacing: 21) {
                VStack(alignment: .leading, spacing: 9) {
                    Image(systemName: "moon.zzz").font(.system(size: 27, weight: .light)).foregroundStyle(store.accentColor)
                    Text(L10n.text("Idle time")).font(.system(size: 22, weight: .semibold))
                    Text(L10n.text("The timer paused while your Mac was idle. Choose whether to count that time."))
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                }
                VStack(alignment: .leading, spacing: 9) {
                    Text(TimeText.duration(review.duration(at: store.now))).font(.system(size: 34, weight: .light)).monospacedDigit()
                    Text(review.startedAt.formatted(.dateTime.locale(L10n.locale).hour().minute()) + " · " + (review.returnedAt ?? store.now).formatted(.dateTime.locale(L10n.locale).hour().minute()))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    if let active = store.active {
                        Text(active.displayTitle + " · " + (store.ledger.category(active.categoryID)?.name ?? L10n.text("Category")))
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).cardSurface(padding: 17)
                HStack {
                    Text(L10n.text("Resume timer")).font(.system(size: 12))
                    Spacer()
                    Toggle(L10n.text("Resume timer"), isOn: $resume).labelsHidden().toggleStyle(AccentSwitchStyle())
                }
                VStack(spacing: 9) {
                    Button { store.resolveIdle(includeTime: false, resume: resume) } label: { Label(L10n.text("Exclude Idle Time"), systemImage: "minus.circle") }
                        .buttonStyle(PrimaryButton())
                    Button { store.resolveIdle(includeTime: true, resume: resume) } label: {
                        Text(L10n.text("Count as Work")).font(.system(size: 12)).frame(maxWidth: .infinity).frame(height: 36)
                            .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain)
                }
                Text(L10n.text("If you were working away from the keyboard, you can count the time. The timer stays paused until you decide."))
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
                Button(L10n.text("Decide Later")) { store.page = .focus }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
    }
}
