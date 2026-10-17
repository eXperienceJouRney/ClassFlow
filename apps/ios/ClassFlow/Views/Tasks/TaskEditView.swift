import SwiftUI

/// 待办表单：新建或编辑一条待办。
struct TaskEditView: View {

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let task: CourseTask?
    private let presetCourseId: UUID?

    @State private var title: String
    @State private var courseId: UUID?
    @State private var dueDate: CalendarDate?
    @State private var dueTime: TimeOfDay?
    @State private var note: String

    @State private var dateDraft: Date
    @State private var timeDraft: Date
    @State private var showsDatePicker = false
    @State private var showsTimePicker = false
    @State private var errorMessage: String?

    init(task: CourseTask?, presetCourseId: UUID? = nil) {
        self.task = task
        self.presetCourseId = presetCourseId

        _title = State(initialValue: task?.title ?? "")
        _courseId = State(initialValue: task?.courseId ?? presetCourseId)
        _dueDate = State(initialValue: task?.dueDate)
        _dueTime = State(initialValue: task?.dueTime)
        _note = State(initialValue: task?.note ?? "")

        _dateDraft = State(initialValue: task?.dueDate?.startOfDay() ?? Date())
        let defaultTime = TimeOfDay(hour: 18, minute: 0) ?? TimeOfDay(hour: 0, minute: 0)!
        _timeDraft = State(initialValue: task?.dueTime?.dateValue() ?? defaultTime.dateValue())
    }

    var body: some View {
        NavigationStack {
            Form {
                titleSection
                courseSection
                dueDateSection
                dueTimeSection
                noteSection

                if let task, task.status.isTerminal {
                    Section("状态") {
                        LabeledContent("当前状态", value: task.status.displayName)
                        Button("重新打开") { reopen() }
                    }
                }

                Section {
                    Button("保存") { save() }
                        .buttonStyle(PrimaryActionButtonStyle(isEnabled: !title.isBlank))
                        .disabled(title.isBlank)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle(task == nil ? "添加待办" : "编辑待办")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .sheet(isPresented: $showsDatePicker) { datePickerSheet }
            .sheet(isPresented: $showsTimePicker) { timePickerSheet }
            .errorAlert($errorMessage)
        }
    }
}

// MARK: - 表单区块

extension TaskEditView {

    private var titleSection: some View {
        Section {
            TextField("准备做什么？", text: $title, axis: .vertical)
        } header: {
            Text("标题")
        }
    }

    private var courseSection: some View {
        Section {
            Picker(selection: $courseId) {
                Text("未关联课程").tag(UUID?.none)
                ForEach(availableCourses) { course in
                    Text(course.name).tag(UUID?.some(course.id))
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.navigationLink)
        } header: {
            Text("课程")
        } footer: {
            Text(courseId == nil ? "未关联课程" : "自动关联至当前课程")
        }
    }

    private var dueDateSection: some View {
        Section {
            HStack(spacing: 8) {
                QuickChip(title: "今天", isSelected: isSelected(daysFromToday: 0)) {
                    selectDueDate(daysFromToday: 0)
                }
                QuickChip(title: "明天", isSelected: isSelected(daysFromToday: 1)) {
                    selectDueDate(daysFromToday: 1)
                }
                QuickChip(title: "选择日期") {
                    openDatePicker()
                }
                Spacer(minLength: 0)
            }

            if let dueDate {
                HStack {
                    Text(dueDate.weekdayMonthDayText())
                    Spacer()
                    Button("清除") { clearDueDate() }
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("不设截止日期和时间")
                    .foregroundStyle(.secondary)
            }
        } header: {
            FormSectionTitle(title: "截止日期", isOptional: true)
        }
    }

    private var dueTimeSection: some View {
        Section {
            if let dueTime {
                HStack {
                    Text(dueTime.displayText(format: store.preferences.timeFormat))
                    Spacer()
                    Button("清除") { self.dueTime = nil }
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("选择时间（需先选择日期）") { openTimePicker() }
                    .disabled(dueDate == nil)
                    .foregroundStyle(dueDate == nil ? Color.secondary : Color.primary)
            }
        } header: {
            FormSectionTitle(title: "截止时间", isOptional: true)
        }
    }

    private var noteSection: some View {
        Section {
            TextField("添加备注⋯", text: $note, axis: .vertical)
                .lineLimit(3...6)
        } header: {
            FormSectionTitle(title: "备注", isOptional: true)
        }
    }
}

// MARK: - 日期 / 时间选择 sheet

extension TaskEditView {

    private var datePickerSheet: some View {
        NavigationStack {
            DatePicker("截止日期", selection: $dateDraft, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding()
                .navigationTitle("截止日期")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showsDatePicker = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            dueDate = CalendarDate(date: dateDraft)
                            showsDatePicker = false
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }

    private var timePickerSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DatePicker("截止时间", selection: $timeDraft, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()

                Button("不设置具体时间") {
                    dueTime = nil
                    showsTimePicker = false
                }
                .font(DesignTokens.Typography.body)
                .foregroundStyle(.secondary)
                .padding(.vertical, 12)
            }
            .navigationTitle("截止时间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showsTimePicker = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dueTime = TimeOfDay.from(timeDraft)
                        showsTimePicker = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - 状态与保存

extension TaskEditView {

    private var availableCourses: [Course] {
        if let semesterId = store.currentSemester?.id {
            return store.courses(in: semesterId)
        }
        return store.data.courses.sorted { $0.name < $1.name }
    }

    private func isSelected(daysFromToday offset: Int) -> Bool {
        guard let dueDate else { return false }
        return dueDate == CalendarDate.today().adding(days: offset)
    }

    private func selectDueDate(daysFromToday offset: Int) {
        guard let date = CalendarDate.today().adding(days: offset) else { return }
        dueDate = date
    }

    private func openDatePicker() {
        dateDraft = dueDate?.startOfDay() ?? Date()
        showsDatePicker = true
    }

    private func openTimePicker() {
        guard dueDate != nil else { return }
        if let dueTime {
            timeDraft = dueTime.dateValue()
        }
        showsTimePicker = true
    }

    /// 清除日期会同时清除时间（模型不允许只有时间的截止状态）。
    private func clearDueDate() {
        dueDate = nil
        dueTime = nil
    }

    private func save() {
        let noteValue = note.normalizedOrNil

        do {
            if let task {
                try store.updateTask(
                    id: task.id,
                    title: title,
                    courseId: courseId,
                    dueDate: dueDate,
                    dueTime: dueTime,
                    note: noteValue
                )
            } else {
                try store.createTask(
                    title: title,
                    courseId: courseId,
                    dueDate: dueDate,
                    dueTime: dueTime,
                    note: noteValue
                )
            }
            dismiss()
        } catch {
            errorMessage = error.userMessage
        }
    }

    private func reopen() {
        guard let task else { return }
        do {
            try store.reopenTask(id: task.id)
            dismiss()
        } catch {
            errorMessage = error.userMessage
        }
    }
}

#Preview("添加待办") {
    TaskEditView(task: nil)
        .environment(PreviewSupport.store)
}

#Preview("添加待办 · 从课程进入") {
    let seed = PreviewSupport.seed

    TaskEditView(task: nil, presetCourseId: seed.math.id)
        .environment(seed.store)
}

#Preview("编辑待办") {
    let seed = PreviewSupport.seed

    TaskEditView(task: seed.task)
        .environment(seed.store)
}

#Preview("编辑待办 · 已完成") {
    let seed = PreviewSupport.seed

    TaskEditView(task: seed.completedTask)
        .environment(seed.store)
}
