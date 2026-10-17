import Foundation

struct Semester: Identifiable, Hashable, Codable, Sendable, Validatable {

    let id: UUID
    var name: String
    var startDate: CalendarDate
    var endDate: CalendarDate
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        startDate: CalendarDate,
        endDate: CalendarDate,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Semester {

    var validationErrors: [ValidationError] {
        var errors: [ValidationError] = []

        if name.isBlank {
            errors.append(.requiredFieldEmpty(field: "学期名称"))
        }
        if startDate > endDate {
            errors.append(.invalidDateRange(field: "学期日期"))
        }

        return errors
    }
}

extension Semester {

    func contains(_ date: CalendarDate) -> Bool {
        startDate <= date && date <= endDate
    }

    func weekIndex(of date: CalendarDate, calendar: Calendar = .current) -> Int? {
        guard contains(date),
              let target = date.startOfDay(in: calendar),
              let anchor = firstWeekMonday(calendar: calendar)
        else { return nil }

        let days = calendar.dateComponents([.day], from: anchor, to: target).day ?? 0
        return days / 7 + 1
    }

    func weekCount(calendar: Calendar = .current) -> Int {
        weekIndex(of: endDate, calendar: calendar) ?? 0
    }

    func firstWeekMonday(calendar: Calendar = .current) -> Date? {
        guard let start = startDate.startOfDay(in: calendar),
              let weekday = Weekday(date: start, calendar: calendar),
              let monday = calendar.date(byAdding: .day, value: -(weekday.rawValue - 1), to: start)
        else { return nil }

        return monday
    }
}

extension Semester {

    static func == (lhs: Semester, rhs: Semester) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
