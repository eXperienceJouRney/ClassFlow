import Foundation

// MARK: - 规则定义
struct WeekRule: Hashable, Codable, Sendable, Validatable {

    var startWeek: Int?
    var endWeek: Int?
    var pattern: WeekPattern
    var customWeeks: [Int]
    var excludedWeeks: [Int]

    init(
        startWeek: Int? = nil,
        endWeek: Int? = nil,
        pattern: WeekPattern = .everyWeek,
        customWeeks: [Int] = [],
        excludedWeeks: [Int] = []
    ) {
        self.startWeek = startWeek
        self.endWeek = endWeek
        self.pattern = pattern
        self.customWeeks = customWeeks
        self.excludedWeeks = excludedWeeks
    }
}

// MARK: - 规范化
extension WeekRule {

    var normalizedCustomWeeks: [Int] {
        Array(Set(customWeeks)).sorted()
    }

    var normalizedExcludedWeeks: [Int] {
        Array(Set(excludedWeeks)).sorted()
    }

    mutating func normalize() {
        let weeks = normalizedCustomWeeks
        customWeeks = pattern.requiresCustomWeeks ? weeks : []
        excludedWeeks = normalizedExcludedWeeks
    }

    func normalized() -> WeekRule {
        var copy = self
        copy.normalize()
        return copy
    }
}

// MARK: - 周次判断
extension WeekRule {

    func contains(week: Int) -> Bool {
        guard week > 0 else { return false }

        if let startWeek, week < startWeek { return false }
        if let endWeek, week > endWeek { return false }
        guard pattern.matches(week: week, customWeeks: customWeeks) else { return false }

        return !excludedWeeks.contains(week)
    }

    func resolvedWeeks(upTo weekCount: Int) -> [Int] {
        guard weekCount >= 1 else { return [] }
        return (1...weekCount).filter { contains(week: $0) }
    }

    func coversEveryWeek(upTo weekCount: Int) -> Bool {
        guard weekCount >= 1 else { return false }
        return resolvedWeeks(upTo: weekCount).count == weekCount
    }
}

// MARK: - 规则压缩
extension WeekRule {

    /// 从勾选的周次反推最简洁的规则：全选 → 每周，整学期单 / 双周 → 单周 / 双周，连续段 → 起止周，否则 → 指定周次。
    static func compact(weeks: Set<Int>, weekCount: Int) -> WeekRule {
        let total = max(weekCount, 1)
        let selected = weeks.filter { (1...total).contains($0) }
        let sorted = selected.sorted()

        guard let first = sorted.first, let last = sorted.last else {
            // 一周都没选：返回空规则，交由 `missingCustomWeeks` 校验拦下。
            return WeekRule(pattern: .customWeeks, customWeeks: [])
        }

        if sorted.count == total { return WeekRule() }

        let oddWeeks = Set(stride(from: 1, through: total, by: 2))
        let evenWeeks = Set(stride(from: 2, through: total, by: 2))

        if selected == oddWeeks {
            return WeekRule(startWeek: first, endWeek: last, pattern: .oddWeeks)
        }
        if selected == evenWeeks {
            return WeekRule(startWeek: first, endWeek: last, pattern: .evenWeeks)
        }
        if last - first + 1 == sorted.count {
            return WeekRule(startWeek: first, endWeek: last)
        }

        return WeekRule(pattern: .customWeeks, customWeeks: sorted)
    }

    /// 该规则在 `weekCount` 周内实际会上课的周次（编辑器用它回填勾选状态）。
    func selectedWeeks(upTo weekCount: Int) -> Set<Int> {
        Set(resolvedWeeks(upTo: weekCount))
    }
}

// MARK: - 文案
extension WeekRule {

    var rangeDescription: String? {
        switch (startWeek, endWeek) {
        case let (start?, end?): "\(start)–\(end) 周"
        case let (start?, nil): "第 \(start) 周起"
        case let (nil, end?): "第 \(end) 周止"
        case (nil, nil): nil
        }
    }

    var displayName: String {
        var text = baseDescription

        let excluded = normalizedExcludedWeeks
        if !excluded.isEmpty {
            text += "（除第 \(excluded.map(String.init).joined(separator: "、")) 周）"
        }

        return text
    }

    private var baseDescription: String {
        switch pattern {
        case .customWeeks:
            let weeks = normalizedCustomWeeks
            guard !weeks.isEmpty else { return "未指定周次" }
            return "第 \(weeks.map(String.init).joined(separator: "、")) 周"
        case .everyWeek:
            return rangeDescription ?? "每周"
        case .oddWeeks, .evenWeeks:
            return [rangeDescription, pattern.displayName].compactMap { $0 }.joined(separator: " ")
        }
    }
}

// MARK: - 校验
extension WeekRule {

    var validationErrors: [ValidationError] {
        var errors: [ValidationError] = []

        if let startWeek, startWeek < 1 {
            errors.append(.invalidWeekNumber(week: startWeek))
        }
        if let endWeek, endWeek < 1 {
            errors.append(.invalidWeekNumber(week: endWeek))
        }
        if let startWeek, let endWeek, startWeek > endWeek {
            errors.append(.invalidWeekRange(startWeek: startWeek, endWeek: endWeek))
        }

        for week in customWeeks where week < 1 {
            errors.append(.invalidWeekNumber(week: week))
        }
        for week in excludedWeeks where week < 1 {
            errors.append(.invalidWeekNumber(week: week))
        }

        if pattern.requiresCustomWeeks && customWeeks.isEmpty {
            errors.append(.missingCustomWeeks)
        }
        if !pattern.requiresCustomWeeks && !customWeeks.isEmpty {
            errors.append(.unexpectedCustomWeeks)
        }

        if hasUsableBounds {
            for week in customWeeks where week >= 1 && !isWithinBounds(week) {
                errors.append(.weekOutOfRange(field: "指定周次", week: week))
            }
            for week in excludedWeeks where week >= 1 && !isWithinBounds(week) {
                errors.append(.weekOutOfRange(field: "排除周次", week: week))
            }
        }

        for week in normalizedCustomWeeks where normalizedExcludedWeeks.contains(week) {
            errors.append(.weekIncludedAndExcluded(week: week))
        }

        return errors
    }

    private var hasUsableBounds: Bool {
        if let startWeek, startWeek < 1 { return false }
        if let endWeek, endWeek < 1 { return false }
        if let startWeek, let endWeek, startWeek > endWeek { return false }
        return true
    }

    private func isWithinBounds(_ week: Int) -> Bool {
        if let startWeek, week < startWeek { return false }
        if let endWeek, week > endWeek { return false }
        return true
    }
}
