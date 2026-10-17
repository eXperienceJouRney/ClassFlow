import Foundation

struct ClassOccurrence: Identifiable, Hashable, Sendable {

    let course: Course
    let entry: ScheduleEntry
    let date: CalendarDate
    let week: Int
    let clockTime: TimeRange?

    var id: UUID { entry.id }
    var weekday: Weekday { entry.weekday }
    var classTime: ClassTime { entry.time }
    var isTimeConfigured: Bool { clockTime != nil }
    var displayTime: String { clockTime?.displayText ?? entry.time.displayText }

    /// 上课地点：本条安排单独填写的教室优先，否则回退到课程上的教室。
    var location: String? {
        if let location = entry.location, !location.isBlank { return location }
        if let location = course.location, !location.isBlank { return location }
        return nil
    }
}

