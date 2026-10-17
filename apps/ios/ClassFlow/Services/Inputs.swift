import Foundation

struct ScheduleEntryInput: Hashable, Sendable {

    var weekday: Weekday
    var time: ClassTime
    var weekRule: WeekRule
    /// 本条安排单独使用的教室；nil 表示未单独指定。
    var location: String?

    init(
        weekday: Weekday,
        time: ClassTime,
        weekRule: WeekRule = WeekRule(),
        location: String? = nil
    ) {
        self.weekday = weekday
        self.time = time
        self.weekRule = weekRule
        self.location = location
    }

    func makeEntry(courseId: UUID) -> ScheduleEntry {
        var entry = ScheduleEntry(
            courseId: courseId,
            weekday: weekday,
            time: time,
            location: location
        )
        entry.weekRule = weekRule
        return entry
    }
}

struct ClassPeriodInput: Hashable, Sendable {

    var periodNumber: Int
    var startTime: TimeOfDay
    var endTime: TimeOfDay

    init(periodNumber: Int, startTime: TimeOfDay, endTime: TimeOfDay) {
        self.periodNumber = periodNumber
        self.startTime = startTime
        self.endTime = endTime
    }
}

/// 修改一条导入草稿记录的输入；课节与钟点两组字段可同时存在。
struct ImportEntryEdit: Hashable, Sendable {

    var courseName: String
    var teacher: String?
    var location: String?
    var weekday: Weekday?
    var startPeriod: Int?
    var endPeriod: Int?
    var startTime: TimeOfDay?
    var endTime: TimeOfDay?
    var weekRule: WeekRule

    init(
        courseName: String,
        teacher: String? = nil,
        location: String? = nil,
        weekday: Weekday? = nil,
        startPeriod: Int? = nil,
        endPeriod: Int? = nil,
        startTime: TimeOfDay? = nil,
        endTime: TimeOfDay? = nil,
        weekRule: WeekRule = WeekRule()
    ) {
        self.courseName = courseName
        self.teacher = teacher
        self.location = location
        self.weekday = weekday
        self.startPeriod = startPeriod
        self.endPeriod = endPeriod
        self.startTime = startTime
        self.endTime = endTime
        self.weekRule = weekRule
    }

    init(entry: ImportDraftEntry) {
        self.init(
            courseName: entry.courseName,
            teacher: entry.teacher,
            location: entry.location,
            weekday: entry.weekday,
            startPeriod: entry.startPeriod,
            endPeriod: entry.endPeriod,
            startTime: entry.startTime,
            endTime: entry.endTime,
            weekRule: entry.weekRule
        )
    }
}

/// 校验结果：整体结论与具体问题列表。
struct ValidationResult: Hashable, Sendable {

    let isValid: Bool
    let issues: [ValidationIssue]

    static let valid = ValidationResult(isValid: true, issues: [])
}
