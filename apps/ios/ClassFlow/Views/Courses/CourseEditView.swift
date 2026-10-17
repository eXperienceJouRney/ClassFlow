import SwiftUI

/// 课程编辑表单，新建与编辑共用；名称为空时不可保存。
struct CourseEditView: View {

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let course: Course?

    @State private var semesterId: UUID
    @State private var name: String
    @State private var teacher: String
    @State private var location: String
    @State private var color: CourseColor
    @State private var entries: [ScheduleEntryInput] = []
    @State private var draft: EntryDraft?
    @State private var showsDeletion = false
    @State private var errorMessage: String?

    private struct EntryDraft: Identifiable {
        let id = UUID()
        var index: Int?
        var input: ScheduleEntryInput?
    }

    init(semesterId: UUID, course: Course?) {
        self.course = course

        _semesterId = State(initialValue: course?.semesterId ?? semesterId)
        _name = State(initialValue: course?.name ?? "")
        _teacher = State(initialValue: course?.teacher ?? "")
        _location = State(initialValue: course?.location ?? "")
        _color = State(initialValue: course?.color ?? .blue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    fieldRow("课程名称", text: $name, prompt: "例如：数据结构")
                    fieldRow("授课教师", text: $teacher, prompt: "例如：陈老师")
                    fieldRow("教室", text: $location, prompt: "例如：A201")
                }

                Section {
                    colorRow
                } header: {
                    Text("课程颜色")
                }

                Section {
                    Picker("学期", selection: $semesterId) {
                        ForEach(store.semesters) { semester in
                            Text(semester.name).tag(semester.id)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section {
                    ForEach(entries.indices, id: \.self) { index in
                        Button {
                            draft = EntryDraft(index: index, input: entries[index])
                        } label: {
                            entryRow(entries[index])
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { entries.remove(atOffsets: $0) }

                    Button("+添加上课安排") {
                        draft = EntryDraft(index: nil, input: nil)
                    }
                } header: {
                    Text("上课安排")
                } footer: {
                    Text("一门课可以有多条安排（例如周二和周四各一次）。点某条可以修改，左滑删除。")
                }

                if !conflicts.isEmpty {
                    Section {
                        ScheduleConflictWarningView(
                            conflicts: conflicts,
                            title: "与其他课程的时间冲突"
                        )
                    } footer: {
                        Text("冲突只做提示，不会阻止保存；可以回到课表里调整时间。")
                    }
                }

                if course != nil {
                    Section {
                        Button(role: .destructive) {
                            showsDeletion = true
                        } label: {
                            Text("删除课程")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle(course == nil ? "新建课程" : "编辑课程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(name.isBlank)
                }
            }
            .sheet(item: $draft) { item in
                if let semester = store.data.semester(id: semesterId) {
                    ScheduleEntryEditView(
                        semester: semester,
                        courseName: name.normalizedOrNil ?? "本课程",
                        initial: item.input,
                        onSave: { result in
                            if let index = item.index {
                                entries[index] = result
                            } else {
                                entries.append(result)
                            }
                        },
                        onDelete: item.index.map { index in
                            { entries.remove(at: index) }
                        }
                    )
                }
            }
            .sheet(isPresented: $showsDeletion) {
                if let course {
                    CourseDeletionView(courseId: course.id) { dismiss() }
                }
            }
            .task { loadEntries() }
            .errorAlert($errorMessage)
        }
    }
}

// MARK: - 字段与颜色

extension CourseEditView {

    private func fieldRow(
        _ title: String,
        text: Binding<String>,
        prompt: String
    ) -> some View {
        FormFieldRow(title: title) {
            TextField(prompt, text: text)
                .font(DesignTokens.Typography.body)
        }
    }

    private var colorRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(CourseColor.allCases, id: \.self) { item in
                    Button {
                        color = item
                    } label: {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(item.color)
                                .frame(width: 30, height: 30)
                                .overlay {
                                    Circle()
                                        .strokeBorder(Color.primary, lineWidth: color == item ? 2.5 : 0)
                                }
                            Text(item.displayName)
                                .font(.caption2)
                                .foregroundStyle(color == item ? Color.primary : Color.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - 上课安排

extension CourseEditView {

    /// 当前编辑内容与学期内其它课程、以及本课程多条安排之间的时间冲突（只读提示）。
    private var conflicts: [ScheduleConflict] {
        guard !entries.isEmpty else { return [] }

        return store.detectScheduleConflicts(
            semesterId: semesterId,
            candidateEntries: entries,
            courseName: name.normalizedOrNil ?? "本课程",
            excludingCourseId: course?.id
        )
    }

    /// 行内显示星期与节次；周次规则不是「每周」时补一行说明。
    private func entryRow(_ input: ScheduleEntryInput) -> some View {
        HStack(spacing: 10) {
            Text(input.weekday.shortName)
                .font(.system(size: 22, weight: .regular))
                .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(input.time.displayText)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.primary)

                if let note = weekRuleNote(input) {
                    Text(note)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func weekRuleNote(_ input: ScheduleEntryInput) -> String? {
        let total = store.data.semester(id: semesterId)?.weekCount() ?? 0
        guard total >= 1 else { return nil }

        let rule = input.weekRule
        guard !rule.coversEveryWeek(upTo: total) else { return nil }
        return rule.displayName
    }

    private func loadEntries() {
        guard entries.isEmpty, let course else { return }
        entries = store.scheduleEntries(for: course.id).map {
            ScheduleEntryInput(
                weekday: $0.weekday,
                time: $0.time,
                weekRule: $0.weekRule,
                location: $0.location
            )
        }
    }

    private func save() {
        let teacherValue = teacher.normalizedOrNil
        let locationValue = location.normalizedOrNil

        do {
            if let course {
                try store.updateCourse(
                    id: course.id,
                    name: name,
                    teacher: teacherValue,
                    location: locationValue,
                    color: color,
                    scheduleEntries: entries,
                    semesterId: semesterId
                )
            } else {
                try store.createCourse(
                    semesterId: semesterId,
                    name: name,
                    teacher: teacherValue,
                    location: locationValue,
                    color: color,
                    scheduleEntries: entries
                )
            }
            dismiss()
        } catch {
            errorMessage = error.userMessage
        }
    }
}

#Preview("新建课程") {
    let seed = PreviewSupport.seed

    CourseEditView(semesterId: seed.semester.id, course: nil)
        .environment(seed.store)
}

#Preview("编辑课程") {
    let seed = PreviewSupport.seed

    CourseEditView(semesterId: seed.semester.id, course: seed.dataStructures)
        .environment(seed.store)
}

#Preview("编辑课程 · 与其他课程时间冲突") {
    let scenario = PreviewSupport.conflictScenario

    CourseEditView(semesterId: scenario.semester.id, course: scenario.math)
        .environment(scenario.store)
}
