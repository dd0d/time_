import SwiftUI
import RhythmCore
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 9) {
                Text("ОФОРМЛЕНИЕ").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                AppSegments(selection: $store.ledger.preferences.appearance, options: ["system", "light", "dark"], title: { $0 == "system" ? "Система" : $0 == "light" ? "Светлое" : "Тёмное" })
                    .onChange(of: store.ledger.preferences.appearance) { _, _ in store.save() }
            }
            glassSettings
            menuBarSettings
            accentSettings
            VStack(alignment: .leading, spacing: 10) {
                Text("КОМПАКТНОЕ МЕНЮ").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                settingToggle("Анимация логотипа", symbol: "arrow.triangle.2.circlepath", binding: preference(\.animateLogo))
                Text("Логотип вращается при отсчёте и сжимается при нажатии. Этот переключатель управляет анимацией в time_, в том числе при уменьшении движения в macOS.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            pomodoroSettings
            idleSettings
            VStack(spacing: 14) {
                settingToggle("Звук завершения", symbol: "speaker.wave.2", binding: preference(\.soundEnabled))
                settingToggle("Уведомление о таймере", symbol: "bell", binding: preference(\.notificationsEnabled))
                settingToggle("Пауза при блокировке", symbol: "lock", binding: preference(\.pauseOnLock))
                settingToggle("Запускать при входе", symbol: "sunrise", binding: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
            }
            .cardSurface(padding: 14)

            if let loginError {
                Text(loginError).font(.system(size: 10)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if SMAppService.mainApp.status == .requiresApproval {
                Button("Разрешить запуск в системных настройках…") { SMAppService.openSystemSettingsLoginItems() }.font(.system(size: 11))
            }
            Text("Во время сна Mac отсчёт ставится на паузу. После пробуждения продолжите его вручную.")
                .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
            VStack(alignment: .leading, spacing: 10) {
                Text("ДАННЫЕ").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Button("Экспортировать историю в CSV…") { store.exportCSV() }
                Button("Сохранить резервную копию…") { store.exportBackup() }
                Button("Открыть папку данных") {
                    let directory = store.file.url.deletingLastPathComponent()
                    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(directory)
                }
            }
            .font(.system(size: 11))
            HStack {
                RhythmMark(size: 14).foregroundStyle(.tertiary)
                Text("time_ 1.5.2").font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                Text("Только на вашем Mac").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDisappear { store.stopGlowPreview(); store.save() }
    }

    private var glassSettings: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("ПРОЗРАЧНОСТЬ МЕНЮ").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button("По умолчанию") {
                    store.ledger.preferences.backgroundOpacity = GlassStyle.defaultOpacity
                    store.ledger.preferences.backgroundBlur = GlassStyle.defaultBlur
                    store.save()
                }
                .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(store.accentColor)
            }
            glassSlider("Непрозрачность фона", value: $store.ledger.preferences.backgroundOpacity)
            glassSlider("Размытие", value: $store.ledger.preferences.backgroundBlur)
            Text("Меняется только фон. Текст и кнопки остаются чёткими.")
                .font(.system(size: 10)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func glassSlider(_ title: String, value: Binding<Double>) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title).font(.system(size: 11))
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded()))%")
                    .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
            }
            AccentSlider(value: value, accessibilityTitle: title, onEditingChanged: { editing in if !editing { store.save() } })
        }
    }

    private var menuBarSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("СТРОКА МЕНЮ").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            settingToggle("Показывать время", symbol: "clock", binding: preference(\.showMenuBarTime))
            HStack {
                Text("Значок").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                SelectionDropdown(selection: $store.ledger.preferences.menuBarIcon, options: MenuBarIcon.allCases, title: { $0.title }, accessibilityTitle: "Значок в строке меню")
                    .frame(width: 140).onChange(of: store.ledger.preferences.menuBarIcon) { _, _ in store.save() }
            }
            Text("Время отображается во время активной сессии.").font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }

    private var accentSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("АКЦЕНТНЫЙ ЦВЕТ").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            HStack {
                Button {
                    store.ledger.preferences.accentChoice = .system
                    store.save()
                } label: {
                    Label("Системный", systemImage: store.ledger.preferences.accentChoice == .system ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.plain).font(.system(size: 12))
                .foregroundStyle(store.ledger.preferences.accentChoice == .system ? store.accentColor : .secondary)
                Spacer()
                ColorPicker("Свой цвет", selection: Binding(get: { store.accentColor }, set: { store.setCustomAccent($0) }), supportsOpacity: false)
                    .font(.system(size: 11)).fixedSize()
            }
            HStack(spacing: 12) {
                ForEach(AccentChoice.allCases.filter { $0 != .system && $0 != .custom }, id: \.self) { choice in
                    Button {
                        store.ledger.preferences.accentChoice = choice
                        store.save()
                    } label: {
                        Circle().fill(Color(nsColor: choice.nativeColor)).frame(width: 19, height: 19)
                            .overlay {
                                if store.ledger.preferences.accentChoice == choice {
                                    Circle().strokeBorder(.primary.opacity(0.65), lineWidth: 1.3).padding(-3)
                                }
                            }
                    }
                    .buttonStyle(.plain).accessibilityLabel(choice.title)
                    .accessibilityAddTraits(store.ledger.preferences.accentChoice == choice ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var pomodoroSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ПОМОДОРО").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            pomodoroStepper("Фокус", value: $store.ledger.preferences.pomodoro.focusMinutes, range: 1...120, suffix: "мин")
            pomodoroStepper("Короткий перерыв", value: $store.ledger.preferences.pomodoro.shortBreakMinutes, range: 1...30, suffix: "мин")
            pomodoroStepper("Длинный перерыв", value: $store.ledger.preferences.pomodoro.longBreakMinutes, range: 1...60, suffix: "мин")
            pomodoroStepper("До длинного перерыва", value: $store.ledger.preferences.pomodoro.roundsBeforeLongBreak, range: 2...8, suffix: "сессии")
            settingToggle("Автоматически начинать отдых", symbol: "cup.and.saucer", binding: Binding(get: { store.ledger.preferences.pomodoro.autoStartBreaks }, set: {
                store.ledger.preferences.pomodoro.autoStartBreaks = $0; store.save()
            }))
            settingToggle("Свечение по краям во время отдыха", symbol: "light.beacon.min", binding: preference(\.breakEdgeGlowEnabled))
            if store.ledger.preferences.breakEdgeGlowEnabled { glowSettings }
            Text("Следующий фокус всегда запускаете вы. Начало и конец отдыха видны в компактном меню и уведомлениях. Перерывы не входят в рабочее время.")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var glowSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            glowSlider("Ширина", value: $store.ledger.preferences.glowWidth, range: 24...320, display: "\(Int(store.ledger.preferences.glowWidth.rounded())) пт")
            glowSlider("Яркость", value: $store.ledger.preferences.glowIntensity, range: 0...1, display: "\(Int((store.ledger.preferences.glowIntensity * 100).rounded()))%")
            HStack {
                Button(store.isGlowPreviewing ? "Остановить предпросмотр" : "Показать свечение") {
                    if store.isGlowPreviewing { store.stopGlowPreview() } else { store.showGlowPreview() }
                }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(store.accentColor)
                Spacer()
                Button("Сбросить") {
                    store.ledger.preferences.glowWidth = GlowStyle.defaultWidth
                    store.ledger.preferences.glowIntensity = GlowStyle.defaultIntensity
                    store.save()
                    store.showGlowPreview()
                }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.padding(.leading, 26)
    }

    private func glowSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, display: String) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title).font(.system(size: 11))
                Spacer()
                Text(display).font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
            }
            AccentSlider(value: value, range: range, accessibilityTitle: "Свечение: " + title, onEditingChanged: { editing in
                store.showGlowPreview()
                if !editing { store.save() }
            })
        }
    }

    private var idleSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ПРОВЕРКА ПРОСТОЯ").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            settingToggle("Замечать отсутствие активности", symbol: "moon.zzz", binding: preference(\.idleCheckEnabled))
            HStack {
                Text("После").font(.system(size: 11))
                Spacer()
                SelectionDropdown(selection: $store.ledger.preferences.idleMinutes, options: [1, 3, 5, 10, 15, 30], title: { "\($0) мин" }, accessibilityTitle: "Порог простоя")
                    .frame(width: 110).disabled(!store.ledger.preferences.idleCheckEnabled)
                    .onChange(of: store.ledger.preferences.idleMinutes) { _, _ in store.save() }
            }
            Text("Таймер встанет на паузу. После возвращения выберите, исключить простой или засчитать его. При чтении и размышлении время можно оставить.")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func pomodoroStepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, suffix: String) -> some View {
        HStack {
            Text(title).font(.system(size: 11))
            Spacer(minLength: 4)
            Text("\(value.wrappedValue) \(suffix)").font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
            Stepper(title, value: value, in: range).labelsHidden().controlSize(.small)
        }
        .onChange(of: value.wrappedValue) { _, _ in store.save() }
    }

    private func preference(_ keyPath: WritableKeyPath<Preferences, Bool>) -> Binding<Bool> {
        Binding(get: { store.ledger.preferences[keyPath: keyPath] }, set: { value in
            store.ledger.preferences[keyPath: keyPath] = value
            store.save()
            if keyPath == \Preferences.notificationsEnabled && value { store.onNotificationPermissionNeeded?() }
            if keyPath == \Preferences.idleCheckEnabled && value && store.ledger.preferences.notificationsEnabled { store.onNotificationPermissionNeeded?() }
            if keyPath == \Preferences.breakEdgeGlowEnabled && !value { store.stopGlowPreview() }
        })
    }

    private func settingToggle(_ title: String, symbol: String, binding: Binding<Bool>) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 17)
            Text(title).font(.system(size: 12))
            Spacer(minLength: 4)
            Toggle(title, isOn: binding).labelsHidden().toggleStyle(AccentSwitchStyle())
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginError = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginError = "Переместите time_ в «Программы» и попробуйте ещё раз: \(error.localizedDescription)"
        }
    }
}

struct CategoriesView: View {
    @EnvironmentObject var store: AppStore
    @State private var editingID: UUID?
    @State private var name = ""
    @State private var color: CategoryColor = .mint
    @State private var goal = 0
    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            if isEditing {
                editor
            } else {
                VStack(spacing: 7) {
                        ForEach(store.categories) { category in
                            Button {
                                editingID = category.id; name = category.name; color = category.color; goal = category.dailyGoalMinutes; isEditing = true
                            } label: {
                                HStack(spacing: 10) {
                                    Circle().fill(category.color.tint).frame(width: 9, height: 9)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(category.name).font(.system(size: 12, weight: .medium)).foregroundStyle(.primary)
                                        Text(category.dailyGoalMinutes == 0 ? "План из задач" : TimeText.duration(Double(category.dailyGoalMinutes * 60)) + " в день")
                                            .font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(store.accentColor)
                                }
                                .cardSurface(padding: 12)
                            }
                            .buttonStyle(.plain)
                        }
                }
                Button {
                    editingID = nil; name = ""; color = .lavender; goal = 0; isEditing = true
                } label: { Label("Новая категория", systemImage: "plus") }.buttonStyle(PrimaryButton())
                let archived = store.ledger.categories.filter(\.isArchived)
                if !archived.isEmpty {
                    CategoryArchiveMenu(categories: archived)
                }
                Text("Если цель равна нулю, план считается по оценкам задач.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Название").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("Например, свой проект", text: $name).textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 13) {
                ForEach(CategoryColor.allCases, id: \.self) { candidate in
                    Button { color = candidate } label: {
                        Circle().fill(candidate.tint).frame(width: 24, height: 24)
                            .overlay { if candidate == color { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white) } }
                    }
                    .buttonStyle(.plain).accessibilityLabel(colorName(candidate))
                    .accessibilityAddTraits(candidate == color ? .isSelected : [])
                }
            }
            HStack {
                Text("Цель на день").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                TextField("Минуты", value: $goal, format: .number).textFieldStyle(.roundedBorder).frame(width: 55)
                Text("мин").font(.system(size: 11)).foregroundStyle(.secondary)
                Stepper("Цель на день", value: $goal, in: 0...1440, step: 15).labelsHidden()
            }
            Text("При нуле план считается по оценкам задач.").font(.system(size: 10)).foregroundStyle(.tertiary)
            Button(editingID == nil ? "Создать категорию" : "Сохранить") {
                let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else { return }
                if let id = editingID, var category = store.ledger.category(id) {
                    category.name = String(clean.prefix(40)); category.color = color; category.dailyGoalMinutes = max(0, min(1440, goal))
                    store.updateCategory(category)
                } else { store.addCategory(name: clean, color: color, goal: goal) }
                isEditing = false
            }
            .buttonStyle(PrimaryButton()).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
            HStack {
                Button("Назад") { isEditing = false }.font(.system(size: 11))
                Spacer()
                if let id = editingID {
                    Button("В архив") { store.archiveCategory(id); isEditing = false }
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .disabled(store.categories.count <= 1 || store.active?.categoryID == id)
                }
            }
        }
    }

    private func colorName(_ color: CategoryColor) -> String {
        switch color {
        case .mint: return "Мятный"
        case .blue: return "Голубой"
        case .lavender: return "Лавандовый"
        case .peach: return "Персиковый"
        case .rose: return "Розовый"
        case .yellow: return "Жёлтый"
        }
    }
}

private struct CategoryArchiveMenu: View {
    @EnvironmentObject var store: AppStore
    let categories: [TimeCategory]
    @State private var expanded = false

    var body: some View {
        Button { expanded.toggle() } label: {
            HStack(spacing: 7) {
                Text("Архив · \(categories.count)").font(.system(size: 11))
                Spacer()
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(store.accentColor)
            .padding(.horizontal, 10).frame(height: 31)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain).accessibilityLabel("Архив категорий: \(categories.count)")
        .popover(isPresented: $expanded, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 7) {
                Text("АРХИВ КАТЕГОРИЙ").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 9).padding(.top, 5)
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(categories) { category in
                            Button {
                                expanded = false
                                store.restoreCategory(category.id)
                            } label: {
                                HStack(spacing: 8) {
                                    Circle().fill(category.color.tint).frame(width: 6, height: 6)
                                    Text(category.name).font(.system(size: 12)).lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "arrow.uturn.backward").font(.system(size: 10))
                                        .foregroundStyle(store.accentColor)
                                }
                                .foregroundStyle(.primary).padding(.horizontal, 9).frame(minHeight: 32)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).accessibilityLabel("Вернуть «\(category.name)»")
                        }
                    }
                }.frame(height: min(280, CGFloat(categories.count) * 35 - 3))
            }
            .padding(7).frame(width: 250).background(MenuGlass())
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .modifier(RhythmAppearance(store: store)).environmentObject(store)
            .presentationBackground(.clear)
        }
    }
}
