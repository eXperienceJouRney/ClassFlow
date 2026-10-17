import Foundation

/// 待办「按时间」分组的分组名。
enum TaskDueBucket: String, CaseIterable, Hashable, Sendable {

    case today
    case tomorrow
    case upcoming
    case undated

    static let displayOrder: [TaskDueBucket] = [.today, .tomorrow, .upcoming, .undated]

    var title: String {
        switch self {
        case .today: "今天"
        case .tomorrow: "明天"
        case .upcoming: "即将到期"
        case .undated: "无截止日期"
        }
    }
}

/// 待办行内的相对时间文案；初始化只做日期算术，`now` 由调用方传入。
struct TaskDueText: Hashable, Sendable {

    let bucket: TaskDueBucket
    /// 按课程分组时的行内文案：`今天・17:00` / `明天` / `周一，9月22日` / `无截止日期`
    let relative: String
    /// 按时间分组时的时间部分：今天或明天且有具体时刻时只写时刻（`17:00`），其余与 `relative` 相同
    let short: String

    init(
        dueDate: CalendarDate?,
        dueTime: TimeOfDay? = nil,
        now: Date = Date(),
        calendar: Calendar = .current,
        format: TimeFormatPreference = .twentyFourHour
    ) {
        guard let dueDate else {
            bucket = .undated
            relative = "无截止日期"
            short = relative
            return
        }

        let today = CalendarDate(date: now, calendar: calendar)
        let offset = Self.dayOffset(from: today, to: dueDate, calendar: calendar)

        let dayText: String
        switch offset {
        case 0: dayText = "今天"
        case 1: dayText = "明天"
        default: dayText = Self.absoluteText(dueDate, calendar: calendar)
        }

        switch offset {
        case 0: bucket = .today
        case 1: bucket = .tomorrow
        default: bucket = offset < 0 ? .today : .upcoming
        }

        if let dueTime {
            let timeText = dueTime.displayText(format: format)
            relative = "\(dayText)・\(timeText)"
            short = (offset == 0 || offset == 1) ? timeText : dayText
        } else {
            relative = dayText
            short = dayText
        }
    }
}

extension TaskDueText {

    /// `周一，9月22日`。
    private static func absoluteText(_ date: CalendarDate, calendar: Calendar) -> String {
        date.weekdayMonthDayText(calendar: calendar)
    }

    /// 两个日历日之间相差几天（`to` 晚于 `today` 为正）。
    private static func dayOffset(
        from today: CalendarDate,
        to date: CalendarDate,
        calendar: Calendar
    ) -> Int {
        guard let from = today.startOfDay(in: calendar),
              let to = date.startOfDay(in: calendar)
        else {
            if date == today { return 0 }
            return date < today ? -1 : 1
        }

        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }
}

extension CourseTask {

    /// 分组与行内相对时间文案。
    func dueText(
        now: Date = Date(),
        calendar: Calendar = .current,
        format: TimeFormatPreference = .twentyFourHour
    ) -> TaskDueText {
        TaskDueText(
            dueDate: dueDate,
            dueTime: dueTime,
            now: now,
            calendar: calendar,
            format: format
        )
    }
}
