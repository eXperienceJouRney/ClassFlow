import Foundation

struct CalendarDate: Hashable, Comparable, Codable, Sendable {

    let year: Int
    let month: Int
    let day: Int

    private static let validationCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    init?(year: Int, month: Int, day: Int) {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        guard parts.isValidDate(in: Self.validationCalendar) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }
}

extension CalendarDate {

    var displayText: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    init?(_ text: String) {
        let parts = text.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }
}

extension CalendarDate {

    static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

extension CalendarDate {

    /// `周五，9月19日`。
    func weekdayMonthDayText(calendar: Calendar = .current) -> String {
        guard let instant = startOfDay(in: calendar),
              let weekday = Weekday(date: instant, calendar: calendar)
        else { return "\(month)月\(day)日" }

        return "\(weekday.shortName)，\(month)月\(day)日"
    }

    init(date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = parts.year ?? 1
        self.month = parts.month ?? 1
        self.day = parts.day ?? 1
    }

    func startOfDay(in calendar: Calendar = .current) -> Date? {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        return gregorian.date(from: DateComponents(year: year, month: month, day: day))
    }

    func instant(at time: TimeOfDay, in calendar: Calendar = .current) -> Date? {
        guard let day = startOfDay(in: calendar) else { return nil }
        return calendar.date(byAdding: .minute, value: time.minutesFromMidnight, to: day)
    }
}

// MARK: - 日期算术

extension CalendarDate {

    static func today(calendar: Calendar = .current) -> CalendarDate {
        CalendarDate(date: Date(), calendar: calendar)
    }

    func weekday(calendar: Calendar = .current) -> Weekday? {
        guard let instant = startOfDay(in: calendar) else { return nil }
        return Weekday(date: instant, calendar: calendar)
    }

    func adding(days: Int, calendar: Calendar = .current) -> CalendarDate? {
        guard let instant = startOfDay(in: calendar),
              let shifted = calendar.date(byAdding: .day, value: days, to: instant)
        else { return nil }
        return CalendarDate(date: shifted, calendar: calendar)
    }

    func addingMonths(_ value: Int, calendar: Calendar = .current) -> CalendarDate? {
        guard let instant = startOfDay(in: calendar),
              let shifted = calendar.date(byAdding: .month, value: value, to: instant)
        else { return nil }
        return CalendarDate(date: shifted, calendar: calendar)
    }

    var startOfMonth: CalendarDate {
        CalendarDate(year: year, month: month, day: 1) ?? self
    }

    var endOfMonth: CalendarDate {
        let nextMonthStart = addingMonths(1)?.startOfMonth ?? self
        return nextMonthStart.adding(days: -1) ?? self
    }
}
