import Foundation

enum ClassTime: Hashable, Codable, Sendable {

    case period(start: Int, end: Int)
    case custom(start: TimeOfDay, end: TimeOfDay)
}

extension ClassTime: Validatable {

    var validationErrors: [ValidationError] {
        switch self {
        case let .period(start, end):
            if start < 1 { return [.invalidPeriodNumber(periodNumber: start)] }
            if end < 1 { return [.invalidPeriodNumber(periodNumber: end)] }
            if start > end { return [.periodOrderInvalid(start: start, end: end)] }
            return []

        case let .custom(start, end):
            if start >= end { return [.timeOrderInvalid(field: "上课时间")] }
            return []
        }
    }
}

extension ClassTime {

    static func makePeriod(start: Int, end: Int) throws -> ClassTime {
        let value = ClassTime.period(start: start, end: end)
        try value.validate()
        return value
    }

    static func makeCustom(start: TimeOfDay, end: TimeOfDay) throws -> ClassTime {
        let value = ClassTime.custom(start: start, end: end)
        try value.validate()
        return value
    }
}

extension ClassTime {

    var isPeriodBased: Bool {
        if case .period = self { return true }
        return false
    }

    /// 无空格写法：`第3节` / `第3-4节`。
    var displayText: String {
        switch self {
        case let .period(start, end):
            start == end ? "第\(start)节" : "第\(start)-\(end)节"
        case let .custom(start, end):
            "\(start.displayText)-\(end.displayText)"
        }
    }

    /// 课节模式下的起止课节编号；自定时间返回 nil。
    var periodRange: (start: Int, end: Int)? {
        if case let .period(start, end) = self { return (start, end) }
        return nil
    }
}
