import SwiftUI
import RhythmCore

struct RootView: View {
    static let compactSize = NSSize(width: 260, height: 100)
    static let expandedSize = NSSize(width: 392, height: 640)
    private static let recoverySize = NSSize(width: 392, height: 230)
    @MainActor static func size(for store: AppStore) -> NSSize {
        if store.isStorageReadOnly { return recoverySize }
        guard store.page == .focus else { return expandedSize }
        return NSSize(width: compactSize.width, height: compactSize.height + (store.compactEditor != nil ? store.compactEditorHeight : 0))
    }
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if store.isStorageReadOnly {
                recoveryView.frame(width: Self.recoverySize.width, height: Self.recoverySize.height)
            } else if store.page == .focus {
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

    private var recoveryView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L10n.text("Data unavailable"), systemImage: "exclamationmark.triangle")
                .font(AppTypography.pageTitle)
            if let error = store.storageError {
                ScrollView {
                    Text(error).font(AppTypography.body).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 86)
            }
            HStack {
                Button(L10n.text("Restore Backup…")) { store.chooseBackupToRestore() }
                Button(L10n.text("Open Data Folder")) { store.openDataFolder() }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CompactMenuView: View {
    @EnvironmentObject var store: AppStore
    @State private var iconHovered = false
    private var orbAction: String { store.pendingIdle != nil ? L10n.text("Review Idle Time") : (store.active.map { $0.isRunning ? L10n.text("Pause") : L10n.text("Resume") } ?? L10n.text("Quick Start")) }

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
                        Text(time).timeDisplay(size: time.count > 5 ? 22 : 26)
                            .foregroundStyle(store.active?.isPaused == true ? Color.secondary : Color.primary)
                    }
                    .buttonStyle(.plain).accessibilityLabel(L10n.text("Time ") + time + L10n.text(". Mode and duration"))
                    Button { store.compactEditor = store.compactEditor == .details ? nil : .details } label: {
                        HStack(spacing: 4) {
                            Image(systemName: store.storageError != nil ? "exclamationmark.triangle" : "tag").font(.system(size: 10))
                            Text(compactTitle)
                                .font(AppTypography.body).lineLimit(1)
                        }
                        .foregroundStyle(store.storageError != nil ? Color.orange : store.accentColor)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityLabel(L10n.text("Task and category"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 2) {
                    PanelPinButton(size: 22)
                    moreMenu
                }
                .padding(.top, 1)
            }
            .frame(height: 50)
            HStack(spacing: 7) {
                if store.pendingIdle != nil {
                    Button { store.presentIdleReview() } label: { Label(L10n.text("Review Idle Time"), systemImage: "moon.zzz").frame(maxWidth: .infinity) }
                        .buttonStyle(CompactButtonStyle())
                } else if let active = store.active {
                    Button { store.pauseOrResume() } label: {
                        Label(active.isRunning ? L10n.text("Pause") : L10n.text("Resume"), systemImage: active.isRunning ? "pause" : "play").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CompactButtonStyle()).keyboardShortcut(.return, modifiers: .command)
                    Button { store.finish() } label: { Image(systemName: "stop.fill").frame(width: 26) }
                        .buttonStyle(CompactButtonStyle()).accessibilityLabel(L10n.text("Stop and Save"))
                } else {
                    Button {
                        if store.canStart { store.start() }
                        else { store.page = .session }
                    } label: { Label(store.mode == .pomodoro ? (store.pomodoroPhase.isBreak ? L10n.text("Start Break") : L10n.text("Start Focus")) : L10n.text("Start"), systemImage: "play.circle").frame(maxWidth: .infinity) }
                    .buttonStyle(CompactButtonStyle()).keyboardShortcut(.return, modifiers: .command)
                }
                Button { store.page = .summary } label: { Image(systemName: "chart.bar.fill").frame(width: 26) }
                    .buttonStyle(CompactButtonStyle()).accessibilityLabel(L10n.text("Open History"))
            }
        }
        .padding(10)
    }

    private var compactTitle: String {
        if store.storageError != nil { return L10n.text("Could not save") }
        if store.pendingIdle != nil { return store.phaseCaption }
        let name = store.active?.title ?? store.title
        if store.active?.isBreak == true { return L10n.text("Break · ") + (store.currentCategory?.name ?? "") }
        return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (store.currentCategory?.name ?? L10n.text("Choose a category")) : name
    }

    private var moreMenu: some View {
        Menu {
            Button(L10n.text("Daily Plan…"), systemImage: "checklist") { store.page = .plan }
            Button(L10n.text("History…"), systemImage: "chart.bar") { store.page = .summary }
            Divider()
            Button(L10n.text("Categories…"), systemImage: "tag") { store.page = .categories }
            Button(L10n.text("Settings…"), systemImage: "gearshape") { store.page = .settings }
            Divider()
            Button(L10n.text("Quit time_"), systemImage: "power") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14)).foregroundStyle(.secondary).frame(width: 22, height: 22)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel(L10n.text("App menu"))
    }
}

private struct PanelPinButton: View {
    @EnvironmentObject private var store: AppStore
    var size: CGFloat = 28

    var body: some View {
        let title = store.isPinned ? L10n.text("Unpin Panel") : L10n.text("Pin Panel")
        QuietIconButton(symbol: store.isPinned ? "pin.fill" : "pin", help: title,
                        selected: store.isPinned, size: size, showsHoverBackground: false) {
            store.isPinned.toggle()
            store.onPinChanged?()
        }
        .help(title)
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
        configuration.label.font(AppTypography.rowTitle).foregroundStyle(.primary.opacity(0.8))
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
                    QuietIconButton(symbol: "chevron.left", help: L10n.text("Back")) { store.page = store.page == .analytics ? .summary : store.lastMainPage }
                } else { RhythmMark(size: 19).foregroundStyle(store.accentColor) }
                Text(isUtility ? store.page.title : "time_").font(AppTypography.panelTitle)
                Spacer()
                PanelPinButton()
                QuietIconButton(symbol: "rectangle.compress.vertical", help: L10n.text("Collapse panel")) { store.page = .focus }
            }
            .padding(.horizontal, 20).padding(.top, 15).padding(.bottom, 13)
            HStack(spacing: 3) {
                ForEach([AppPage.session, .plan, .summary], id: \.self) { page in
                    Button { store.page = page } label: {
                        HStack(spacing: 5) {
                            Image(systemName: page.symbol).font(.system(size: 11))
                            Text(page.title).font(.system(size: 11, weight: isSelected(page) ? .semibold : .medium))
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
                        Text(error).font(AppTypography.detail).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
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
                Button { store.page = .categories } label: { Label(L10n.text("Categories"), systemImage: "tag") }
                    .foregroundStyle(store.page == .categories ? store.accentColor : .secondary)
                Button { store.page = .settings } label: { Label(L10n.text("Settings"), systemImage: "gearshape") }
                    .foregroundStyle(store.page == .settings ? store.accentColor : .secondary)
                Spacer(minLength: 4)
                Text(TimeText.duration(store.totalToday)).monospacedDigit().foregroundStyle(.tertiary)
            }
            .font(AppTypography.small).buttonStyle(.plain).padding(.horizontal, 21).padding(.vertical, 13)
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
                        Text(L10n.text("Idle time · ") + TimeText.duration(review.duration(at: store.now)))
                        Spacer()
                        Text(L10n.text("Review")).foregroundStyle(store.accentColor)
                    }.font(AppTypography.detail).cardSurface(padding: 12)
                }.buttonStyle(.plain)
            }
            VStack(spacing: 15) {
                TextField(L10n.text("Name (optional)"), text: $store.title, axis: .vertical)
                    .font(.system(size: 16, weight: .medium)).textFieldStyle(.plain).lineLimit(1...2).focused($titleFocused)
                    .accessibilityLabel(L10n.text("Task name"))
                    .onSubmit { commit() }
                    .onChange(of: store.title) { _, value in
                        if store.active == nil, let id = store.selectedTaskID, store.ledger.tasks.first(where: { $0.id == id })?.title != value { store.clearTaskAssociation() }
                    }
                HStack {
                    CategoryPicker(selection: $store.selectedCategoryID)
                    Spacer()
                    if changedActiveDetails {
                        Button(L10n.text("Save")) { store.updateSessionDetails(title: store.title, categoryID: store.selectedCategoryID) }
                            .buttonStyle(.borderless).font(AppTypography.detail)
                    }
                }
                VStack(spacing: 5) {
                    Text(time).timeDisplay(size: time.count > 5 ? 42 : 54)
                    Text(store.active == nil && store.mode == .pomodoro ? store.pomodoroPhase.title : store.phaseCaption)
                        .font(AppTypography.detail).foregroundStyle(.secondary)
                }.padding(.vertical, 5)
                if let active = store.active {
                    if active.mode.isTimed {
                        AccentProgress(value: active.elapsed(at: store.now) / max(1, active.targetSeconds))
                        HStack {
                            Text(L10n.text("Elapsed ") + TimeText.duration(active.elapsed(at: store.now))).font(AppTypography.small).foregroundStyle(.secondary)
                            Spacer()
                            if active.mode == .countdown { Button(L10n.text("+ 5 min")) { store.extendTimer() }.buttonStyle(.plain).font(AppTypography.detail) }
                            if active.isBreak { Button(L10n.text("Skip")) { store.skipPomodoroBreak() }.buttonStyle(.plain).font(AppTypography.detail) }
                        }
                    }
                    HStack(spacing: 8) {
                        Button { store.pauseOrResume() } label: { Label(active.isRunning ? L10n.text("Pause") : L10n.text("Resume"), systemImage: active.isRunning ? "pause.fill" : "play.fill") }
                            .buttonStyle(PrimaryButton()).keyboardShortcut(.return, modifiers: .command)
                        Button { store.finish() } label: { Image(systemName: "stop.fill").frame(width: 42, height: 42) }
                            .buttonStyle(.borderless).background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                            .accessibilityLabel(active.isBreak ? L10n.text("End break") : L10n.text("Stop and Save"))
                    }
                } else {
                    AppSegments(selection: $store.mode, options: TrackingMode.allCases, title: { $0.title }).accessibilityLabel(L10n.text("Mode"))
                    if store.mode == .countdown {
                        HStack(spacing: 6) {
                            ForEach([25, 45, 60], id: \.self) { minutes in
                                Button(L10n.text("\(minutes) min")) { store.minutes = minutes }
                                    .foregroundStyle(store.minutes == minutes ? store.accentColor : .secondary)
                            }
                            Spacer(minLength: 1)
                            TextField(L10n.text("Minutes"), value: $store.minutes, format: .number).textFieldStyle(.roundedBorder).frame(width: 37)
                            Stepper(L10n.text("Minutes"), value: $store.minutes, in: 1...480).labelsHidden()
                        }.font(AppTypography.small).controlSize(.small)
                    }
                    if store.mode == .pomodoro { pomodoroSummary }
                    Button(action: commit) { Label(store.mode == .pomodoro ? (store.pomodoroPhase.isBreak ? L10n.text("Start Break") : L10n.text("Start Focus")) : L10n.text("Start"), systemImage: "play.fill") }
                        .buttonStyle(PrimaryButton()).keyboardShortcut(.return, modifiers: .command).disabled(!store.canStart)
                }
            }
            .cardSurface(padding: 17)
            if let completed = store.lastCompleted, store.active == nil {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(store.accentColor)
                    Text((completed.isBreak ? L10n.text("Break ended · ") : L10n.text("Saved · ")) + TimeText.duration(completed.elapsed(at: completed.endedAt ?? store.now)))
                        .font(AppTypography.detail).foregroundStyle(.secondary)
                    Spacer()
                    QuietIconButton(symbol: "xmark", help: L10n.text("Dismiss")) { store.lastCompleted = nil }
                }
            }
            VStack(spacing: 13) {
                SectionCaption(title: L10n.text("TODAY"), trailing: TimeText.duration(store.totalToday))
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
                Text(L10n.text("\(settings.focusMinutes) / \(settings.shortBreakMinutes) / \(settings.longBreakMinutes) min"))
                    .font(AppTypography.small).foregroundStyle(.secondary)
            }
            HStack {
                Text(settings.autoStartBreaks ? L10n.text("Breaks start automatically. Start the next focus session when ready.") : L10n.text("Start each phase manually.")).font(AppTypography.small).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if store.pomodoroPhase.isBreak {
                    Button(L10n.text("Skip")) { store.skipPomodoroBreak() }.font(AppTypography.small).buttonStyle(.plain).foregroundStyle(store.accentColor)
                } else if completed > 0 {
                    Button(L10n.text("Reset")) { store.resetPomodoro() }.font(AppTypography.small).buttonStyle(.plain).foregroundStyle(store.accentColor)
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
                Text(store.isToday ? L10n.text("Today") : store.selectedDay.formatted(.dateTime.locale(L10n.locale).day().month(.wide)))
                    .font(AppTypography.pageTitle)
                Text(dayCaption)
                    .font(AppTypography.detail).foregroundStyle(.secondary)
            }
            Spacer()
            if !store.isToday {
                Button(L10n.text("Today")) { store.selectedDay = Calendar.current.startOfDay(for: Date()) }
                    .font(AppTypography.small).buttonStyle(.plain).foregroundStyle(.secondary)
            }
            HStack(spacing: 1) {
                QuietIconButton(symbol: "chevron.left", help: L10n.text("Previous day")) { store.changeDay(-1, allowsFuture: allowsFuture) }
                QuietIconButton(symbol: "chevron.right", help: L10n.text("Next day")) { store.changeDay(1, allowsFuture: allowsFuture) }
                    .disabled(!allowsFuture && store.isToday).opacity(!allowsFuture && store.isToday ? 0.3 : 1)
            }
        }
    }

    private var dayCaption: String {
        let text = store.selectedDay.formatted(.dateTime.locale(L10n.locale).weekday(.wide).day().month(.wide))
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
                Text(category.name).font(AppTypography.body).lineLimit(1)
                Spacer(minLength: 4)
                Text(TimeText.duration(tracked)).font(.system(size: 11, weight: .medium)).monospacedDigit()
                if goal > 0 { Text("/ " + TimeText.duration(Double(goal * 60))).font(AppTypography.small).foregroundStyle(.secondary).monospacedDigit() }
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
                .accessibilityLabel(L10n.text("\(Int(min(1, tracked / Double(goal * 60)) * 100)) percent of the goal"))
            }
        }
    }
}
