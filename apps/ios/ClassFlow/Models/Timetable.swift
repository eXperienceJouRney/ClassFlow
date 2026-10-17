import Foundation

struct Timetable: Hashable, Sendable {

    let semester: Semester
    let courses: [Course]
    let entries: [ScheduleEntry]
    let periods: [ClassPeriodTime]

    init(
        semester: Semester,
        courses: [Course],
        entries: [ScheduleEntry],
        periods: [ClassPeriodTime] = []
    ) {
        self.semester = semester
        self.courses = courses.filter { $0.semesterId == semester.id }
        self.entries = entries
        self.periods = periods.filter { $0.semesterId == semester.id }
    }
}

extension Timetable {

    func dates(inWeek week: Int, calendar: Calendar = .current) -> [CalendarDate] {
        guard week >= 1,
              let anchor = semester.firstWeekMonday(calendar: calendar),
              let monday = calendar.date(byAdding: .day, value: (week - 1) * 7, to: anchor)
        else { return [] }

        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: monday)
                .map { CalendarDate(date: $0, calendar: calendar) }
        }
    }

    func classes(on date: CalendarDate, calendar: Calendar = .current) -> [ClassOccurrence] {
        guard let week = semester.weekIndex(of: date, calendar: calendar),
              let instant = date.startOfDay(in: calendar),
              let weekday = Weekday(date: instant, calendar: calendar)
        else { return [] }

        let coursesById = Dictionary(
            courses.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return entries
            .filter { $0.weekday == weekday && $0.isActive(inWeek: week) }
            .compactMap { entry -> ClassOccurrence? in
                guard let course = coursesById[entry.courseId] else { return nil }
                return ClassOccurrence(
                    course: course,
                    entry: entry,
                    date: date,
                    week: week,
                    clockTime: periods.resolve(entry.time)
                )
            }
            .sorted { lhs, rhs in
                let left = lhs.clockTime?.start.minutesFromMidnight ?? Int.max
                let right = rhs.clockTime?.start.minutesFromMidnight ?? Int.max

                if left == right { return lhs.course.name < rhs.course.name }
                return left < right
            }
    }

    func classes(inWeek week: Int, calendar: Calendar = .current) -> [ClassOccurrence] {
        dates(inWeek: week, calendar: calendar).flatMap { classes(on: $0, calendar: calendar) }
    }
}
