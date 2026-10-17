import Foundation

struct TimeOfDay: Hashable, Comparable, Codable, Sendable {

    let hour: Int

    let minute: Int

    init?(hour: Int, minute: Int) {
        guard (0...23).contains(hour), (0...59).contains(minute) else {
            return nil
        }
        self.hour = hour
        self.minute = minute
    }

    var minutesFromMidnight: Int { hour * 60 + minute }

    var displayText: String { String(format: "%02d:%02d", hour, minute) }
}

extension TimeOfDay {
    init?(_ text: String) {
        let parts = text.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1])
        else {
            return nil
        }
        self.init(hour: hour, minute: minute)
    }
}


extension TimeOfDay {
    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesFromMidnight < rhs.minutesFromMidnight
    }
}
