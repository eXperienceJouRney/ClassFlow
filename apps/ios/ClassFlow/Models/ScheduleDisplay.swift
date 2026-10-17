import Foundation

/// 课表的日 / 周 / 月主视图，同时用作偏好设置中的默认视图。
enum ScheduleMode: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {

    case day
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "日"
        case .week: "周"
        case .month: "月"
        }
    }

    /// 课表头部右上角分段控件里的三项。
    static let segmentedCases: [ScheduleMode] = [.day, .week, .month]
}

extension ClassOccurrence {

    /// 该安排按课节排课，但学期作息里没有对应课节，算不出钟点。
    var hasUnresolvedPeriodTime: Bool {
        classTime.isPeriodBased && clockTime == nil
    }

    /// 主时间文本：能算出钟点就显示钟点，否则退回课节编号并说明原因。
    func primaryTimeText(timeFormat: TimeFormatPreference) -> String {
        if let clockTime { return clockTime.displayText(format: timeFormat) }
        return "\(classTime.displayText)（时间未配置）"
    }

    /// 概要文本：「时间（・课节）・地点」。
    func detailText(timeFormat: TimeFormatPreference, showsPeriod: Bool = false) -> String {
        var parts = [primaryTimeText(timeFormat: timeFormat)]
        if showsPeriod, classTime.isPeriodBased, clockTime != nil {
            parts.append(classTime.displayText)
        }
        if let location { parts.append(location) }
        return parts.joined(separator: "・")
    }
}
