import SwiftUI
import RhythmCore

struct RootView: View {
    static let compactSize = NSSize(width: 260, height: 100)
    static let expandedSize = NSSize(width: 392, height: 640)
    @MainActor static func size(for store: AppStore) -> NSSize {
        guard store.page == .focus else { return expandedSize }
        return NSSize(width: compactSize.width, height: compactSize.height + (store.compactEditor != nil ? store.compactEditorHeight : 0))
    }
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if store.page == .focus {
                VStack(spacing: 0) {
                    CompactMenuView().frame(height: Self.compactSize.height)
                    if let editor = store.compactEditor { CompactEditorView(editor: editor).id(editor) }
                }.frame(width: Self.compactSize.width).fixedSize(horizontal: false, vertical: true)
            }
            else { ExpandedMenuView().frame(width: Self.expandedSize.width, height: Self.expandedSize.height) }
        }
        .background(MenuGlass())
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(scheme == .dark ? .white.opacity(0.18) : .white.opacity(0.5), lineWidth: 0.7))
        .onExitCommand {
            if store.page == .focus, store.compactEditor != nil { store.compactEditor = nil }
            else if store.page == .focus { store.onCloseRequested?() }
            else { store.page = .focus }
        }
        .modifier(RhythmAppearance(store: store))
    }
}

private struct CompactMenuView: View {
    @EnvironmentObject var store: AppStore
    @State private var iconHovered = false
    private var orbAction: String { store.pendingIdle != nil ? "Разобрать простой" : (store.active.map { $0.isRunning ? "Пауза" : "Продолжить" } ?? "Быстрый старт") }

    private var time: String {
        if let active = store.active {
            return TimeText.clock(active.mode.isTimed ? active.remaining(at: store.now) : active.elapsed(at: store.now), countdown: active.mode.isTimed)
        }
        return TimeText.clock(store.idleSeconds, countdown: store.mode.isTimed)
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Button(action: store.quickToggle) {
                    FocusOrb(highlighted: iconHovered)
                }
                .buttonStyle(OrbButtonStyle())
                .onHover { iconHovered = $0 }
                .accessibilityLabel(orbAction)
                .contextMenu { QuickCategoryMenuContent() }
                VStack(alignment: .leading, spacing: 2) {
                    Button { store.compactEditor = store.compactEditor == .timer ? nil : .timer } label: {
                        Text(time).font(.system(size: time.count > 5 ? 22 : 26, weight: .semibold)).monospacedDigit().tracking(-0.8)
                            .foregroundStyle(store.active?.isPaused == true ? Color.secondary : Color.primary)
                    }
                    .buttonStyle(.plain).accessibilityLabel("Время " + time + ". Режим и длительность")
                    Button { store.compactEditor = store.compactEditor == .details ? nil : .details } label: {
                        HStack(spacing: 4) {
                            Image(systemName: store.storageError != nil ? "exclamationmark.triangle" : "tag").font(.system(size: 10))
                            Text(compactTitle)
                                .font(.system(size: 12)).lineLimit(1)
                        }
                        .foregroundStyle(store.storageError != nil ? Color.orange : store.accentColor)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityLabel("Задача и категория")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                moreMenu.padding(.top, 1)
            }
            .frame(height: 50)
            HStack(spacing: 7) {
                if store.pendingIdle != nil {
                    Button { store.presentIdleReview() } label: { Label("Разобрать простой", systemImage: "moon.zzz").frame(maxWidth: .infinity) }
                        .buttonStyle(CompactButtonStyle())
                } else if let active = store.active {
                    Button { store.pauseOrResume() } label: {
                        Label(active.isRunning ? "Пауза" : "Продолжить", systemImage: active.isRunning ? "pause" : "play").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CompactButtonStyle()).keyboardShortcut(.return, modifiers: .command)
                    Button { store.finish() } label: { Image(systemName: "stop.fill").frame(width: 26) }
                        .buttonStyle(CompactButtonStyle()).accessibilityLabel("Завершить и сохранить")
                } else {
                    Button {
                        if store.canStart { store.start() }
                        else { store.page = .session }
                    } label: { Label(store.mode == .pomodoro ? (store.pomodoroPhase.isBreak ? "Начать отдых" : "Начать фокус") : "Начать", systemImage: "play.circle").frame(maxWidth: .infinity) }
                    .buttonStyle(CompactButtonStyle()).keyboardShortcut(.return, modifiers: .command)
                }
                Button { store.page = .summary } label: { Image(systemName: "chart.bar.fill").frame(width: 26) }
                    .buttonStyle(CompactButtonStyle()).accessibilityLabel("Открыть историю")
            }
        }
        .padding(10)
    }

    private var compactTitle: String {
        if store.storageError != nil { return "Ошибка сохранения" }
        if store.pendingIdle != nil { return store.phaseCaption }
        let name = store.active?.title ?? store.title
        if store.active?.isBreak == true { return "Отдых · " + (store.currentCategory?.name ?? "") }
        return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (store.currentCategory?.name ?? "Чем займёмся?") : name
    }

    private var moreMenu: some View {
        Menu {
            Button("План на день…", systemImage: "checklist") { store.page = .plan }
            Button("История…", systemImage: "chart.bar") { store.page = .summary }
            Divider()
            Button("Категории…", systemImage: "tag") { store.page = .categories }
            Button("Настройки…", systemImage: "gearshape") { store.page = .settings }
            Divider()
            Button(store.isPinned ? "Открепить меню" : "Закрепить меню", systemImage: store.isPinned ? "pin.slash" : "pin") {
                store.isPinned.toggle(); store.onPinChanged?()
            }
            Divider()
            Button("Завершить time_", systemImage: "power") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: store.isPinned ? "pin.fill" : "ellipsis")
                .font(.system(size: store.isPinned ? 11 : 15)).foregroundStyle(.secondary).frame(width: 17, height: 17)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Меню приложения")
    }
}

private struct FocusOrb: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var feedback = 0
    var highlighted: Bool

    private var running: Bool { store.active?.isRunning == true }
    private var animateLogo: Bool { store.ledger.preferences.animateLogo }

    var body: some View {
        let reduced = reduceMotion
        ZStack {
            Circle().trim(from: 0.06, to: 0.91).stroke(.secondary.opacity(0.16), style: StrokeStyle(lineWidth: 2.6, lineCap: .round)).rotationEffect(.degrees(-90))
            if let active = store.active {
                let progress = active.mode.isTimed ? min(1, active.elapsed(at: store.now) / max(1, active.targetSeconds)) : 0.85
                Circle().trim(from: 0, to: progress)
                    .stroke(store.accentColor.opacity(active.isPaused ? 0.4 : 0.85), style: StrokeStyle(lineWidth: 2.6, lineCap: .round)).rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .linear(duration: 0.9), value: progress)
            }
            if animateLogo {
                Circle().strokeBorder(store.accentColor, lineWidth: 1.5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .keyframeAnimator(initialValue: 1.0, trigger: feedback) { ring, phase in
                        ring
                            .scaleEffect(reduced ? 1 : 0.83 + 0.22 * phase)
                            .opacity(0.42 * (1 - phase))
                    } keyframes: { _ in
                        MoveKeyframe(0.0)
                        CubicKeyframe(1.0, duration: 0.48)
                    }
            }
            AnimatedRhythmMark(spinning: running && store.isPanelVisible,
                               highlighted: highlighted || running, animationsEnabled: animateLogo)
                .frame(width: 23, height: 23)
        }
        .scaleEffect(highlighted && !reduceMotion ? 1.025 : 1)
        .shadow(color: store.accentColor.opacity(highlighted ? 0.12 : 0), radius: 5)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: highlighted)
        .frame(width: 45, height: 45).padding(.top, 2).contentShape(Circle())
        .onChange(of: running) { _, isRunning in
            if isRunning { flashMark() }
        }
        .onChange(of: store.selectedCategoryID) { _, _ in flashMark() }
        .onChange(of: store.active?.pomodoroPhase) { old, new in
            if old?.isBreak == true || new?.isBreak == true { flashMark() }
        }
    }

    private func flashMark() {
        if animateLogo && store.isPanelVisible { feedback += 1 }
    }
}

private struct OrbButtonStyle: ButtonStyle {
    @EnvironmentObject var store: AppStore
    func makeBody(configuration: Configuration) -> some View {
        let animation: Animation = configuration.isPressed ? .easeOut(duration: 0.09) : .spring(response: 0.30, dampingFraction: 0.76)
        configuration.label.scaleEffect(configuration.isPressed ? 0.91 : 1)
            .animation(store.ledger.preferences.animateLogo ? animation : nil, value: configuration.isPressed)
    }
}

struct CompactButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium)).foregroundStyle(.primary.opacity(0.8))
            .frame(height: 24)
            .background(.primary.opacity(configuration.isPressed ? 0.14 : 0.055), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.065), lineWidth: 0.6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct ExpandedMenuView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) private var scheme
    private var isUtility: Bool { [.categories, .settings, .analytics, .idleReview].contains(store.page) }
    private func isSelected(_ page: AppPage) -> Bool { store.page == page || (page == .summary && store.page == .analytics) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if isUtility {
                    QuietIconButton(symbol: "chevron.left", help: "Назад") { store.page = store.page == .analytics ? .summary : store.lastMainPage }
                } else { RhythmMark(size: 19).foregroundStyle(store.accentColor) }
                Text(isUtility ? store.page.rawValue : "time_").font(.system(size: 14, weight: .semibold))
                Spacer()
                QuietIconButton(symbol: store.isPinned ? "pin.fill" : "pin", help: store.isPinned ? "Открепить меню" : "Закрепить меню", selected: store.isPinned) {
                    store.isPinned.toggle(); store.onPinChanged?()
                }
                QuietIconButton(symbol: "rectangle.compress.vertical", help: "Свернуть меню") { store.page = .focus }
            }
            .padding(.horizontal, 20).padding(.top, 15).padding(.bottom, 13)
            HStack(spacing: 3) {
                ForEach([AppPage.session, .plan, .summary], id: \.self) { page in
                    Button { store.page = page } label: {
                        HStack(spacing: 5) {
                            Image(systemName: page.symbol).font(.system(size: 11))
                            Text(page.rawValue).font(.system(size: 11, weight: isSelected(page) ? .semibold : .medium))
                        }
                        .foregroundStyle(isSelected(page) ? Color.primary : .secondary)
                        .frame(maxWidth: .infinity).frame(height: 29)
                        .background(isSelected(page) ? Palette.card(scheme) : .clear, in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityAddTraits(isSelected(page) ? .isSelected : [])
                }
            }
            .padding(3).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 20).padding(.bottom, 12)
            ScrollView {
                VStack(spacing: 16) {
                    if let error = store.storageError {
                        Text(error).font(.system(size: 11)).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    switch store.page {
                    case .session: ExpandedFocusView()
                    case .plan: PlanView()
                    case .summary: SummaryView()
                    case .analytics: AnalyticsView()
                    case .categories: CategoriesView()
                    case .settings: SettingsView()
                    case .idleReview: IdleReviewView()
                    case .focus: EmptyView()
                    }
                }
                .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 20)
            }
            .id(store.page)
            footer
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Palette.line(scheme)).frame(height: 0.7)
            HStack(spacing: 14) {
                Button { store.page = .categories } label: { Label("Категории", systemImage: "tag") }
                    .foregroundStyle(store.page == .categories ? store.accentColor : .secondary)
                Button { store.page = .settings } label: { Label("Настройки", systemImage: "gearshape") }
                    .foregroundStyle(store.page == .settings ? store.accentColor : .secondary)
                Spacer(minLength: 4)
                Text(TimeText.duration(store.totalToday)).monospacedDigit().foregroundStyle(.tertiary)
            }
            .font(.system(size: 10)).buttonStyle(.plain).padding(.horizontal, 21).padding(.vertical, 13)
        }
    }
}

private struct ExpandedFocusView: View {
    @EnvironmentObject var store: AppStore
    @FocusState private var titleFocused: Bool
    private var time: String {
        if let active = store.active {
            return TimeText.clock(active.mode.isTimed ? active.remaining(at: store.now) : active.elapsed(at: store.now), countdown: active.mode.isTimed)
        }
        return TimeText.clock(store.idleSeconds, countdown: store.mode.isTimed)
    }
    private var changedActiveDetails: Bool {
        guard let active = store.active else { return false }
        return active.title != store.title || active.categoryID != store.selectedCategoryID
    }
    var body: some View {
        VStack(spacing: 17) {
            if let review = store.pendingIdle {
                Button { store.presentIdleReview() } label: {
                    HStack {
                        Image(systemName: "moon.zzz")
                        Text("Простой · " + TimeText.duration(review.duration(at: store.now)))
                        Spacer()
                        Text("Разобрать").foregroundStyle(store.accentColor)
                    }.font(.system(size: 11)).cardSurface(padding: 12)
                }.buttonStyle(.plain)
            }
            VStack(spacing: 15) {
                TextField("Название (необязательно)", text: $store.title, axis: .vertical)
                    .font(.system(size: 16, weight: .medium)).textFieldStyle(.plain).lineLimit(1...2).focused($titleFocused)
                    .accessibilityLabel("Название задачи")
                    .onSubmit { commit() }
                    .onChange(of: store.title) { _, value in
                        if store.active == nil, let id = store.selectedTaskID, store.ledger.tasks.first(where: { $0.id == id })?.title != value { store.clearTaskAssociation() }
                    }
                HStack {
                    CategoryPicker(selection: $store.selectedCategoryID)
                    Spacer()
                    if changedActiveDetails {
                        Button("Сохранить") { store.updateSessionDetails(title: store.title, categoryID: store.selectedCategoryID) }
                            .buttonStyle(.borderless).font(.system(size: 11))
                    }
                }
                VStack(spacing: 5) {
                    Text(time).timeDisplay(size: time.count > 5 ? 42 : 54)
                    Text(store.active == nil && store.mode == .pomodoro ? store.pomodoroPhase.title : store.phaseCaption)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(.vertical, 5)
                if let active = store.active {
                    if active.mode.isTimed {
                        AccentProgress(value: active.elapsed(at: store.now) / max(1, active.targetSeconds))
                        HStack {
                            Text("Прошло " + TimeText.duration(active.elapsed(at: store.now))).font(.system(size: 10)).foregroundStyle(.secondary)
                            Spacer()
                            if active.mode == .countdown { Button("+ 5 мин") { store.extendTimer() }.buttonStyle(.plain).font(.system(size: 11)) }
                            if active.isBreak { Button("Пропустить") { store.skipPomodoroBreak() }.buttonStyle(.plain).font(.system(size: 11)) }
                        }
                    }
                    HStack(spacing: 8) {
                        Button { store.pauseOrResume() } label: { Label(active.isRunning ? "Пауза" : "Продолжить", systemImage: active.isRunning ? "pause.fill" : "play.fill") }
                            .buttonStyle(PrimaryButton()).keyboardShortcut(.return, modifiers: .command)
                        Button { store.finish() } label: { Image(systemName: "stop.fill").frame(width: 42, height: 42) }
                            .buttonStyle(.borderless).background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                            .accessibilityLabel(active.isBreak ? "Завершить перерыв" : "Завершить и сохранить")
                    }
                } else {
                    AppSegments(selection: $store.mode, options: TrackingMode.allCases, title: { $0.title }).accessibilityLabel("Режим")
                    if store.mode == .countdown {
                        HStack(spacing: 6) {
                            ForEach([25, 45, 60], id: \.self) { minutes in
                                Button("\(minutes) мин") { store.minutes = minutes }
                                    .foregroundStyle(store.minutes == minutes ? store.accentColor : .secondary)
                            }
                            Spacer(minLength: 1)
                            TextField("Минуты", value: $store.minutes, format: .number).textFieldStyle(.roundedBorder).frame(width: 37)
                            Stepper("Минуты", value: $store.minutes, in: 1...480).labelsHidden()
                        }.font(.system(size: 10)).controlSize(.small)
                    }
                    if store.mode == .pomodoro { pomodoroSummary }
                    Button(action: commit) { Label(store.mode == .pomodoro ? (store.pomodoroPhase.isBreak ? "Начать отдых" : "Начать фокус") : "Начать", systemImage: "play.fill") }
                        .buttonStyle(PrimaryButton()).keyboardShortcut(.return, modifiers: .command).disabled(!store.canStart)
                }
            }
            .cardSurface(padding: 17)
            if let completed = store.lastCompleted, store.active == nil {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(store.accentColor)
                    Text((completed.isBreak ? "Перерыв завершён · " : "Сохранено · ") + TimeText.duration(completed.elapsed(at: completed.endedAt ?? store.now)))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    QuietIconButton(symbol: "xmark", help: "Скрыть") { store.lastCompleted = nil }
                }
            }
            VStack(spacing: 13) {
                SectionCaption(title: "СЕГОДНЯ", trailing: TimeText.duration(store.totalToday))
                ForEach(store.categories) { category in CategoryProgress(category: category, day: store.now) }
            }
        }
        .onAppear { if store.title.isEmpty { titleFocused = true } }
        .onDisappear { store.saveTimerPreferences() }
    }
    private func commit() {
        if store.active != nil { store.updateSessionDetails(title: store.title, categoryID: store.selectedCategoryID) }
        else { store.minutes = max(1, min(480, store.minutes)); store.start() }
    }

    private var pomodoroSummary: some View {
        let settings = store.ledger.preferences.pomodoro
        let rounds = min(8, max(2, settings.roundsBeforeLongBreak))
        let completed = store.pomodoroPhase == .longBreak ? rounds : (store.ledger.pomodoroProgress?.completedFocusCount ?? 0) % rounds
        return VStack(spacing: 10) {
            HStack(spacing: 5) {
                ForEach(0..<rounds, id: \.self) { index in
                    Circle().fill(index < completed ? store.accentColor : .primary.opacity(0.1)).frame(width: 6, height: 6)
                }
                Spacer()
                Text("\(settings.focusMinutes) / \(settings.shortBreakMinutes) / \(settings.longBreakMinutes) мин")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            HStack {
                Text(settings.autoStartBreaks ? "Перерыв начнётся сам. Следующий фокус запустите вручную." : "Каждый этап запускается вручную.").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if store.pomodoroPhase.isBreak {
                    Button("Пропустить") { store.skipPomodoroBreak() }.font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(store.accentColor)
                } else if completed > 0 {
                    Button("Сначала") { store.resetPomodoro() }.font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(store.accentColor)
                }
            }
        }
    }
}

struct DayNavigation: View {
    @EnvironmentObject var store: AppStore
    var allowsFuture = false
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.isToday ? "Сегодня" : store.selectedDay.formatted(.dateTime.day().month(.wide)))
                    .font(.system(size: 21, weight: .semibold))
                Text(dayCaption)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if !store.isToday {
                Button("Сегодня") { store.selectedDay = Calendar.current.startOfDay(for: Date()) }
                    .font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(.secondary)
            }
            HStack(spacing: 1) {
                QuietIconButton(symbol: "chevron.left", help: "Предыдущий день") { store.changeDay(-1, allowsFuture: allowsFuture) }
                QuietIconButton(symbol: "chevron.right", help: "Следующий день") { store.changeDay(1, allowsFuture: allowsFuture) }
                    .disabled(!allowsFuture && store.isToday).opacity(!allowsFuture && store.isToday ? 0.3 : 1)
            }
        }
    }

    private var dayCaption: String {
        let text = store.selectedDay.formatted(.dateTime.locale(Locale(identifier: "ru_RU")).weekday(.wide).day().month(.wide))
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}

struct CategoryProgress: View {
    @EnvironmentObject var store: AppStore
    let category: TimeCategory
    var day: Date

    var body: some View {
        let tracked = store.ledger.total(on: day, categoryID: category.id, at: store.now)
        let goal = store.ledger.plannedMinutes(for: category.id, on: day)
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                Circle().fill(category.color.tint).frame(width: 6, height: 6)
                Text(category.name).font(.system(size: 12)).lineLimit(1)
                Spacer(minLength: 4)
                Text(TimeText.duration(tracked)).font(.system(size: 11, weight: .medium)).monospacedDigit()
                if goal > 0 { Text("/ " + TimeText.duration(Double(goal * 60))).font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit() }
            }
            if goal > 0 {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.primary.opacity(0.05))
                        Capsule().fill(category.color.tint.opacity(0.85))
                            .frame(width: max(0, geometry.size.width * min(1, tracked / Double(goal * 60))))
                    }
                }
                .frame(height: 3)
                .accessibilityLabel("Выполнено \(Int(min(1, tracked / Double(goal * 60)) * 100)) процентов плана")
            }
        }
    }
}
