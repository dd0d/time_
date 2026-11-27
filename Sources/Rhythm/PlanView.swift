import SwiftUI
import RhythmCore

struct PlanView: View {
    @EnvironmentObject var store: AppStore
    @State private var showEditor = false
    @State private var editingTask: PlanTask?
    @State private var deletingTask: PlanTask?
    @State private var showCompleted = false

    private var planned: Int { store.dayTasks.reduce(0) { $0 + $1.plannedMinutes } }
    private var finishedCount: Int { store.dayTasks.filter { $0.completedAt != nil }.count }
    private var pendingTasks: [PlanTask] { store.dayTasks.filter { $0.completedAt == nil } }
    private var completedTasks: [PlanTask] { store.dayTasks.filter { $0.completedAt != nil } }

    var body: some View {
        Group {
            if showEditor {
                TaskEditor(task: editingTask) { showEditor = false }
            } else {
                planContent
            }
        }
        .alert(deletingTask?.dailyScheduleID != nil ? L10n.text("Delete recurring task?") : L10n.text("Delete task?"), isPresented: Binding(get: { deletingTask != nil }, set: { if !$0 { deletingTask = nil } })) {
            Button(L10n.text("Cancel"), role: .cancel) { deletingTask = nil }
            Button(L10n.text("Delete"), role: .destructive) { if let task = deletingTask { store.deleteTask(task.id) }; deletingTask = nil }
        } message: {
            Text(deletingTask?.dailyScheduleID != nil
                 ? L10n.text("This removes the task from the selected day onward. Past days and tracked time are kept.")
                 : L10n.text("Tracked time stays in History."))
        }
        .onChange(of: store.selectedDay) { _, _ in showCompleted = false }
    }

    private var planContent: some View {
        VStack(spacing: 18) {
            DayNavigation(allowsFuture: true)
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.text("Daily plan")).font(AppTypography.detail).foregroundStyle(.secondary)
                    Text(planned > 0 ? TimeText.duration(Double(planned * 60)) : (store.dayTasks.isEmpty ? L10n.text("0 min") : L10n.text("No goal")))
                        .timeDisplay(size: AppTypography.totalSize)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(L10n.text("Completed")).font(AppTypography.detail).foregroundStyle(.secondary)
                    Text("\(finishedCount) / \(store.dayTasks.count)").timeDisplay(size: AppTypography.metricSize)
                }
            }
            .cardSurface(padding: 17)

            VStack(spacing: 12) {
                HStack {
                    SectionCaption(title: L10n.text("TASKS"))
                    Button {
                        editingTask = nil
                        showEditor = true
                    } label: {
                        HStack(spacing: 4) { Image(systemName: "plus"); Text(L10n.text("Add")) }
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain).keyboardShortcut("n", modifiers: .command)
                }

                if store.dayTasks.isEmpty {
                    VStack(spacing: 3) {
                        EmptyNote(symbol: "checklist", title: L10n.text("No tasks"), subtitle: L10n.text("Time goals are optional."))
                        Button { editingTask = nil; showEditor = true } label: { Label(L10n.text("Add Task"), systemImage: "plus") }
                            .buttonStyle(PrimaryButton()).padding(.horizontal, 18).padding(.bottom, 18)
                    }
                    .cardSurface(padding: 0)
                } else {
                    taskList(pendingTasks)
                    if !completedTasks.isEmpty {
                        VStack(spacing: 10) {
                            Button { showCompleted.toggle() } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                                        .rotationEffect(.degrees(showCompleted ? 90 : 0)).foregroundStyle(store.accentColor)
                                    Text(L10n.text("Completed · \(completedTasks.count)")).font(AppTypography.detail)
                                    Spacer()
                                }
                                .foregroundStyle(.secondary).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(showCompleted ? L10n.text("Hide completed tasks") : L10n.text("Show completed tasks"))
                            if showCompleted { taskList(completedTasks) }
                        }
                    }
                }
            }

            let plannedCategories = store.categories.filter { store.ledger.plannedMinutes(for: $0.id, on: store.selectedDay) > 0 }
            if !plannedCategories.isEmpty {
                VStack(spacing: 13) {
                    SectionCaption(title: L10n.text("BY CATEGORY"))
                    ForEach(plannedCategories) { category in CategoryProgress(category: category, day: store.selectedDay) }
                }
                .padding(.top, 2)
            }
        }
    }

    private func taskList(_ tasks: [PlanTask]) -> some View {
        VStack(spacing: 7) {
            ForEach(tasks) { task in
                taskRow(task)
                    .contextMenu {
                        Button(L10n.text("Edit…"), systemImage: "pencil") { editingTask = task; showEditor = true }
                        if !store.isToday && task.completedAt == nil && task.dailyScheduleID == nil {
                            Button(L10n.text("Move to Today"), systemImage: "arrow.right") { store.moveTaskToToday(task.id) }
                        }
                        Divider()
                        Button(L10n.text("Delete Task…"), systemImage: "trash", role: .destructive) { deletingTask = task }
                    }
            }
        }
    }

    private func taskRow(_ task: PlanTask) -> some View {
        let completed = task.completedAt != nil
        let tracked = store.ledger.tracked(for: task, at: store.now)
        let isActive = store.isActiveTask(task)
        return HStack(spacing: 10) {
            Button { store.toggleTask(task.id) } label: {
                Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(completed ? store.accentColor : .secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel((completed ? L10n.text("Mark incomplete: ") : L10n.text("Complete task: ")) + task.title)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Text(task.title).font(AppTypography.rowTitle).strikethrough(completed).foregroundStyle(completed ? .secondary : .primary).lineLimit(2)
                    if task.dailyScheduleID != nil {
                        Image(systemName: "repeat").font(.system(size: 9)).foregroundStyle(.secondary).help(L10n.text("Daily task"))
                    }
                }
                HStack(spacing: 5) {
                    Circle().fill(store.ledger.category(task.categoryID)?.color.tint ?? store.accentColor).frame(width: 5, height: 5)
                    Text(store.ledger.category(task.categoryID)?.name ?? L10n.text("Category")).lineLimit(1)
                    Text("·")
                    Text(task.plannedMinutes > 0
                         ? (tracked > 0 ? TimeText.duration(tracked) + " / " + TimeText.duration(Double(task.plannedMinutes * 60)) : TimeText.duration(Double(task.plannedMinutes * 60)))
                         : (tracked > 0 ? TimeText.duration(tracked) : L10n.text("No time goal")))
                        .monospacedDigit().lineLimit(1)
                }
                .font(AppTypography.detail).foregroundStyle(.secondary)
            }
            Spacer(minLength: 1)
            if !completed {
                QuietIconButton(symbol: isActive ? "waveform" : "play.fill", help: isActive ? L10n.text("Open current session") : L10n.text("Start task")) {
                    if isActive { store.page = .focus }
                    else { store.useTask(task, startImmediately: true) }
                }
                .disabled(store.active != nil && !isActive)
                .opacity(store.active != nil && !isActive ? 0.3 : 1)
            }
        }
        .cardSurface(padding: 12)
    }
}

struct TaskEditor: View {
    @EnvironmentObject var store: AppStore
    let task: PlanTask?
    let close: () -> Void
    @State private var title = ""
    @State private var categoryID = UUID()
    @State private var minutes = 25
    @State private var day = Date()
    @State private var isDaily = false
    @State private var hasTimeGoal = true
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            EditorHeader(title: task == nil ? L10n.text("New Task") : L10n.text("Edit Task"), close: close)
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("What do you need to do?")).font(AppTypography.detail).foregroundStyle(.secondary)
                TextField(L10n.text("Task name"), text: $title).textFieldStyle(.roundedBorder).focused($titleFocused)
                    .onSubmit { commit() }
            }
            HStack {
                Text(L10n.text("Category")).font(AppTypography.body).foregroundStyle(.secondary)
                Spacer()
                CategoryPicker(selection: $categoryID, allowsManagement: false)
            }
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Toggle(L10n.text("Time goal"), isOn: $hasTimeGoal).toggleStyle(AccentCheckboxStyle())
                    Spacer()
                    if hasTimeGoal {
                        TextField(L10n.text("Minutes"), value: $minutes, format: .number).textFieldStyle(.roundedBorder).frame(width: 50)
                        Text(L10n.text("min")).font(AppTypography.detail).foregroundStyle(.secondary)
                        Stepper(L10n.text("Minutes"), value: $minutes, in: 1...480, step: 5).labelsHidden()
                    }
                }
                if !hasTimeGoal {
                    Text(L10n.text("▶ starts a stopwatch."))
                        .font(AppTypography.small).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).lineSpacing(2)
                }
            }
            DatePicker(task?.dailyScheduleID != nil && isDaily ? L10n.text("Task date") : (isDaily ? L10n.text("Starts on") : L10n.text("Date")), selection: $day, displayedComponents: .date)
                .font(AppTypography.body).disabled(task?.dailyScheduleID != nil && isDaily)
            VStack(alignment: .leading, spacing: 7) {
                Toggle(L10n.text("Repeat daily"), isOn: $isDaily).toggleStyle(AccentCheckboxStyle())
                Text(isDaily
                     ? (task?.dailyScheduleID != nil ? L10n.text("Changes apply from this day onward. Each day has its own progress.") : L10n.text("Repeats every day from the selected date."))
                     : (task?.dailyScheduleID != nil ? L10n.text("Future repeats stop. The task stays on the selected day.") : L10n.text("This is a one-time task.")))
                    .font(AppTypography.small).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).lineSpacing(2)
            }
            Button(task == nil ? L10n.text("Add to Plan") : L10n.text("Save")) { commit() }
                .buttonStyle(PrimaryButton()).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            title = task?.title ?? ""
            categoryID = task?.categoryID ?? store.selectedCategoryID
            minutes = task.flatMap { $0.plannedMinutes > 0 ? $0.plannedMinutes : nil } ?? 25
            hasTimeGoal = task.map { $0.plannedMinutes > 0 } ?? true
            day = task?.day ?? store.selectedDay
            isDaily = task?.dailyScheduleID != nil
            titleFocused = true
        }
        .onChange(of: isDaily) { _, enabled in
            if enabled, let task, task.dailyScheduleID != nil { day = task.day }
        }
    }

    private func commit() {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if var task {
            task.title = String(clean.prefix(240))
            task.categoryID = categoryID
            task.plannedMinutes = hasTimeGoal ? max(1, min(480, minutes)) : 0
            task.day = Calendar.current.startOfDay(for: day)
            store.updateTask(task, isDaily: isDaily)
        } else { store.addTask(title: clean, categoryID: categoryID, minutes: hasTimeGoal ? max(1, min(480, minutes)) : 0, day: day, isDaily: isDaily) }
        store.selectedDay = Calendar.current.startOfDay(for: day)
        close()
    }
}

struct EditorHeader: View {
    let title: String
    var close: () -> Void
    var body: some View {
        HStack {
            Text(title).font(AppTypography.editorTitle)
            Spacer()
            QuietIconButton(symbol: "xmark", help: L10n.text("Close"), action: close)
        }
    }
}
