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
        .alert(deletingTask?.dailyScheduleID != nil ? "Удалить ежедневную задачу?" : "Удалить задачу?", isPresented: Binding(get: { deletingTask != nil }, set: { if !$0 { deletingTask = nil } })) {
            Button("Отмена", role: .cancel) { deletingTask = nil }
            Button("Удалить", role: .destructive) { if let task = deletingTask { store.deleteTask(task.id) }; deletingTask = nil }
        } message: {
            Text(deletingTask?.dailyScheduleID != nil
                 ? "Задача и её повторы исчезнут с выбранного дня. Предыдущие дни и записанное время останутся."
                 : "Записанное время останется в истории.")
        }
        .onChange(of: store.selectedDay) { _, _ in showCompleted = false }
    }

    private var planContent: some View {
        VStack(spacing: 18) {
            DayNavigation(allowsFuture: true)
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("План на день").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(planned > 0 ? TimeText.duration(Double(planned * 60)) : (store.dayTasks.isEmpty ? "0 мин" : "Без цели"))
                        .font(.system(size: 27, weight: .light)).monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text("Выполнено").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("\(finishedCount) / \(store.dayTasks.count)").font(.system(size: 19, weight: .light)).monospacedDigit()
                }
            }
            .cardSurface(padding: 17)

            VStack(spacing: 12) {
                HStack {
                    SectionCaption(title: "ЗАДАЧИ")
                    Button {
                        editingTask = nil
                        showEditor = true
                    } label: {
                        HStack(spacing: 4) { Image(systemName: "plus"); Text("Добавить") }
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain).keyboardShortcut("n", modifiers: .command)
                }

                if store.dayTasks.isEmpty {
                    VStack(spacing: 3) {
                        EmptyNote(symbol: "checklist", title: "Нет задач", subtitle: "Цель по времени необязательна.")
                        Button { editingTask = nil; showEditor = true } label: { Label("Добавить задачу", systemImage: "plus") }
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
                                    Text("Выполнено · \(completedTasks.count)").font(.system(size: 11))
                                    Spacer()
                                }
                                .foregroundStyle(.secondary).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(showCompleted ? "Скрыть выполненные задачи" : "Показать выполненные задачи")
                            if showCompleted { taskList(completedTasks) }
                        }
                    }
                }
            }

            let plannedCategories = store.categories.filter { store.ledger.plannedMinutes(for: $0.id, on: store.selectedDay) > 0 }
            if !plannedCategories.isEmpty {
                VStack(spacing: 13) {
                    SectionCaption(title: "ПО КАТЕГОРИЯМ")
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
                        Button("Редактировать…", systemImage: "pencil") { editingTask = task; showEditor = true }
                        if !store.isToday && task.completedAt == nil && task.dailyScheduleID == nil {
                            Button("Перенести на сегодня", systemImage: "arrow.right") { store.moveTaskToToday(task.id) }
                        }
                        Divider()
                        Button("Удалить задачу…", systemImage: "trash", role: .destructive) { deletingTask = task }
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
            .accessibilityLabel((completed ? "Вернуть в план: " : "Завершить задачу: ") + task.title)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Text(task.title).font(.system(size: 12, weight: .medium)).strikethrough(completed).foregroundStyle(completed ? .secondary : .primary).lineLimit(2)
                    if task.dailyScheduleID != nil {
                        Image(systemName: "repeat").font(.system(size: 9)).foregroundStyle(.secondary).help("Ежедневная задача")
                    }
                }
                HStack(spacing: 5) {
                    Circle().fill(store.ledger.category(task.categoryID)?.color.tint ?? store.accentColor).frame(width: 5, height: 5)
                    Text(store.ledger.category(task.categoryID)?.name ?? "Категория").lineLimit(1)
                    Text("·")
                    Text(task.plannedMinutes > 0
                         ? (tracked > 0 ? TimeText.duration(tracked) + " / " + TimeText.duration(Double(task.plannedMinutes * 60)) : TimeText.duration(Double(task.plannedMinutes * 60)))
                         : (tracked > 0 ? TimeText.duration(tracked) : "Без цели по времени"))
                        .monospacedDigit().lineLimit(1)
                }
                .font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 1)
            if !completed {
                QuietIconButton(symbol: isActive ? "waveform" : "play.fill", help: isActive ? "Открыть текущую сессию" : "Начать задачу") {
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
            EditorHeader(title: task == nil ? "Новая задача" : "Редактировать задачу", close: close)
            VStack(alignment: .leading, spacing: 8) {
                Text("Что нужно сделать").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("Название задачи", text: $title).textFieldStyle(.roundedBorder).focused($titleFocused)
                    .onSubmit { commit() }
            }
            HStack {
                Text("Категория").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                CategoryPicker(selection: $categoryID, allowsManagement: false)
            }
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Toggle("Цель по времени", isOn: $hasTimeGoal).toggleStyle(AccentCheckboxStyle())
                    Spacer()
                    if hasTimeGoal {
                        TextField("Минуты", value: $minutes, format: .number).textFieldStyle(.roundedBorder).frame(width: 50)
                        Text("мин").font(.system(size: 11)).foregroundStyle(.secondary)
                        Stepper("Минуты", value: $minutes, in: 1...480, step: 5).labelsHidden()
                    }
                }
                if !hasTimeGoal {
                    Text("Кнопка ▶ запускает секундомер.")
                        .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).lineSpacing(2)
                }
            }
            DatePicker(task?.dailyScheduleID != nil && isDaily ? "День задачи" : (isDaily ? "Начиная с" : "На какой день"), selection: $day, displayedComponents: .date)
                .font(.system(size: 12)).disabled(task?.dailyScheduleID != nil && isDaily)
            VStack(alignment: .leading, spacing: 7) {
                Toggle("Ежедневная", isOn: $isDaily).toggleStyle(AccentCheckboxStyle())
                Text(isDaily
                     ? (task?.dailyScheduleID != nil ? "Изменения применятся к этому и следующим дням. Выполнение и время учитываются отдельно за каждый день." : "С выбранной даты задача появляется каждый день с новым прогрессом.")
                     : (task?.dailyScheduleID != nil ? "Дальнейшие повторы прекратятся. Задача останется только на выбранный день." : "Один раз. После выполнения задача больше не повторяется."))
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).lineSpacing(2)
            }
            Button(task == nil ? "Добавить в план" : "Сохранить") { commit() }
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
            Text(title).font(.system(size: 16, weight: .semibold))
            Spacer()
            QuietIconButton(symbol: "xmark", help: "Закрыть", action: close)
        }
    }
}
