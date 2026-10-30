import SwiftUI

/// 修改一条导入候选记录；课节与钟点并存时，钟点仅作为学期作息候选值。
struct ImportEntryEditView: View {

    let semester: Semester
    let entry: ImportDraftEntry
    var onSave: (ImportEntryEdit) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var courseName: String
    @State private var teacher: String
    @State private var location: String
    @State private var weekday: Weekday?
    @State private var usesPeriod: Bool
    @State private var startPeriod: Int
    @State private var endPeriod: Int
    @State private var keepsCandidateTimes: Bool
    @State private var startTime: Date
    @State private var endTime: Date
    /// 实际上课周次：勾选的周排课，未勾选的周不排课。
    @State private var selectedWeeks: Set<Int>
    @State private var confirmsImageWeeks: Bool

    init(
        semester: Semester,
        entry: ImportDraftEntry,
        onSave: @escaping (ImportEntryEdit) -> Void
    ) {
        self.semester = semester
        self.entry = entry
        self.onSave = onSave

        let total = max(semester.weekCount(), 1)
        let rule = entry.weekRule

        _courseName = State(initialValue: entry.courseName)
        _teacher = State(initialValue: entry.teacher ?? "")
        _location = State(initialValue: entry.location ?? "")
        _weekday = State(initialValue: entry.weekday)
        _usesPeriod = State(initialValue: entry.periodPair != nil || !entry.hasCustomTimeInformation)
        _startPeriod = State(initialValue: entry.startPeriod ?? 1)
        _endPeriod = State(initialValue: entry.endPeriod ?? 2)
        _keepsCandidateTimes = State(initialValue: entry.customPair != nil)
        _startTime = State(
            initialValue: (entry.startTime ?? TimeOfDay(hour: 8, minute: 0)!).dateValue()
        )
        _endTime = State(
            initialValue: (entry.endTime ?? TimeOfDay(hour: 9, minute: 40)!).dateValue()
        )
        _selectedWeeks = State(initialValue: entry.imageReview?.requiresWeekConfirmation == true
            ? [] : rule.selectedWeeks(upTo: total))
        _confirmsImageWeeks = State(initialValue: entry.imageReview?.requiresWeekConfirmation != true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("课程信息") {
                    TextField("课程名称", text: $courseName)
                    TextField("任课教师（可选）", text: $teacher)
                    TextField("上课地点（可选）", text: $location)
                }

                Section("星期") {
                    Picker("星期", selection: $weekday) {
                        Text("未指定").tag(Weekday?.none)
                        ForEach(Weekday.allCases, id: \.self) { day in
                            Text(day.shortName).tag(Weekday?.some(day))
                        }
                    }
                }

                timeSection
                weekSection

                if let review = entry.imageReview, !review.notes.isEmpty {
                    Section("原图核对提示") {
                        ForEach(review.notes, id: \.self) { Text($0).font(.callout) }
                    }
                }

                if !entry.issues.isEmpty {
                    Section("当前校验问题") {
                        ForEach(entry.issues, id: \.self) { issue in
                            Label(issue.message, systemImage: "exclamationmark.circle")
                                .font(.callout)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                if let raw = entry.rawPayload {
                    Section("原始输入") {
                        Text(raw)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("修改导入记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { save() }
                        .disabled(!confirmsImageWeeks || (entry.imageReview?.requiresWeekConfirmation == true && selectedWeeks.isEmpty))
                }
            }
        }
    }
}

// MARK: - 表单区块
extension ImportEntryEditView {

    @ViewBuilder
    private var timeSection: some View {
        Section {
            Picker("时间模式", selection: $usesPeriod) {
                Text("按课节").tag(true)
                Text("按自定时间").tag(false)
            }
            .pickerStyle(.segmented)

            if usesPeriod {
                Stepper("起始课节：第 \(startPeriod) 节", value: $startPeriod, in: 1...30)
                Stepper("结束课节：第 \(endPeriod) 节", value: $endPeriod, in: 1...30)

                if entry.customPair != nil {
                    Toggle("保留识别到的钟点", isOn: $keepsCandidateTimes)
                    if keepsCandidateTimes {
                        DatePicker("开始", selection: $startTime, displayedComponents: .hourAndMinute)
                        DatePicker("结束", selection: $endTime, displayedComponents: .hourAndMinute)
                    }
                }
            } else {
                DatePicker("开始", selection: $startTime, displayedComponents: .hourAndMinute)
                DatePicker("结束", selection: $endTime, displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("上课时间")
        } footer: {
            if usesPeriod && entry.customPair != nil && keepsCandidateTimes {
                Text("提交时以课节为准；钟点不会写入课程安排，只作为待确认的学期作息候选值。")
            } else if usesPeriod {
                Text("按课节的安排会根据学期作息换算实际钟点，作息表改了它也跟着变。")
            } else {
                Text("自定时间直接写在安排里，作息表怎么改都不受影响。")
            }
        }
    }

    /// 上课周次：以「实际排课的周」正面勾选，解析出的周规则会先换算成勾选状态。
    @ViewBuilder
    private var weekSection: some View {
        Section {
            WeekSelectionEditor(weekCount: semester.weekCount(), selection: $selectedWeeks)
            if entry.imageReview?.requiresWeekConfirmation == true {
                Toggle("已核对本课程的上课周次", isOn: $confirmsImageWeeks)
                    .disabled(selectedWeeks.isEmpty)
            }
        } header: {
            Text("上课周次")
        } footer: {
            Text("勾选这门课实际上课的周次；没勾的周不排课。识别到的周次写法（含「除某几周」）会自动换算成勾选状态。")
        }
    }

    private func save() {
        let rule = WeekRule.compact(weeks: selectedWeeks, weekCount: semester.weekCount())

        let edit = ImportEntryEdit(
            courseName: courseName,
            teacher: teacher.normalizedOrNil,
            location: location.normalizedOrNil,
            weekday: weekday,
            startPeriod: usesPeriod ? startPeriod : nil,
            endPeriod: usesPeriod ? endPeriod : nil,
            startTime: (!usesPeriod || (entry.customPair != nil && keepsCandidateTimes))
                ? TimeOfDay.from(startTime)
                : nil,
            endTime: (!usesPeriod || (entry.customPair != nil && keepsCandidateTimes))
                ? TimeOfDay.from(endTime)
                : nil,
            weekRule: rule,
            confirmsImageWeeks: confirmsImageWeeks
        )

        onSave(edit)
        dismiss()
    }
}

#Preview("修改导入记录 · 按课节") {
    let seed = PreviewSupport.seed

    ImportEntryEditView(
        semester: seed.semester,
        entry: PreviewSupport.importEntry(
            rawPayload: "高等数学,周一,第1-2节,1-16周,教三201,王老师"
        )
    ) { _ in }
}

#Preview("修改导入记录 · 同时识别到钟点") {
    let seed = PreviewSupport.seed

    ImportEntryEditView(
        semester: seed.semester,
        entry: PreviewSupport.importEntry(
            startTime: TimeOfDay(hour: 8, minute: 0),
            endTime: TimeOfDay(hour: 9, minute: 40),
            rawPayload: "高等数学,周一,第1-2节,08:00-09:40,教三201,王老师"
        )
    ) { _ in }
}

#Preview("修改导入记录 · 待修正") {
    let seed = PreviewSupport.seed

    ImportEntryEditView(
        semester: seed.semester,
        entry: PreviewSupport.importEntry(
            teacher: nil,
            location: nil,
            weekday: nil,
            startPeriod: nil,
            endPeriod: nil,
            rawPayload: "高等数学",
            status: .needsCorrection,
            issues: [
                ValidationIssue(
                    code: ImportIssueCode.missingWeekday.rawValue,
                    field: "weekday",
                    message: "缺少上课星期"
                ),
                ValidationIssue(
                    code: ImportIssueCode.missingTime.rawValue,
                    field: "time",
                    message: "缺少上课时间"
                ),
            ]
        )
    ) { _ in }
}
