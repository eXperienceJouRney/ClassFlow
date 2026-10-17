import Foundation

enum ValidationError: Error, Equatable, Hashable, Sendable {

    case requiredFieldEmpty(field: String)
    case invalidDateRange(field: String)
    case invalidWeekNumber(week: Int)
    case invalidWeekRange(startWeek: Int, endWeek: Int)
    case missingCustomWeeks
    case unexpectedCustomWeeks
    case weekOutOfRange(field: String, week: Int)
    case weekIncludedAndExcluded(week: Int)
    case invalidPeriodNumber(periodNumber: Int)
    case periodOrderInvalid(start: Int, end: Int)
    case timeOrderInvalid(field: String)
    case dueTimeWithoutDate
    case illegalStatusTransition(from: TaskStatus, to: TaskStatus)
    case duplicatePeriodNumber(periodNumber: Int)
}

extension ValidationError {

    var message: String {
        switch self {
        case let .requiredFieldEmpty(field):
            "「\(field)」不能为空"
        case let .invalidDateRange(field):
            "「\(field)」的开始日期不能晚于结束日期"
        case let .invalidWeekNumber(week):
            "周次 \(week) 必须大于 0"
        case let .invalidWeekRange(startWeek, endWeek):
            "起始周 \(startWeek) 不能晚于结束周 \(endWeek)"
        case .missingCustomWeeks:
            "「指定周次」模式必须至少选择一周"
        case .unexpectedCustomWeeks:
            "只有「指定周次」模式才能填写指定周次列表"
        case let .weekOutOfRange(field, week):
            "「\(field)」中的第 \(week) 周超出起止教学周范围"
        case let .weekIncludedAndExcluded(week):
            "第 \(week) 周不能同时作为上课周和排除周"
        case let .invalidPeriodNumber(periodNumber):
            "课节编号 \(periodNumber) 必须大于 0"
        case let .periodOrderInvalid(start, end):
            "起始课节 \(start) 不能晚于结束课节 \(end)"
        case let .timeOrderInvalid(field):
            "「\(field)」的开始时间必须早于结束时间"
        case .dueTimeWithoutDate:
            "设置了截止时间就必须先设置截止日期"
        case let .illegalStatusTransition(from, to):
            "任务状态不能从「\(from.displayName)」直接变为「\(to.displayName)」"
        case let .duplicatePeriodNumber(periodNumber):
            "课节编号 \(periodNumber) 重复"
        }
    }
}

protocol Validatable {
    var validationErrors: [ValidationError] { get }
}

extension Validatable {

    var isValid: Bool { validationErrors.isEmpty }

    func validate() throws {
        if let first = validationErrors.first { throw first }
    }
}
