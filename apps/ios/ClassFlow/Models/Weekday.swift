import Foundation

enum Weekday: Int, CaseIterable, Codable, Hashable, Sendable {

    case monday = 1
    case tuesday = 2
    case wednesday = 3
    case thursday = 4
    case friday = 5
    case saturday = 6
    case sunday = 7

}

extension Weekday {
    var shortName: String {
        switch self {
        case .monday: "周一"
        case .tuesday: "周二"
        case .wednesday: "周三"
        case .thursday: "周四"
        case .friday: "周五"
        case .saturday: "周六"
        case .sunday: "周日"
        }
    }

    var isWeekend: Bool {
        self == .saturday || self == .sunday
    }
}

extension Weekday {
    init?(date: Date, calendar: Calendar = .current) {
        let foundationWeekday = calendar.component(.weekday, from: date)
        let isoValue = foundationWeekday == 1 ? 7 : foundationWeekday - 1
        self.init(rawValue: isoValue)
    }
}
