import SwiftUI
import RhythmCore

struct QuickCategoryMenuContent: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        if store.pendingIdle != nil {
            Button("Разобрать простой…", systemImage: "moon.zzz") { store.presentIdleReview() }
        } else {
            Text("Сменить категорию")
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
                Text("Уже учтённое время сохранится")
            }
        }
        Divider()
        Button("Все категории…", systemImage: "tag") { store.page = .categories }
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
                    Text("Отвлеклись?").font(.system(size: 22, weight: .semibold))
                    Text("Mac долго не использовался. Таймер на паузе; выберите, учитывать ли это время как работу.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                }
                VStack(alignment: .leading, spacing: 9) {
                    Text(TimeText.duration(review.duration(at: store.now))).font(.system(size: 34, weight: .light)).monospacedDigit()
                    Text(review.startedAt.formatted(.dateTime.hour().minute()) + " · " + (review.returnedAt ?? store.now).formatted(.dateTime.hour().minute()))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    if let active = store.active {
                        Text(active.displayTitle + " · " + (store.ledger.category(active.categoryID)?.name ?? "Категория"))
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).cardSurface(padding: 17)
                HStack {
                    Text("Продолжить отсчёт").font(.system(size: 12))
                    Spacer()
                    Toggle("Продолжить отсчёт", isOn: $resume).labelsHidden().toggleStyle(AccentSwitchStyle())
                }
                VStack(spacing: 9) {
                    Button { store.resolveIdle(includeTime: false, resume: resume) } label: { Label("Исключить простой", systemImage: "minus.circle") }
                        .buttonStyle(PrimaryButton())
                    Button { store.resolveIdle(includeTime: true, resume: resume) } label: {
                        Text("Засчитать время как работу").font(.system(size: 12)).frame(maxWidth: .infinity).frame(height: 36)
                            .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain)
                }
                Text("Если вы читали, думали или работали без клавиатуры и мыши, время можно засчитать. Ожидание решения останется паузой.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
                Button("Решить позже") { store.page = .focus }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
    }
}
