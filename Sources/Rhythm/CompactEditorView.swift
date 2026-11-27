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
                Text(editor == .details ? "Task" : "Mode and time").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(action: finishEditing) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Close editor")
            }
            if editor == .details { details } else { timer }
            Button(action: finishEditing) {
                Text("Done").font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity).frame(height: 29)
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
                caption("Name")
                TextField("Optional", text: $store.title).textFieldStyle(.plain).font(.system(size: 12))
                    .padding(.horizontal, 9).frame(height: 32).fieldSurface()
                    .accessibilityLabel("Task name in compact panel").onSubmit(finishEditing)
            }
            VStack(alignment: .leading, spacing: 6) {
                caption("Category")
                CategoryPicker(selection: Binding(get: { store.currentCategoryID }, set: { store.selectCategoryQuickly($0) }), showsProgress: true)
            }
            Button { store.compactEditor = .timer } label: {
                HStack {
                    Text("Mode").foregroundStyle(.secondary)
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
                .disabled(store.active != nil).accessibilityLabel("Mode in compact panel")
            if let active = store.active {
                Text(active.isBreak ? "On a break. Start the next focus session when ready." : "Finish the session to change modes.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    if active.mode == .countdown { Button("+ 5 min") { store.extendTimer() }.buttonStyle(.plain).foregroundStyle(store.accentColor) }
                    Spacer()
                    Button(active.isBreak ? "End Break" : "End Session") { store.finish() }
                        .buttonStyle(.plain).foregroundStyle(store.accentColor)
                }.font(.system(size: 11)).frame(height: 25)
            } else if store.mode == .countdown {
                HStack(spacing: 6) {
                    ForEach([15, 25, 45], id: \.self) { minutes in
                        Button { store.minutes = minutes } label: {
                            Text("\(minutes) min").font(.system(size: 11)).frame(maxWidth: .infinity).frame(height: 29)
                                .foregroundStyle(store.minutes == minutes ? store.accentColor : .primary)
                                .background(store.minutes == minutes ? store.accentColor.opacity(0.12) : .primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain)
                    }
                }
                HStack(spacing: 8) {
                    Text("Minutes").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    adjustmentButton("minus") { store.minutes = max(1, min(480, max(1, store.minutes)) - 1) }
                    TextField("Minutes", value: $store.minutes, format: .number).textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium)).monospacedDigit().multilineTextAlignment(.center)
                        .frame(width: 40, height: 31).fieldSurface()
                    adjustmentButton("plus") { store.minutes = min(480, min(480, max(1, store.minutes)) + 1) }
                }
            } else if store.mode == .pomodoro {
                HStack(alignment: .top, spacing: 8) {
                    phaseField("Focus", value: $store.ledger.preferences.pomodoro.focusMinutes, range: 1...120)
                    phaseField("Break", value: $store.ledger.preferences.pomodoro.shortBreakMinutes, range: 1...30)
                    phaseField("Long", value: $store.ledger.preferences.pomodoro.longBreakMinutes, range: 1...60)
                }
                HStack {
                    Text("Auto-start breaks").font(.system(size: 11))
                    Spacer(minLength: 4)
                    Toggle("Auto-start breaks", isOn: $store.ledger.preferences.pomodoro.autoStartBreaks).labelsHidden().toggleStyle(AccentSwitchStyle())
                }.frame(height: 24)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Long break after \(store.ledger.preferences.pomodoro.roundsBeforeLongBreak) sessions")
                        .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("More") { store.page = .settings }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(store.accentColor)
                }
            } else {
                Text("Tracks elapsed time. A task name is optional.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func caption(_ title: String) -> some View { Text(title).font(.system(size: 10)).foregroundStyle(.secondary) }

    private func adjustmentButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .medium)).frame(width: 27, height: 29)
                .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).accessibilityLabel(symbol == "plus" ? "Increase duration" : "Decrease duration")
    }

    private func phaseField(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            caption(title)
            TextField("min", value: value, format: .number).textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium)).monospacedDigit().multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).frame(height: 32).fieldSurface()
                .accessibilityLabel(title + ", minutes")
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
