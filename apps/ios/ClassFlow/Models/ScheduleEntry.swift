import Foundation

struct ScheduleEntry: Identifiable, Hashable, Codable, Sendable, Validatable {

    let id: UUID
    var courseId: UUID
    var weekday: Weekday
    var time: ClassTime
    /// 本条目单独使用的教室；为空时回退到 `Course.location`。
    var location: String?
    var startWeek: Int?
    var endWeek: Int?
    var weekPattern: WeekPattern
    var customWeeks: [Int]?
    var excludedWeeks: [Int]?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        courseId: UUID,
        weekday: Weekday,
        time: ClassTime,
        location: String? = nil,
        startWeek: Int? = nil,
        endWeek: Int? = nil,
        weekPattern: WeekPattern = .everyWeek,
        customWeeks: [Int]? = nil,
        excludedWeeks: [Int]? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.courseId = courseId
        self.weekday = weekday
        self.time = time
        self.location = location
        self.startWeek = startWeek
        self.endWeek = endWeek
        self.weekPattern = weekPattern
        self.customWeeks = customWeeks
        self.excludedWeeks = excludedWeeks
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension ScheduleEntry {

    var weekRule: WeekRule {
        get {
            WeekRule(
                startWeek: startWeek,
                endWeek: endWeek,
                pattern: weekPattern,
                customWeeks: customWeeks ?? [],
                excludedWeeks: excludedWeeks ?? []
            )
        }
        set {
            startWeek = newValue.startWeek
            endWeek = newValue.endWeek
            weekPattern = newValue.pattern
            customWeeks = newValue.customWeeks.isEmpty ? nil : newValue.customWeeks
            excludedWeeks = newValue.excludedWeeks.isEmpty ? nil : newValue.excludedWeeks
        }
    }
}

extension ScheduleEntry {

    var validationErrors: [ValidationError] {
        time.validationErrors + weekRule.validationErrors
    }
}

extension ScheduleEntry {

    mutating func normalize() {
        location = location?.normalizedOrNil
        var rule = weekRule
        rule.normalize()
        weekRule = rule
    }

    func normalized() -> ScheduleEntry {
        var copy = self
        copy.normalize()
        return copy
    }
}

extension ScheduleEntry {

    func isActive(inWeek week: Int) -> Bool {
        weekRule.contains(week: week)
    }

    func isActive(on date: CalendarDate, in semester: Semester, calendar: Calendar = .current) -> Bool {
        guard let week = semester.weekIndex(of: date, calendar: calendar) else { return false }
        return isActive(inWeek: week)
    }

    func applicableWeeks(in semester: Semester, calendar: Calendar = .current) -> [Int] {
        weekRule.resolvedWeeks(upTo: semester.weekCount(calendar: calendar))
    }
}

extension ScheduleEntry {

    static func == (lhs: ScheduleEntry, rhs: ScheduleEntry) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
