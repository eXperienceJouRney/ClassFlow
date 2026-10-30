import Foundation
import CoreGraphics

/// 手机周视图：日期列与至少两个星期标记共同确认列序，不根据课程内容猜星期。
struct TimetableImageCalendarLayout: Sendable {
    struct Column: Sendable {
        let weekday: Weekday
        let x: CGFloat
    }
    struct Period: Sendable {
        let number: Int
        let y: CGFloat
        let startTime: TimeOfDay?
        let endTime: TimeOfDay?
    }
    let columns: [Column]
    let columnWidth: CGFloat
    let periods: [Period]
    let rowHeight: CGFloat
    let displayedWeek: Int?

    var top: CGFloat { max(0, periods[0].y - rowHeight * 0.32) }
    var bottom: CGFloat { min(1, periods[periods.count - 1].y + rowHeight * 0.83) }
}

struct TimetableImageCard: Sendable {
    let bounds: CGRect
    let weekday: Weekday
    let startPeriod: Int?
    let endPeriod: Int?
}

struct TimetableImageCalendarParser: Sendable {
    func layout(in blocks: [TimetableOCRBlock]) -> TimetableImageCalendarLayout? {
        let numbers = blocks.filter {
            Int($0.text).map { (1...31).contains($0) } == true && $0.bounds.midY < 0.5
        }
        let weekdays = blocks.compactMap { block -> (Weekday, TimetableOCRBlock)? in
            guard let day = weekday(block.text) else { return nil }
            return (day, block)
        }
        for seed in numbers.sorted(by: { $0.bounds.midY < $1.bounds.midY }) {
            let dates = numbers.filter {
                abs($0.bounds.midY - seed.bounds.midY) < max(seed.bounds.height * 0.65, 0.007)
            }.sorted { $0.bounds.midX < $1.bounds.midX }
            guard (5...7).contains(dates.count) else { continue }
            let gaps = zip(dates, dates.dropFirst()).map { $1.bounds.midX - $0.bounds.midX }.sorted()
            let width = gaps[gaps.count / 2]
            guard width > 0.04, gaps.allSatisfy({ abs($0 - width) < width * 0.18 }),
                  zip(dates, dates.dropFirst()).allSatisfy({ left, right in
                      let a = Int(left.text)!, b = Int(right.text)!
                      return b == a + 1 || (a >= 28 && b == 1)
                  }) else { continue }
            var offsets: [Int] = []
            var markedColumns = Set<Int>()
            for (day, block) in weekdays {
                let gap = seed.bounds.minY - block.bounds.maxY
                guard gap > -0.005, gap < 0.055,
                      let index = dates.indices.min(by: {
                          abs(dates[$0].bounds.midX - block.bounds.midX) < abs(dates[$1].bounds.midX - block.bounds.midX)
                      }), abs(dates[index].bounds.midX - block.bounds.midX) < width * 0.25 else { continue }
                offsets.append(day.rawValue - index)
                markedColumns.insert(index)
            }
            // 只补有实际日期格的列；表头证据矛盾或不足时不进入手机布局分支。
            guard markedColumns.count >= 2, Set(offsets).count == 1, let offset = offsets.first,
                  offset >= 1, offset + dates.count - 1 <= 7 else { continue }
            let left = dates[0].bounds.midX - width * 0.45
            let labels = blocks.filter {
                $0.bounds.maxX < left && $0.bounds.midY > seed.bounds.maxY + 0.02
                    && Int($0.text).map { (1...30).contains($0) } == true
            }.sorted { $0.bounds.midY < $1.bounds.midY }
            guard labels.count >= 3,
                  zip(labels, labels.dropFirst()).allSatisfy({ Int($1.text)! == Int($0.text)! + 1 }) else { continue }
            let heights = zip(labels, labels.dropFirst()).map { $1.bounds.midY - $0.bounds.midY }.sorted()
            let height = heights[heights.count / 2]
            guard height > 0.015, heights.allSatisfy({ abs($0 - height) < height * 0.25 }) else { continue }
            let periods = labels.map { label in
                let times = blocks.filter {
                    $0.bounds.maxX < left && $0.bounds.midY > label.bounds.midY
                        && $0.bounds.midY < label.bounds.midY + height * 0.8
                }.sorted { $0.bounds.midY < $1.bounds.midY }.compactMap { time($0.text) }
                let valid = times.count == 2 && times[0] < times[1]
                return TimetableImageCalendarLayout.Period(number: Int(label.text)!, y: label.bounds.midY,
                    startTime: valid ? times[0] : nil, endTime: valid ? times[1] : nil)
            }
            let week = displayedWeek(in: blocks.filter { $0.bounds.maxY < seed.bounds.minY })
            return TimetableImageCalendarLayout(
                columns: dates.enumerated().map { .init(weekday: Weekday(rawValue: offset + $0.offset)!, x: $0.element.bounds.midX) },
                columnWidth: width, periods: periods, rowHeight: height, displayedWeek: week)
        }
        return nil
    }

    func parse(_ cards: [TimetableImageCard], blocks: [TimetableOCRBlock], layout: TimetableImageCalendarLayout,
               draftId: UUID) -> [ImportDraftEntry] {
        cards.compactMap { card -> ImportDraftEntry? in
            let cell = blocks.filter { card.bounds.contains(CGPoint(x: $0.bounds.midX, y: $0.bounds.midY)) }
                .sorted { $0.bounds.midY < $1.bounds.midY }
            let rawLines = cell.map(\.text)
            let inactive = rawLines.contains { $0.contains("非本周") }
            let lines = rawLines.filter { !$0.contains("非本周") && !$0.isBlank }
            guard !lines.isEmpty else { return nil }
            let metadata = lines.firstIndex { locationMarker($0) || isMetadata($0) } ?? lines.count
            let name = joined(Array(lines.prefix(metadata)))
            guard !name.isBlank else { return nil }
            let text = TimetableImageLayoutParser.normalize(lines.joined(separator: ","))
            var entry = PlainTextTimetableParser().parse(text, draftId: draftId).entries.first
                ?? ImportDraftEntry(draftId: draftId, sourceIndex: 0)
            entry.courseName = name
            TimetableImageLayoutParser().applyWeekRanges(in: text, to: &entry)
            entry.weekday = card.weekday
            entry.startPeriod = card.startPeriod
            entry.endPeriod = card.endPeriod
            if let index = lines.firstIndex(where: locationMarker) {
                let room = lines[index...].prefix { !isMetadata($0) || locationMarker($0) }
                entry.location = joined(Array(room)).replacingOccurrences(
                    of: #"^(?:[@＠◎]|(?:上课地点|地点|教室)\s*[:：])\s*"#, with: "", options: .regularExpression).normalizedOrNil
            }
            // 课程自己的周次优先；否则正常课程只排在图片明确显示的这一周。
            let hasWeeks = match(#"(?:第?\s*[0-9]{1,2}(?:\s*[-–—~～至到,、，]\s*[0-9]{1,2})*\s*周|单周|双周)"#, text) != nil
            let defaultWeek = !hasWeeks && !inactive ? layout.displayedWeek : nil
            if let defaultWeek {
                entry.weekRule = WeekRule(startWeek: defaultWeek, endWeek: defaultWeek)
            }
            var notes: [String] = []
            if inactive { notes.append("原图标记「非本周」，已默认取消勾选；需要时请补全周次后再选中。") }
            if let defaultWeek {
                notes.append("已按图片默认选择第\(defaultWeek)周，仅导入这一周；需要时可修改周次。")
            } else if !hasWeeks {
                notes.append("未识别到本课程的上课周次，请在修改记录中选择并确认。")
            }
            if let location = entry.location, location.contains("…") || location.hasSuffix(".") {
                notes.append("原图教室被省略，请核对并补全。")
            } else if entry.location == nil { notes.append("未识别到教室，可对照原图补充。") }
            if let start = layout.periods.first(where: { $0.number == card.startPeriod })?.startTime,
               let end = layout.periods.first(where: { $0.number == card.endPeriod })?.endTime {
                notes.append("原图钟点 \(start.displayText)–\(end.displayText)；按课节导入时请核对学期作息。")
            }
            entry.imageReview = ImportImageReview(notes: notes, requiresWeekConfirmation: !hasWeeks && defaultWeek == nil)
            entry.rawPayload = rawLines.joined(separator: "\n")
            entry.isSelected = !inactive
            entry.status = inactive ? .skipped : .parsed
            return entry
        }.enumerated().map { index, value in
            var entry = value
            entry.sourceIndex = index
            return entry
        }
    }

    private func weekday(_ text: String) -> Weekday? {
        let text = text.filter { !$0.isWhitespace }
        if let day = PlainTextTimetableParser.weekday(from: text), Int(text) == nil { return day }
        guard let groups = match(#"^(?:星期|周|礼拜)([一二三四五六日天1-7])$"#, text) else { return nil }
        return PlainTextTimetableParser.weekday(from: groups[0])
    }

    private func displayedWeek(in blocks: [TimetableOCRBlock]) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"第\s*([0-9]{1,2}|[一二三四五六七八九十两]{1,3})\s*周"#) else { return nil }
        let values = blocks.flatMap { block in
            regex.matches(in: block.text, range: NSRange(block.text.startIndex..., in: block.text)).compactMap { match -> Int? in
                guard let range = Range(match.range(at: 1), in: block.text) else { return nil }
                let token = String(block.text[range])
                if let value = Int(token) { return value }
                let digits: [Character: Int] = ["一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
                if token == "十" { return 10 }
                if token.count == 1, let first = token.first { return digits[first] }
                let parts = token.split(separator: "十", omittingEmptySubsequences: false)
                guard parts.count == 2, parts.allSatisfy({ $0.count <= 1 }) else { return nil }
                let tens = parts[0].first.flatMap { digits[$0] } ?? 1
                let units = parts[1].first.flatMap { digits[$0] } ?? 0
                return tens * 10 + units
            }
        }
        // 多个不同周数、零周等不能作为自动默认值，交给用户补充。
        guard values.allSatisfy({ $0 >= 1 }), Set(values).count == 1 else { return nil }
        return values.first
    }

    private func time(_ text: String) -> TimeOfDay? {
        guard let groups = match(#"^([0-9]{1,2})[:：]([0-9]{2})$"#, text),
              let h = Int(groups[0]), let m = Int(groups[1]) else { return nil }
        return TimeOfDay(hour: h, minute: m)
    }

    private func locationMarker(_ text: String) -> Bool {
        match(#"^(?:[@＠◎]|(?:上课地点|地点|教室)\s*[:：])"#, text) != nil
    }

    private func isMetadata(_ text: String) -> Bool {
        match(#"^(?:第?\s*[0-9].*(?:周|节)|[单双]周|(?:任课教师|授课教师|教师|老师)\s*[:：]|.*(?:老师|教授)$)"#, text) != nil
    }

    private func joined(_ lines: [String]) -> String {
        lines.reduce("") { result, line in
            // 中文窄列换行直接接续；英文单词之间保留空格，教室字母数字相连。
            let space = result.last?.isASCII == true && result.last?.isLetter == true
                && line.first?.isASCII == true && line.first?.isLetter == true
            return result + (space ? " " : "") + line.trimmingCharacters(in: .whitespaces)
        }
    }

    private func match(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<result.numberOfRanges).map {
            Range(result.range(at: $0), in: text).map { String(text[$0]) } ?? ""
        }
    }
}
