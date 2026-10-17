import Foundation

enum WeekPattern: String, Codable, CaseIterable, Hashable, Sendable {

    case everyWeek = "everyWeek"
    case oddWeeks = "oddWeeks"
    case evenWeeks = "evenWeeks"
    case customWeeks = "customWeeks"
}

extension WeekPattern {

    var displayName: String {
        switch self {
        case .everyWeek: "每周"
        case .oddWeeks: "单周"
        case .evenWeeks: "双周"
        case .customWeeks: "指定周次"
        }
    }

    var requiresCustomWeeks: Bool { self == .customWeeks }

    func matches(week: Int, customWeeks: [Int] = []) -> Bool {
        guard week > 0 else { return false }

        switch self {
        case .everyWeek: return true
        case .oddWeeks: return week % 2 == 1
        case .evenWeeks: return week % 2 == 0
        case .customWeeks: return customWeeks.contains(week)
        }
    }
}
