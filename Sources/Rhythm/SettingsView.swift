import SwiftUI
import RhythmCore
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @AppStorage(L10n.languagePreference) private var language = "en"

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 9) {
                SectionCaption(title: L10n.text("LANGUAGE"))
                AppSegments(selection: $language, options: ["en", "ru"], title: { $0 == "ru" ? "Русский" : "English" })
                    .accessibilityLabel(L10n.text("Interface language"))
                if language != L10n.language {
                    Text(L10n.text("Quit and reopen time_ to apply the language."))
                        .font(AppTypography.detail).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                Text(L10n.text("APPEARANCE")).font(AppTypography.section).foregroundStyle(.secondary)
                AppSegments(selection: $store.ledger.preferences.appearance, options: ["system", "light", "dark"], title: { $0 == "system" ? L10n.text("System") : $0 == "light" ? L10n.text("Light") : L10n.text("Dark") })
                    .onChange(of: store.ledger.preferences.appearance) { _, _ in store.save() }
            }
            glassSettings
            menuBarSettings
            accentSettings
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.text("COMPACT PANEL")).font(AppTypography.section).foregroundStyle(.secondary)
                settingToggle(L10n.text("Animate logo"), symbol: "arrow.triangle.2.circlepath", binding: preference(\.animateLogo))
                Text(L10n.text("Controls logo motion, including when Reduce Motion is enabled in macOS."))
                    .font(AppTypography.small).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            pomodoroSettings
            idleSettings
            VStack(spacing: 14) {
                settingToggle(L10n.text("Completion sound"), symbol: "speaker.wave.2", binding: preference(\.soundEnabled))
                settingToggle(L10n.text("Timer notifications"), symbol: "bell", binding: preference(\.notificationsEnabled))
                settingToggle(L10n.text("Pause on lock"), symbol: "lock", binding: preference(\.pauseOnLock))
                settingToggle(L10n.text("Open at login"), symbol: "sunrise", binding: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
            }
            .cardSurface(padding: 14)

            if let loginError {
                Text(loginError).font(AppTypography.small).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if SMAppService.mainApp.status == .requiresApproval {
                Button(L10n.text("Allow in System Settings…")) { SMAppService.openSystemSettingsLoginItems() }.font(AppTypography.detail)
            }
            Text(L10n.text("The timer pauses when your Mac sleeps. Resume it manually after waking."))
                .font(AppTypography.small).foregroundStyle(.secondary).lineSpacing(3)
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.text("DATA")).font(AppTypography.section).foregroundStyle(.secondary)
                Button(L10n.text("Export History as CSV…")) { store.exportCSV() }
                Button(L10n.text("Save Backup…")) { store.exportBackup() }
                Button(L10n.text("Open Data Folder")) {
                    let directory = store.file.url.deletingLastPathComponent()
                    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(directory)
                }
            }
            .font(AppTypography.detail)
            HStack {
                RhythmMark(size: 14).foregroundStyle(.tertiary)
                if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                    Text("time_ \(version)").font(AppTypography.small).foregroundStyle(.tertiary)
                }
                Spacer()
                Text(L10n.text("Stored on this Mac")).font(AppTypography.small).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDisappear { store.stopGlowPreview(); store.save() }
    }

    private var glassSettings: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(L10n.text("PANEL TRANSPARENCY")).font(AppTypography.section).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.text("Reset")) {
                    store.ledger.preferences.backgroundOpacity = GlassStyle.defaultOpacity
                    store.ledger.preferences.backgroundBlur = GlassStyle.defaultBlur
                    store.save()
                }
                .buttonStyle(.plain).font(AppTypography.small).foregroundStyle(store.accentColor)
            }
            glassSlider(L10n.text("Background opacity"), value: $store.ledger.preferences.backgroundOpacity)
            glassSlider(L10n.text("Blur"), value: $store.ledger.preferences.backgroundBlur)
            Text(L10n.text("Applies to the panel background."))
                .font(AppTypography.small).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func glassSlider(_ title: String, value: Binding<Double>) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title).font(AppTypography.detail)
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded()))%")
                    .font(AppTypography.small).monospacedDigit().foregroundStyle(.secondary)
            }
            AccentSlider(value: value, accessibilityTitle: title, onEditingChanged: { editing in if !editing { store.save() } })
        }
    }

    private var menuBarSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("MENU BAR")).font(AppTypography.section).foregroundStyle(.secondary)
            settingToggle(L10n.text("Show time"), symbol: "clock", binding: preference(\.showMenuBarTime))
            HStack {
                Text(L10n.text("Icon")).font(AppTypography.body).foregroundStyle(.secondary)
                Spacer()
                SelectionDropdown(selection: $store.ledger.preferences.menuBarIcon, options: MenuBarIcon.allCases, title: { $0.title }, accessibilityTitle: L10n.text("Menu bar icon"))
                    .frame(width: 140).onChange(of: store.ledger.preferences.menuBarIcon) { _, _ in store.save() }
            }
            Text(L10n.text("Show the timer during an active session.")).font(AppTypography.small).foregroundStyle(.tertiary)
        }
    }

    private var accentSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("ACCENT COLOR")).font(AppTypography.section).foregroundStyle(.secondary)
            HStack {
                Button {
                    store.ledger.preferences.accentChoice = .system
                    store.save()
                } label: {
                    Label(L10n.text("System"), systemImage: store.ledger.preferences.accentChoice == .system ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.plain).font(AppTypography.body)
                .foregroundStyle(store.ledger.preferences.accentChoice == .system ? store.accentColor : .secondary)
                Spacer()
                ColorPicker(L10n.text("Custom color"), selection: Binding(get: { store.accentColor }, set: { store.setCustomAccent($0) }), supportsOpacity: false)
                    .font(AppTypography.detail).fixedSize()
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
            Text(L10n.text("POMODORO")).font(AppTypography.section).foregroundStyle(.secondary)
            pomodoroStepper(L10n.text("Focus"), value: $store.ledger.preferences.pomodoro.focusMinutes, range: 1...120, suffix: L10n.text("min"))
            pomodoroStepper(L10n.text("Short break"), value: $store.ledger.preferences.pomodoro.shortBreakMinutes, range: 1...30, suffix: L10n.text("min"))
            pomodoroStepper(L10n.text("Long break"), value: $store.ledger.preferences.pomodoro.longBreakMinutes, range: 1...60, suffix: L10n.text("min"))
            pomodoroStepper(L10n.text("Until long break"), value: $store.ledger.preferences.pomodoro.roundsBeforeLongBreak, range: 2...8, suffix: L10n.text("sessions"))
            settingToggle(L10n.text("Auto-start breaks"), symbol: "cup.and.saucer", binding: Binding(get: { store.ledger.preferences.pomodoro.autoStartBreaks }, set: {
                store.ledger.preferences.pomodoro.autoStartBreaks = $0; store.save()
            }))
            settingToggle(L10n.text("Edge glow during breaks"), symbol: "light.beacon.min", binding: preference(\.breakEdgeGlowEnabled))
            if store.ledger.preferences.breakEdgeGlowEnabled { glowSettings }
            Text(L10n.text("Start each focus session manually. Breaks are excluded from work totals."))
                .font(AppTypography.small).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var glowSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            glowSlider(L10n.text("Width"), value: $store.ledger.preferences.glowWidth, range: 24...320, display: L10n.text("\(Int(store.ledger.preferences.glowWidth.rounded())) pt"))
            glowSlider(L10n.text("Intensity"), value: $store.ledger.preferences.glowIntensity, range: 0...1, display: "\(Int((store.ledger.preferences.glowIntensity * 100).rounded()))%")
            HStack {
                Button(store.isGlowPreviewing ? L10n.text("Stop Preview") : L10n.text("Preview Glow")) {
                    if store.isGlowPreviewing { store.stopGlowPreview() } else { store.showGlowPreview() }
                }.buttonStyle(.plain).font(AppTypography.detail).foregroundStyle(store.accentColor)
                Spacer()
                Button(L10n.text("Reset")) {
                    store.ledger.preferences.glowWidth = GlowStyle.defaultWidth
                    store.ledger.preferences.glowIntensity = GlowStyle.defaultIntensity
                    store.save()
                    store.showGlowPreview()
                }.buttonStyle(.plain).font(AppTypography.small).foregroundStyle(.secondary)
            }
        }.padding(.leading, 26)
    }

    private func glowSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, display: String) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title).font(AppTypography.detail)
                Spacer()
                Text(display).font(AppTypography.small).monospacedDigit().foregroundStyle(.secondary)
            }
            AccentSlider(value: value, range: range, accessibilityTitle: L10n.text("Glow: ") + title, onEditingChanged: { editing in
                store.showGlowPreview()
                if !editing { store.save() }
            })
        }
    }

    private var idleSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("IDLE DETECTION")).font(AppTypography.section).foregroundStyle(.secondary)
            settingToggle(L10n.text("Detect idle time"), symbol: "moon.zzz", binding: preference(\.idleCheckEnabled))
            HStack {
                Text(L10n.text("After")).font(AppTypography.detail)
                Spacer()
                SelectionDropdown(selection: $store.ledger.preferences.idleMinutes, options: [1, 3, 5, 10, 15, 30], title: { L10n.text("\($0) min") }, accessibilityTitle: L10n.text("Idle threshold"))
                    .frame(width: 110).disabled(!store.ledger.preferences.idleCheckEnabled)
                    .onChange(of: store.ledger.preferences.idleMinutes) { _, _ in store.save() }
            }
            Text(L10n.text("The timer pauses when you're idle. Choose whether that time counts when you return."))
                .font(AppTypography.small).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func pomodoroStepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, suffix: String) -> some View {
        HStack {
            Text(title).font(AppTypography.detail)
            Spacer(minLength: 4)
            Text("\(value.wrappedValue) \(suffix)").font(AppTypography.detail).monospacedDigit().foregroundStyle(.secondary)
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
            loginError = L10n.text("Move time_ to Applications and try again: \(error.localizedDescription)")
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
                                        Text(category.name).font(AppTypography.rowTitle).foregroundStyle(.primary)
                                        Text(category.dailyGoalMinutes == 0 ? L10n.text("Based on tasks") : TimeText.duration(Double(category.dailyGoalMinutes * 60)) + L10n.text(" per day"))
                                            .font(AppTypography.small).foregroundStyle(.secondary)
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
                } label: { Label(L10n.text("New Category"), systemImage: "plus") }.buttonStyle(PrimaryButton())
                let archived = store.ledger.categories.filter(\.isArchived)
                if !archived.isEmpty {
                    CategoryArchiveMenu(categories: archived)
                }
                Text(L10n.text("Set the goal to zero to use task estimates."))
                    .font(AppTypography.small).foregroundStyle(.secondary).lineSpacing(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text(L10n.text("Name")).font(AppTypography.detail).foregroundStyle(.secondary)
                TextField(L10n.text("For example, a project"), text: $name).textFieldStyle(.roundedBorder)
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
                Text(L10n.text("Daily goal")).font(AppTypography.body).foregroundStyle(.secondary)
                Spacer()
                TextField(L10n.text("Minutes"), value: $goal, format: .number).textFieldStyle(.roundedBorder).frame(width: 55)
                Text(L10n.text("min")).font(AppTypography.detail).foregroundStyle(.secondary)
                Stepper(L10n.text("Daily goal"), value: $goal, in: 0...1440, step: 15).labelsHidden()
            }
            Text(L10n.text("Zero uses task estimates.")).font(AppTypography.small).foregroundStyle(.tertiary)
            Button(editingID == nil ? L10n.text("Create Category") : L10n.text("Save")) {
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
                Button(L10n.text("Back")) { isEditing = false }.font(AppTypography.detail)
                Spacer()
                if let id = editingID {
                    Button(L10n.text("Archive")) { store.archiveCategory(id); isEditing = false }
                        .font(AppTypography.detail).foregroundStyle(.secondary)
                        .disabled(store.categories.count <= 1 || store.active?.categoryID == id)
                }
            }
        }
    }

    private func colorName(_ color: CategoryColor) -> String {
        switch color {
        case .mint: return L10n.text("Mint")
        case .blue: return L10n.text("Light blue")
        case .lavender: return L10n.text("Lavender")
        case .peach: return L10n.text("Peach")
        case .rose: return L10n.text("Pink")
        case .yellow: return L10n.text("Yellow")
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
                Text(L10n.text("Archive · \(categories.count)")).font(AppTypography.detail)
                Spacer()
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(store.accentColor)
            .padding(.horizontal, 10).frame(height: 31)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain).accessibilityLabel(L10n.text("Archived categories: \(categories.count)"))
        .popover(isPresented: $expanded, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 7) {
                Text(L10n.text("ARCHIVED CATEGORIES")).font(AppTypography.section).foregroundStyle(.secondary)
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
                                    Text(category.name).font(AppTypography.body).lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "arrow.uturn.backward").font(.system(size: 10))
                                        .foregroundStyle(store.accentColor)
                                }
                                .foregroundStyle(.primary).padding(.horizontal, 9).frame(minHeight: 32)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).accessibilityLabel(L10n.text("Restore \(category.name)"))
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
