import SwiftUI

struct SemesterEditView: View {

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let semester: Semester?

    @State private var name: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var errorMessage: String?

    init(semester: Semester? = nil) {
        self.semester = semester

        let calendar = Calendar.current
        let defaults = Self.defaultRange(calendar: calendar)

        _name = State(initialValue: semester?.name ?? Self.defaultName())
        _startDate = State(initialValue: semester?.startDate.startOfDay(in: calendar) ?? defaults.start)
        _endDate = State(initialValue: semester?.endDate.startOfDay(in: calendar) ?? defaults.end)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("例如：2026 秋季学期", text: $name)
                }

                Section("起止日期") {
                    DatePicker("开始", selection: $startDate, displayedComponents: .date)
                    DatePicker("结束", selection: $endDate, displayedComponents: .date)
                }

                Section {
                    LabeledContent("教学周数", value: "\(previewWeekCount) 周")
                } footer: {
                    Text("周次按日历周计算：开学当天所在的那一周是第 1 周。单双周等规则都以这个周次为准。")
                }
            }
            .navigationTitle(semester == nil ? "新建学期" : "编辑学期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(name.isBlank)
                }
            }
            .errorAlert($errorMessage)
        }
    }
}

extension SemesterEditView {

    private var previewWeekCount: Int {
        let start = CalendarDate(date: startDate)
        let end = CalendarDate(date: endDate)
        return Semester(name: name, startDate: start, endDate: end).weekCount()
    }

    private func save() {
        let start = CalendarDate(date: startDate)
        let end = CalendarDate(date: endDate)

        do {
            if let semester {
                try store.updateSemester(id: semester.id, name: name, startDate: start, endDate: end)
            } else {
                try store.createSemester(name: name, startDate: start, endDate: end)
            }
            dismiss()
        } catch {
            errorMessage = error.userMessage
        }
    }

    private static func defaultName() -> String {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: Date())
        let year = calendar.component(.year, from: Date())
        let season = (2...7).contains(month) ? "春季学期" : "秋季学期"
        return "\(year) \(season)"
    }

    private static func defaultRange(calendar: Calendar) -> (start: Date, end: Date) {
        let today = calendar.startOfDay(for: Date())
        let weeks = calendar.date(byAdding: .day, value: 16 * 7 - 1, to: today)
        return (today, weeks ?? today)
    }
}

#Preview("新建学期") {
    SemesterEditView()
        .environment(PreviewSupport.store)
}

#Preview("编辑学期") {
    let seed = PreviewSupport.seed

    SemesterEditView(semester: seed.semester)
        .environment(seed.store)
}
