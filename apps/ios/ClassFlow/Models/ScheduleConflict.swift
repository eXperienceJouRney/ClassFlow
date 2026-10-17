import Foundation

// MARK: - 冲突结果
/// 课程时间冲突；只用于展示与提示，不会修改数据。
struct ScheduleConflict: Identifiable, Hashable, Sendable {

    let id: UUID
    let firstEntryId: UUID?
    let secondEntryId: UUID?
    let firstCourseName: String
    let secondCourseName: String
    let dateDescription: String
    let overlapDescription: String

    init(
        id: UUID = UUID(),
        firstEntryId: UUID? = nil,
        secondEntryId: UUID? = nil,
        firstCourseName: String,
        secondCourseName: String,
        dateDescription: String,
        overlapDescription: String
    ) {
        self.id = id
        self.firstEntryId = firstEntryId
        self.secondEntryId = secondEntryId
        self.firstCourseName = firstCourseName
        self.secondCourseName = secondCourseName
        self.dateDescription = dateDescription
        self.overlapDescription = overlapDescription
    }

    var summary: String {
        "\(dateDescription) \(firstCourseName) ↔ \(secondCourseName)：\(overlapDescription)"
    }
}

// MARK: - 可比较的时间槽
/// 参与冲突比较的一条安排；时间可能是实际钟点，也可能是课节编号。
struct ScheduleSlot: Hashable, Sendable {

    enum Time: Hashable, Sendable {
        case clock(TimeRange)
        case period(ClosedRange<Int>)
    }

    let entryId: UUID?
    let courseId: UUID?
    let courseName: String
    let weekday: Weekday
    let weeks: Set<Int>
    let time: Time

    init(
        entryId: UUID? = nil,
        courseId: UUID? = nil,
        courseName: String,
        weekday: Weekday,
        weeks: Set<Int>,
        time: Time
    ) {
        self.entryId = entryId
        self.courseId = courseId
        self.courseName = courseName
        self.weekday = weekday
        self.weeks = weeks
        self.time = time
    }
}

extension ScheduleSlot {

    /// 把一条课程安排转换成可比较的时间槽。
    static func make(
        entry: ScheduleEntry,
        course: Course?,
        periods: [ClassPeriodTime],
        weekCount: Int
    ) -> ScheduleSlot? {
        guard let time = resolve(entry.time, periods: periods) else { return nil }

        return ScheduleSlot(
            entryId: entry.id,
            courseId: entry.courseId,
            courseName: course?.name ?? "未知课程",
            weekday: entry.weekday,
            weeks: Set(entry.weekRule.resolvedWeeks(upTo: max(weekCount, 1))),
            time: time
        )
    }

    static func make(
        input: ScheduleEntryInput,
        courseName: String,
        periods: [ClassPeriodTime],
        weekCount: Int
    ) -> ScheduleSlot? {
        guard let time = resolve(input.time, periods: periods) else { return nil }

        return ScheduleSlot(
            courseName: courseName,
            weekday: input.weekday,
            weeks: Set(input.weekRule.resolvedWeeks(upTo: max(weekCount, 1))),
            time: time
        )
    }

    static func resolve(_ classTime: ClassTime, periods: [ClassPeriodTime]) -> Time? {
        switch classTime {
        case let .custom(start, end):
            guard let range = TimeRange(start: start, end: end) else { return nil }
            return .clock(range)

        case let .period(start, end):
            if let range = periods.resolve(classTime) {
                return .clock(range)
            }
            guard start >= 1, end >= 1, start <= end else { return nil }
            return .period(start...end)
        }
    }
}

// MARK: - 重叠计算
extension ClassOccurrence {

    /// 两节课按真实起止时刻重叠的分钟数；任一侧时间未配置或首尾相接时返回 nil。
    func clockOverlapMinutes(with other: ClassOccurrence) -> Int? {
        guard let lhs = clockTime, let rhs = other.clockTime else { return nil }

        let start = max(lhs.start, rhs.start)
        let end = min(lhs.end, rhs.end)
        guard start < end else { return nil }

        return end.minutesFromMidnight - start.minutesFromMidnight
    }
}

// MARK: - 冲突检测
/// 冲突比较。
enum ScheduleConflictDetector {

    /// 在同一组时间槽中两两比较，返回所有时间重叠。
    static func conflicts(among slots: [ScheduleSlot]) -> [ScheduleConflict] {
        guard slots.count > 1 else { return [] }

        var conflicts: [ScheduleConflict] = []

        for firstIndex in slots.indices {
            for secondIndex in slots.indices where secondIndex > firstIndex {
                let first = slots[firstIndex]
                let second = slots[secondIndex]
                guard let overlap = overlap(first, second) else { continue }

                conflicts.append(
                    ScheduleConflict(
                        firstEntryId: first.entryId,
                        secondEntryId: second.entryId,
                        firstCourseName: first.courseName,
                        secondCourseName: second.courseName,
                        dateDescription: "\(first.weekday.shortName)\(overlap.weeksDescription.isEmpty ? "" : " \(overlap.weeksDescription)")",
                        overlapDescription: overlap.description
                    )
                )
            }
        }

        return conflicts
    }

    /// 两组时间槽之间的重叠说明；不重叠时返回 nil。
    static func overlap(
        _ lhs: ScheduleSlot,
        _ rhs: ScheduleSlot
    ) -> (description: String, weeksDescription: String)? {
        guard lhs.weekday == rhs.weekday else { return nil }

        let sharedWeeks = lhs.weeks.intersection(rhs.weeks)
        guard !sharedWeeks.isEmpty else { return nil }

        guard let description = overlapDescription(lhs.time, rhs.time) else { return nil }

        return (description, weekListDescription(sharedWeeks.sorted()))
    }

    static func overlapDescription(_ lhs: ScheduleSlot.Time, _ rhs: ScheduleSlot.Time) -> String? {
        switch (lhs, rhs) {
        case let (.clock(left), .clock(right)):
            guard left.overlaps(right) else { return nil }
            let start = max(left.start, right.start)
            let end = min(left.end, right.end)
            return "时间重叠 \(start.displayText)-\(end.displayText)"

        case let (.period(left), .period(right)):
            let lower = max(left.lowerBound, right.lowerBound)
            let upper = min(left.upperBound, right.upperBound)
            guard lower <= upper else { return nil }
            let range = lower == upper ? "第\(lower)节" : "第\(lower)-\(upper)节"
            return "\(range)重叠（学期未配置课节时间，按课节编号判断）"

        case (.clock, .period), (.period, .clock):
            return "其中一条按课节安排且学期未配置课节时间，无法确认是否重叠"
        }
    }

    /// 把周次列表压缩成「第 1-4、6 周」这样的描述。
    static func weekListDescription(_ weeks: [Int]) -> String {
        guard let first = weeks.first else { return "" }
        guard weeks.count > 1 else { return "第 \(first) 周" }

        var parts: [String] = []
        var start = first
        var previous = first

        for week in weeks.dropFirst() {
            if week == previous + 1 {
                previous = week
                continue
            }
            parts.append(start == previous ? "\(start)" : "\(start)-\(previous)")
            start = week
            previous = week
        }
        parts.append(start == previous ? "\(start)" : "\(start)-\(previous)")

        return "第 \(parts.joined(separator: "、")) 周"
    }
}

// MARK: - 课表查询
extension Timetable {

    /// 某一周内的时间冲突。
    func conflicts(inWeek week: Int, calendar: Calendar = .current) -> [ScheduleConflict] {
        let weekCount = max(semester.weekCount(calendar: calendar), 1)
        let coursesById = Dictionary(courses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        return dates(inWeek: week, calendar: calendar).flatMap { date -> [ScheduleConflict] in
            let slots = classes(on: date, calendar: calendar).compactMap { occurrence in
                ScheduleSlot.make(
                    entry: occurrence.entry,
                    course: coursesById[occurrence.course.id],
                    periods: periods,
                    weekCount: weekCount
                )
            }
            return ScheduleConflictDetector.conflicts(among: slots)
        }
    }

    /// 整个学期的冲突数量。
    func conflictCount(calendar: Calendar = .current) -> Int {
        let weeks = max(semester.weekCount(calendar: calendar), 1)
        return (1...weeks).reduce(0) { $0 + conflicts(inWeek: $1, calendar: calendar).count }
    }
}
