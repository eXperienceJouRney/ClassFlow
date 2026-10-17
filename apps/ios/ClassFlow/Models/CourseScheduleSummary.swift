import Foundation

/// 一组上课安排的摘要文本，如 `周一/周三•09:00-10:30`。
struct CourseScheduleSummary: Hashable, Sendable {

    /// `周一/周三`
    let weekdaysText: String
    /// `09:00-10:30`，课节时间未配置时退化成 `第5-6节`
    let timeText: String

    var displayText: String { "\(weekdaysText)•\(timeText)" }
}

extension Array where Element == ScheduleEntry {

    /// 把若干条安排压成一行摘要：星期去重后按周一到周日排序，时间取最早开始的那条安排。
    func summary(
        periods: [ClassPeriodTime] = [],
        timeFormat: TimeFormatPreference = .twentyFourHour
    ) -> CourseScheduleSummary? {
        guard !isEmpty else { return nil }

        let weekdays = Set(map(\.weekday)).sorted { $0.rawValue < $1.rawValue }
        let weekdaysText = weekdays.map(\.shortName).joined(separator: "/")

        let ordered = sorted { lhs, rhs in
            let left = periods.resolve(lhs.time)?.start.minutesFromMidnight ?? Int.max
            let right = periods.resolve(rhs.time)?.start.minutesFromMidnight ?? Int.max
            if left != right { return left < right }
            return lhs.weekday.rawValue < rhs.weekday.rawValue
        }

        guard let first = ordered.first else { return nil }

        let timeText: String
        if let range = periods.resolve(first.time) {
            timeText = range.displayText(format: timeFormat)
        } else {
            timeText = first.time.displayText
        }

        return CourseScheduleSummary(weekdaysText: weekdaysText, timeText: timeText)
    }
}
