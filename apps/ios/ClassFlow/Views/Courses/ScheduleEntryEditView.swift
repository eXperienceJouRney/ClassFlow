import SwiftUI

/// 上课安排编辑：星期、起止节次（或自定时间）、上课周次与本次上课教室（选填）。
struct ScheduleEntryEditView: View {

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let semester: Semester
    let courseName: String
    let initial: ScheduleEntryInput?
    var onSave: (ScheduleEntryInput) -> Void
    var onDelete: (() -> Void)?

    @State private var weekday: Weekday
    @State private var entryLocation: String
    @State private var usesPeriod: Bool
    @State private var startPeriod: Int
    @State private var endPeriod: Int
    @State private var startTime: Date
    @State private var endTime: Date
    /// 实际上课周次；保存时由 `WeekRule.compact` 折叠为规则。
    @State private var selectedWeeks: Set<Int>
    @State private var showsMoreSettings: Bool
    @State private var errorMessage: String?

    init(
        semester: Semester,
        courseName: String = "本课程",
        initial: ScheduleEntryInput?,
        onSave: @escaping (ScheduleEntryInput) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.semester = semester
        self.courseName = courseName
        self.initial = initial
        self.onSave = onSave
        self.onDelete = onDelete

        let total = max(semester.weekCount(), 1)
        let rule = initial?.weekRule ?? WeekRule(startWeek: 1, endWeek: total)
        let time = initial?.time ?? .period(start: 1, end: 2)

        _weekday = State(initialValue: initial?.weekday ?? .monday)
        _entryLocation = State(initialValue: initial?.location ?? "")
        _usesPeriod = State(initialValue: time.isPeriodBased)

        switch time {
        case let .period(start, end):
            _startPeriod = State(initialValue: start)
            _endPeriod = State(initialValue: end)
            _startTime = State(initialValue: TimeOfDay(hour: 8, minute: 0)!.dateValue())
            _endTime = State(initialValue: TimeOfDay(hour: 9, minute: 40)!.dateValue())
        case let .custom(start, end):
            _startPeriod = State(initialValue: 1)
            _endPeriod = State(initialValue: 2)
            _startTime = State(initialValue: start.dateValue())
            _endTime = State(initialValue: end.dateValue())
        }

        _selectedWeeks = State(initialValue: rule.selectedWeeks(upTo: total))

        _showsMoreSettings = State(initialValue: !time.isPeriodBased)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    FormFieldRow(title: "课程名称") {
                        Text(courseName)
                            .font(DesignTokens.Typography.body)
                    }

                    FormFieldRow(title: "星期") {
                        valueMenu(weekday.fullName) {
                            ForEach(Weekday.allCases, id: \.self) { day in
                                Button(day.fullName) { weekday = day }
                            }
                        }
                    }

                    FormFieldRow(title: usesPeriod ? "开始节次" : "开始时间") {
                        periodOrTimeValue(
                            selection: $startPeriod,
                            time: $startTime
                        )
                    }

                    FormFieldRow(title: usesPeriod ? "结束节次" : "结束时间") {
                        periodOrTimeValue(
                            selection: $endPeriod,
                            time: $endTime
                        )
                    }

                    FormFieldRow(title: "本次上课教室") {
                        TextField("选填", text: $entryLocation)
                            .font(DesignTokens.Typography.body)
                    }
                }

                weekSection

                moreSettingsSection

                Section {
                    Button("保存") { save() }
                        .buttonStyle(PrimaryActionButtonStyle(isEnabled: resultingTime != nil))
                        .disabled(resultingTime == nil)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)

                    if let onDelete {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Text("删除")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle("上课安排")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onChange(of: startPeriod) { _, newValue in
                if endPeriod < newValue { endPeriod = newValue }
            }
            .onChange(of: endPeriod) { _, newValue in
                if startPeriod > newValue { startPeriod = newValue }
            }
            .errorAlert($errorMessage)
        }
    }
}

// MARK: - 字段控件

extension ScheduleEntryEditView {

    /// 值左对齐的下拉选择控件。
    private func valueMenu<Content: View>(
        _ value: String,
        @ViewBuilder options: () -> Content
    ) -> some View {
        Menu {
            options()
        } label: {
            HStack(spacing: 4) {
                Text(value)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(.primary)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    private func periodOrTimeValue(
        selection: Binding<Int>,
        time: Binding<Date>
    ) -> some View {
        if usesPeriod {
            valueMenu("第\(selection.wrappedValue)节") {
                ForEach(periodOptions, id: \.self) { number in
                    Button("第\(number)节") { selection.wrappedValue = number }
                }
            }
        } else {
            DatePicker("", selection: time, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 可选节次：作息表已配置的节次，且不少于 1…12。
    private var periodOptions: [Int] {
        let configured = store.effectivePeriodTimes(in: semester.id).map(\.periodNumber)
        let highest = max(configured.max() ?? 0, 12)
        return Array(1...max(highest, 1))
    }
}

// MARK: - 上课周次

extension ScheduleEntryEditView {

    /// 上课周次：勾选实际上课的周，保存时由 `WeekRule.compact` 折叠为规则。
    @ViewBuilder
    private var weekSection: some View {
        Section {
            WeekSelectionEditor(weekCount: semester.weekCount(), selection: $selectedWeeks)
        } header: {
            Text("上课周次")
        } footer: {
            Text("勾选这门课实际上课的周次；没勾的周不排课。可以用上面的区间 + 单周/双周快速勾选，再逐周微调。")
        }
    }
}

// MARK: - 更多设置

extension ScheduleEntryEditView {

    @ViewBuilder
    private var moreSettingsSection: some View {
        Section {
            DisclosureGroup("更多设置", isExpanded: $showsMoreSettings) {
                Picker("时间模式", selection: $usesPeriod) {
                    Text("按课节").tag(true)
                    Text("按自定时间").tag(false)
                }
            }
        } footer: {
            Text("按课节的安排会跟着学期作息表换算钟点。")
        }
    }
}

// MARK: - 保存

extension ScheduleEntryEditView {

    private var resultingTime: ClassTime? {
        if usesPeriod {
            return try? ClassTime.makePeriod(start: startPeriod, end: endPeriod)
        }
        guard let start = TimeOfDay.from(startTime), let end = TimeOfDay.from(endTime) else {
            return nil
        }
        return try? ClassTime.makeCustom(start: start, end: end)
    }

    private var resultingRule: WeekRule {
        WeekRule.compact(weeks: selectedWeeks, weekCount: semester.weekCount())
    }

    private func save() {
        guard let time = resultingTime else {
            errorMessage = usesPeriod ? "起始课节不能晚于结束课节" : "开始时间必须早于结束时间"
            return
        }

        guard !selectedWeeks.isEmpty else {
            errorMessage = "请至少选择一个上课周次"
            return
        }

        let rule = resultingRule
        if let error = rule.validationErrors.first {
            errorMessage = error.message
            return
        }

        onSave(
            ScheduleEntryInput(
                weekday: weekday,
                time: time,
                weekRule: rule,
                location: entryLocation.normalizedOrNil
            )
        )
        dismiss()
    }
}

#Preview("添加安排") {
    let seed = PreviewSupport.seed

    ScheduleEntryEditView(
        semester: seed.semester,
        courseName: seed.dataStructures.name,
        initial: nil
    ) { _ in }
    .environment(seed.store)
}

#Preview("编辑安排 · 按课节") {
    let seed = PreviewSupport.seed
    let existing = seed.timetable.entries.first { $0.courseId == seed.dataStructures.id }

    ScheduleEntryEditView(
        semester: seed.semester,
        courseName: seed.dataStructures.name,
        initial: existing.map {
            ScheduleEntryInput(
                weekday: $0.weekday,
                time: $0.time,
                weekRule: $0.weekRule,
                location: $0.location
            )
        },
        onSave: { _ in },
        onDelete: {}
    )
    .environment(seed.store)
}

#Preview("编辑安排 · 自定时间与单双周") {
    let seed = PreviewSupport.seed
    let existing = seed.timetable.entries.first { $0.courseId == seed.physicalEducation.id }

    ScheduleEntryEditView(
        semester: seed.semester,
        courseName: seed.physicalEducation.name,
        initial: existing.map {
            ScheduleEntryInput(
                weekday: $0.weekday,
                time: $0.time,
                weekRule: $0.weekRule,
                location: $0.location
            )
        },
        onSave: { _ in },
        onDelete: {}
    )
    .environment(seed.store)
}
