import Foundation

// MARK: - 一节课的真实时间区间

/// 课表里的一条安排落到某个具体日期后的「一节课」：课程、地点，以及真实的起止时刻。
///
/// `ClassOccurrence` 描述的是「第几周、星期几、第几节」，`ClassSession` 再把它和学期作息
/// 合成为真实时间轴上的 `Date`。Live Activity、倒计时与「下一节」都只认这个类型，
/// 免得各个界面各自把课节换算成时刻。
struct ClassSession: Identifiable, Hashable, Sendable {

    let occurrence: ClassOccurrence
    /// 上课时刻（已按学期作息解析）
    let start: Date
    /// 下课时刻（已按学期作息解析）
    let end: Date

    /// 同一条课表安排；每周重复的课共用同一个 id。
    var id: UUID { occurrence.entry.id }
    var entry: ScheduleEntry { occurrence.entry }
    var course: Course { occurrence.course }
    var courseName: String { occurrence.course.name }
    var date: CalendarDate { occurrence.date }

    /// 上课地点：安排上单独填写的地点优先，否则回退到课程地点；都没有时为 nil。
    var location: String? { occurrence.location }

    /// 本节课的时间区间。结束不晚于开始时退化成零长度区间，避免构造 `ClosedRange` 崩溃。
    var timeRange: ClosedRange<Date> { start...max(start, end) }

    /// 本节课时长（秒）。
    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

extension ClassSession {

    /// 某个时刻是否正在上这节课（下课那一刻起算结束）。
    func isOngoing(at moment: Date) -> Bool {
        start <= moment && moment < end
    }

    /// 是否就是同一节课：同一条安排，且起止时刻完全一致。
    /// 每周重复的同一门课 id 相同，必须连时刻一起比较。
    func isSameSession(as other: ClassSession) -> Bool {
        entry.id == other.entry.id && start == other.start && end == other.end
    }
}

// MARK: - 从课表取出真实时刻

extension ClassOccurrence {

    /// 把课节 / 自定时间换算成真实时刻；学期作息里查不到课节时为 nil（绝不猜测）。
    func session(calendar: Calendar = .current) -> ClassSession? {
        guard let clockTime,
              let start = date.instant(at: clockTime.start, in: calendar),
              let end = date.instant(at: clockTime.end, in: calendar),
              end > start
        else { return nil }

        return ClassSession(occurrence: self, start: start, end: end)
    }
}

// MARK: - 当前课程 / 下一节课程

extension Timetable {

    /// 向后查找下一节课时最多翻几天；一学期里课表通常按周重复，留足够余量即可。
    static let nextSessionSearchDayLimit = 31

    /// 某一天已配置作息的课，按上课时刻排序。
    func sessions(on date: CalendarDate, calendar: Calendar = .current) -> [ClassSession] {
        classes(on: date, calendar: calendar).compactMap { $0.session(calendar: calendar) }
    }

    /// 正在上的课；同一时刻有多节课重叠时取开始最早的一节。
    func currentSession(at moment: Date, calendar: Calendar = .current) -> ClassSession? {
        let today = CalendarDate(date: moment, calendar: calendar)
        return sessions(on: today, calendar: calendar)
            .first { $0.isOngoing(at: moment) }
    }

    /// 在 `date` 当刻或之后开始的第一节课，可以跨天；最多向后翻
    /// `nextSessionSearchDayLimit` 天，且不越过学期结束日。
    func nextSession(startingAtOrAfter date: Date, calendar: Calendar = .current) -> ClassSession? {
        let firstDay = CalendarDate(date: date, calendar: calendar)
        guard firstDay <= semester.endDate else { return nil }

        for offset in 0...Self.nextSessionSearchDayLimit {
            guard let day = firstDay.adding(days: offset, calendar: calendar),
                  day <= semester.endDate
            else { break }

            if let session = sessions(on: day, calendar: calendar)
                .first(where: { $0.start >= date }) {
                return session
            }
        }

        return nil
    }

    /// 这一节课之后的那一节：从本节课下课时开始找。
    /// 两节课首尾相接（下一节正好在本节下课时开始）也算下一节。
    func nextSession(after session: ClassSession, calendar: Calendar = .current) -> ClassSession? {
        nextSession(startingAtOrAfter: session.end, calendar: calendar)
    }
}
