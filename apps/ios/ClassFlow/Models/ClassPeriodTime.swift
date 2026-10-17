import Foundation

struct ClassPeriodTime: Identifiable, Hashable, Codable, Sendable, Validatable {

    let id: UUID
    var semesterId: UUID
    var periodNumber: Int
    var startTime: TimeOfDay
    var endTime: TimeOfDay
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        semesterId: UUID,
        periodNumber: Int,
        startTime: TimeOfDay,
        endTime: TimeOfDay,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.semesterId = semesterId
        self.periodNumber = periodNumber
        self.startTime = startTime
        self.endTime = endTime
        self.updatedAt = updatedAt
    }
}

extension ClassPeriodTime {

    var validationErrors: [ValidationError] {
        var errors: [ValidationError] = []

        if periodNumber < 1 {
            errors.append(.invalidPeriodNumber(periodNumber: periodNumber))
        }
        if startTime >= endTime {
            errors.append(.timeOrderInvalid(field: "第\(periodNumber)节"))
        }

        return errors
    }
}

extension ClassPeriodTime {

    /// 这一节的上课时长（分钟）：`08:00–08:45` → 45。
    var durationMinutes: Int {
        endTime.minutesFromMidnight - startTime.minutesFromMidnight
    }
}

extension ClassPeriodTime {

    static func == (lhs: ClassPeriodTime, rhs: ClassPeriodTime) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension Array where Element == ClassPeriodTime {

    func resolve(_ time: ClassTime) -> TimeRange? {
        switch time {
        case let .custom(start, end):
            return TimeRange(start: start, end: end)

        case let .period(start, end):
            guard let startPeriod = first(where: { $0.periodNumber == start }),
                  let endPeriod = first(where: { $0.periodNumber == end })
            else { return nil }
            return TimeRange(start: startPeriod.startTime, end: endPeriod.endTime)
        }
    }
}

// MARK: - 内置默认作息

extension ClassPeriodTime {

    /// 内置默认作息：第 1–8 节；学期未保存作息时间时使用。
    static let defaultSlots: [DefaultSlot] = [
        DefaultSlot(periodNumber: 1, start: "08:00", end: "08:45"),
        DefaultSlot(periodNumber: 2, start: "08:55", end: "09:40"),
        DefaultSlot(periodNumber: 3, start: "10:00", end: "10:45"),
        DefaultSlot(periodNumber: 4, start: "10:55", end: "11:40"),
        DefaultSlot(periodNumber: 5, start: "14:00", end: "14:45"),
        DefaultSlot(periodNumber: 6, start: "14:55", end: "15:40"),
        DefaultSlot(periodNumber: 7, start: "16:00", end: "16:45"),
        DefaultSlot(periodNumber: 8, start: "16:55", end: "17:40"),
    ]

    /// 默认作息里的一节（只描述「第几节、几点到几点」，与学期无关）。
    struct DefaultSlot: Hashable, Sendable {

        let periodNumber: Int
        /// `HH:mm` 文本，转成 `TimeOfDay` 时再校验一次。
        let start: String
        let end: String
    }

    /// 把内置默认作息落成某个学期的课节时间。
    static func defaults(for semesterId: UUID) -> [ClassPeriodTime] {
        defaultSlots.compactMap { slot in
            guard let start = TimeOfDay(slot.start), let end = TimeOfDay(slot.end) else { return nil }
            return ClassPeriodTime(
                semesterId: semesterId,
                periodNumber: slot.periodNumber,
                startTime: start,
                endTime: end
            )
        }
    }
}
