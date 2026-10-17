import SwiftUI

extension CourseColor {

    var displayName: String {
        switch self {
        case .blue: "蓝色"
        case .green: "绿色"
        case .orange: "橙色"
        case .purple: "紫色"
        case .pink: "粉色"
        case .teal: "青色"
        case .red: "红色"
        case .gray: "灰色"
        }
    }
}

extension Weekday {

    var fullName: String {
        switch self {
        case .monday: "星期一"
        case .tuesday: "星期二"
        case .wednesday: "星期三"
        case .thursday: "星期四"
        case .friday: "星期五"
        case .saturday: "星期六"
        case .sunday: "星期日"
        }
    }
}

extension TimeOfDay {

    func dateValue(calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    static func from(_ date: Date, calendar: Calendar = .current) -> TimeOfDay? {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }
}

extension CalendarDate {

    var monthDayText: String {
        "\(month)月\(day)日"
    }
}

extension Array where Element == CalendarDate {

    /// 按「每周起始日」偏好重排一周的日期，只改展示顺序；周次编号仍以周一为基准。
    func ordered(from firstWeekday: Weekday, calendar: Calendar = .current) -> [CalendarDate] {
        guard count > 1,
              let index = firstIndex(where: { $0.weekday(calendar: calendar) == firstWeekday })
        else { return self }

        return Array(self[index...]) + Array(self[..<index])
    }
}

extension Semester {

    /// 学期日期区间，如 `9月1日-12月20日`。
    var dateRangeText: String {
        "\(startDate.month)月\(startDate.day)日-\(endDate.month)月\(endDate.day)日"
    }
}

extension Course {

    /// 课程在学期详情 / 课程管理里的副标题：`周一/周三•09:00-10:30`。
    func scheduleSummaryText(
        entries: [ScheduleEntry],
        periods: [ClassPeriodTime],
        timeFormat: TimeFormatPreference = .twentyFourHour
    ) -> String? {
        entries.summary(periods: periods, timeFormat: timeFormat)?.displayText
    }
}

extension Memo {

    /// 列表日期，如 `9月18日`。
    func dateText(calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.month, .day], from: createdAt)
        return "\(parts.month ?? 1)月\(parts.day ?? 1)日"
    }

    /// 课程笔记列表里的日期时间，如 `9月18日•14:45`。
    func dateTimeText(calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.month, .day, .hour, .minute], from: createdAt)
        return String(
            format: "%d月%d日•%02d:%02d",
            parts.month ?? 1,
            parts.day ?? 1,
            parts.hour ?? 0,
            parts.minute ?? 0
        )
    }
}

struct DaySchedule: Identifiable, Hashable {

    let date: CalendarDate
    let weekday: Weekday?
    let classes: [ClassOccurrence]

    var id: CalendarDate { date }
    var isWeekend: Bool { weekday?.isWeekend ?? false }
    var isEmpty: Bool { classes.isEmpty }
}

extension Timetable {

    func daySchedules(inWeek week: Int, calendar: Calendar = .current) -> [DaySchedule] {
        dates(inWeek: week, calendar: calendar).map { date in
            DaySchedule(
                date: date,
                weekday: date.weekday(calendar: calendar),
                classes: classes(on: date, calendar: calendar)
            )
        }
    }

    func scheduledWeekNumbers(calendar: Calendar = .current) -> Set<Int> {
        let total = semester.weekCount(calendar: calendar)
        guard total >= 1 else { return [] }

        var weeks = Set<Int>()
        for entry in entries {
            weeks.formUnion(entry.applicableWeeks(in: semester, calendar: calendar))
        }
        return weeks
    }
}

extension Error {

    var userMessage: String {
        (self as? AppError)?.message ?? String(describing: self)
    }
}

extension View {

    func errorAlert(_ message: Binding<String?>) -> some View {
        alert(
            "操作失败",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {
            Button("好", role: .cancel) { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}

private struct ErrorAlertPreview: View {

    @State private var message: String? = "课程名称不能为空"

    var body: some View {
        List {
            Button("再弹一次") { message = "课程名称不能为空" }
        }
        .errorAlert($message)
    }
}

#Preview("错误提示弹窗") {
    ErrorAlertPreview()
}
