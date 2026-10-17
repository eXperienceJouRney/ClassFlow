import Foundation

struct TimeRange: Hashable, Comparable, Sendable {

    let start: TimeOfDay
    let end: TimeOfDay

    init?(start: TimeOfDay, end: TimeOfDay) {
        guard start < end else { return nil }
        self.start = start
        self.end = end
    }
}

extension TimeRange {

    var durationMinutes: Int {
        end.minutesFromMidnight - start.minutesFromMidnight
    }

    var displayText: String {
        "\(start.displayText)-\(end.displayText)"
    }

    func overlaps(_ other: TimeRange) -> Bool {
        start < other.end && other.start < end
    }

    static func < (lhs: TimeRange, rhs: TimeRange) -> Bool {
        (lhs.start, lhs.end) < (rhs.start, rhs.end)
    }
}
