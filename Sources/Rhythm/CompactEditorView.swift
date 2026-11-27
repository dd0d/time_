import SwiftUI
import RhythmCore

private struct CompactEditorHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct CompactEditorView: View {
    @EnvironmentObject var store: AppStore
    let editor: CompactEditor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle().fill(.primary.opacity(0.08)).frame(height: 0.5)
            HStack {
                Text(editor == .details ? L10n.text("Task") : L10n.text("Mode and time")).font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(action: finishEditing) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(L10n.text("Close editor"))
            }
            if editor == .details { details } else { timer }
            Button(action: finishEditing) {
                Text(L10n.text("Done")).font(AppTypography.rowTitle).frame(maxWidth: .infinity).frame(height: 29)
                    .background(.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(RoundedRectangle(cornerRadius: 7))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.top, 2).padding(.bottom, 14)
        .frame(width: RootView.compactSize.width).fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { proxy in Color.clear.preference(key: CompactEditorHeight.self, value: proxy.size.height) })
        .onPreferenceChange(CompactEditorHeight.self) { height in
            Task { @MainActor in store.updateCompactEditorHeight(height) }
        }
        .onDisappear { saveChanges() }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                caption(L10n.text("Name"))
                TextField(L10n.text("Optional"), text: $store.title).textFieldStyle(.plain).font(AppTypography.body)
                    .padding(.horizontal, 9).frame(height: 32).fieldSurface()
                    .accessibilityLabel(L10n.text("Task name in compact panel")).onSubmit(finishEditing)
            }
            VStack(alignment: .leading, spacing: 6) {
                caption(L10n.text("Category"))
                CategoryPicker(selection: Binding(get: { store.currentCategoryID }, set: { store.selectCategoryQuickly($0) }), showsProgress: true)
            }
            Button { store.compactEditor = .timer } label: {
                HStack {
                    Text(L10n.text("Mode")).foregroundStyle(.secondary)
                    Spacer()
                    Text(store.mode.title)
                    Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.secondary)
                }.font(.system(size: 11)).frame(height: 25).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }

    private var timer: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSegments(selection: $store.mode, options: TrackingMode.allCases, title: { $0.title })
                .disabled(store.active != nil).accessibilityLabel(L10n.text("Mode in compact panel"))
            if let active = store.active {
                Text(active.isBreak ? L10n.text("On a break. Start the next focus session when ready.") : L10n.text("Finish the session to change modes."))
                    .font(AppTypography.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    if active.mode == .countdown { Button(L10n.text("+ 5 min")) { store.extendTimer() }.buttonStyle(.plain).foregroundStyle(store.accentColor) }
                    Spacer()
                    Button(active.isBreak ? L10n.text("End Break") : L10n.text("End Session")) { store.finish() }
                        .buttonStyle(.plain).foregroundStyle(store.accentColor)
                }.font(AppTypography.detail).frame(height: 25)
            } else if store.mode == .countdown {
                HStack(spacing: 6) {
                    ForEach([15, 25, 45], id: \.self) { minutes in
                        Button { store.minutes = minutes } label: {
                            Text(L10n.text("\(minutes) min")).font(AppTypography.detail).frame(maxWidth: .infinity).frame(height: 29)
                                .foregroundStyle(store.minutes == minutes ? store.accentColor : .primary)
                                .background(store.minutes == minutes ? store.accentColor.opacity(0.12) : .primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain)
                    }
                }
                HStack(spacing: 8) {
                    Text(L10n.text("Minutes")).font(AppTypography.detail).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    adjustmentButton("minus") { store.minutes = max(1, min(480, max(1, store.minutes)) - 1) }
                    TextField(L10n.text("Minutes"), value: $store.minutes, format: .number).textFieldStyle(.plain)
                        .font(AppTypography.rowTitle).monospacedDigit().multilineTextAlignment(.center)
                        .frame(width: 40, height: 31).fieldSurface()
                    adjustmentButton("plus") { store.minutes = min(480, min(480, max(1, store.minutes)) + 1) }
                }
            } else if store.mode == .pomodoro {
                HStack(alignment: .top, spacing: 8) {
                    phaseField(L10n.text("Focus"), value: $store.ledger.preferences.pomodoro.focusMinutes, range: 1...120)
                    phaseField(L10n.text("Break"), value: $store.ledger.preferences.pomodoro.shortBreakMinutes, range: 1...30)
                    phaseField(L10n.text("Long"), value: $store.ledger.preferences.pomodoro.longBreakMinutes, range: 1...60)
                }
                HStack {
                    Text(L10n.text("Auto-start breaks")).font(AppTypography.detail)
                    Spacer(minLength: 4)
                    Toggle(L10n.text("Auto-start breaks"), isOn: $store.ledger.preferences.pomodoro.autoStartBreaks).labelsHidden().toggleStyle(AccentSwitchStyle())
                }.frame(height: 24)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(L10n.text("Long break after \(store.ledger.preferences.pomodoro.roundsBeforeLongBreak) sessions"))
                        .font(AppTypography.small).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button(L10n.text("More")) { store.page = .settings }.font(AppTypography.detail).buttonStyle(.plain).foregroundStyle(store.accentColor)
                }
            } else {
                Text(L10n.text("Tracks elapsed time. A task name is optional."))
                    .font(AppTypography.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func caption(_ title: String) -> some View { Text(title).font(AppTypography.small).foregroundStyle(.secondary) }

    private func adjustmentButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .medium)).frame(width: 27, height: 29)
                .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).accessibilityLabel(symbol == "plus" ? L10n.text("Increase duration") : L10n.text("Decrease duration"))
    }

    private func phaseField(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            caption(title)
            TextField(L10n.text("min"), value: value, format: .number).textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium)).monospacedDigit().multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).frame(height: 32).fieldSurface()
                .accessibilityLabel(title + L10n.text(", minutes"))
                .onChange(of: value.wrappedValue) { _, new in value.wrappedValue = min(range.upperBound, max(range.lowerBound, new)) }
        }.frame(maxWidth: .infinity)
    }

    private func saveChanges() {
        if editor == .details { store.updateSessionDetails(title: store.title, categoryID: store.currentCategoryID) }
        else { store.saveTimerPreferences() }
    }

    private func finishEditing() { saveChanges(); store.compactEditor = nil }
}

private extension View {
    func fieldSurface() -> some View {
        background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.1), lineWidth: 0.7))
    }
}
