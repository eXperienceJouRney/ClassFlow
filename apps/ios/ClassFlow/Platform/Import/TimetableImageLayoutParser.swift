import Foundation
import CoreGraphics

/// OCR 坐标统一为左上角原点、0...1；不依赖 Vision，便于用布局夹具验证。
struct TimetableOCRBlock: Sendable {
    let text: String
    let bounds: CGRect
    let confidence: Float
}

/// 根据星期与课节标签确定表格方向，也支持同列星期引导的日程卡片。
/// 布局证据不足时仅接受含时间的逐行课程，不用固定模板或课程名猜测安排。
/// 不推测被裁掉的星期，也不把页标题、姓名等孤立文字当作课程。
struct TimetableImageLayoutParser: Sendable {
    func parse(_ blocks: [TimetableOCRBlock], draftId: UUID) -> [ImportDraftEntry] {
        let blocks = blocks.filter { !$0.text.isBlank && $0.bounds.width > 0 && $0.bounds.height > 0 }
        if let entries = parseCourseDetails(blocks, draftId: draftId) { return entries }
        let headers = weekdayHeaders(in: blocks)
        guard headers.count >= 2 else {
            if let entries = parseWeekdayRows(blocks, draftId: draftId) { return entries }
            if let entries = parseAgenda(blocks, draftId: draftId) { return entries }
            return parseLines(blocks, draftId: draftId)
        }

        let spacings = zip(headers, headers.dropFirst()).compactMap { left, right -> CGFloat? in
            let days = right.day.rawValue - left.day.rawValue
            return days > 0 ? (right.block.bounds.midX - left.block.bounds.midX) / CGFloat(days) : nil
        }.sorted()
        guard let width = spacings.dropFirst(spacings.count / 2).first, width > 0.025 else { return [] }
        let top = headers.map { $0.block.bounds.maxY }.max() ?? 0
        let leftEdge = headers[0].block.bounds.midX - width / 2
        let anchors = periodAnchors(in: blocks.filter { $0.bounds.maxX < leftEdge + width * 0.12 && $0.bounds.midY > top })
        var entries: [ImportDraftEntry] = []

        for header in headers {
            let column = blocks.filter { block in
                block.bounds.minY >= top - 0.003
                    && abs(block.bounds.midX - header.block.bounds.midX) < width * 0.49
                    && block.bounds.width < width * 1.35
                    && Self.weekday(block.text) == nil
                    && !Self.isDecoration(block.text)
            }.sorted { $0.bounds.midY < $1.bounds.midY }

            var groups: [[TimetableOCRBlock]] = []
            for block in column {
                if let last = groups.last?.last {
                    let gap = block.bounds.minY - last.bounds.maxY
                    let splitAtRow = anchors.contains { $0.end > $0.start }
                        && anchorIndex(for: block.bounds.midY, anchors: anchors) != anchorIndex(for: last.bounds.midY, anchors: anchors)
                    if gap > max(last.bounds.height * 1.8, 0.022) || splitAtRow {
                        groups.append([block])
                    } else {
                        groups[groups.count - 1].append(block)
                    }
                } else {
                    groups.append([block])
                }
            }

            for group in groups {
                guard var entry = parseCell(group, draftId: draftId, index: entries.count) else { continue }
                entry.weekday = header.day
                if !entry.hasPeriodInformation && !entry.hasCustomTimeInformation,
                   let first = group.first, let last = group.last,
                   let index = anchorIndex(for: (first.bounds.minY + last.bounds.maxY) / 2, anchors: anchors) {
                    let anchor = anchors[index]
                    // 跨多行的文字块无法可靠推断结束课节，留给用户填写。
                    if anchor.start != anchor.end || anchorIndex(for: first.bounds.midY, anchors: anchors) == anchorIndex(for: last.bounds.midY, anchors: anchors) {
                        entry.startPeriod = anchor.start
                        entry.endPeriod = anchor.end
                    }
                }
                entries.append(entry)
            }
        }
        return entries
    }
}

private extension TimetableImageLayoutParser {
    struct Header {
        let day: Weekday
        let block: TimetableOCRBlock
    }

    struct PeriodAnchor {
        let start: Int
        let end: Int
        let y: CGFloat
    }

    /// 星期纵排必须在同一列，且从上到下递增；卡片列表允许重复星期。
    func weekdayColumns(in blocks: [TimetableOCRBlock], allowsRepeatedDays: Bool = false) -> [[Header]] {
        let candidates = blocks.compactMap { block -> Header? in
            Self.weekday(block.text).map { Header(day: $0, block: block) }
        }
        return candidates.map { seed in
            candidates.filter {
                abs($0.block.bounds.midX - seed.block.bounds.midX) < max(seed.block.bounds.height, 0.018)
            }.sorted { $0.block.bounds.midY < $1.block.bounds.midY }
        }.filter { column in
            column.count >= 2 && zip(column, column.dropFirst()).allSatisfy {
                allowsRepeatedDays ? $0.day.rawValue <= $1.day.rawValue : $0.day.rawValue < $1.day.rawValue
            }
        }.sorted { $0.count > $1.count }
    }

    func parseWeekdayRows(_ blocks: [TimetableOCRBlock], draftId: UUID) -> [ImportDraftEntry]? {
        for days in weekdayColumns(in: blocks) {
            let top = days[0].block.bounds.minY
            let left = days.map { $0.block.bounds.maxX }.max() ?? 0
            let labels = blocks.filter { $0.bounds.maxY < top && $0.bounds.minX > left }
                .filter { Self.periodRange($0.text) != nil }
            let rows = labels.map { seed in
                labels.filter { abs($0.bounds.midY - seed.bounds.midY) < max(seed.bounds.height, 0.018) }
                    .sorted { $0.bounds.midX < $1.bounds.midX }
            }.filter { row in
                row.count >= 2 && zip(row, row.dropFirst()).allSatisfy {
                    Self.periodRange($0.text)!.end < Self.periodRange($1.text)!.start
                }
            }
            guard let periods = rows.max(by: { $0.count < $1.count }) else { continue }
            let daySpacings = zip(days, days.dropFirst()).map {
                ($1.block.bounds.midY - $0.block.bounds.midY) / CGFloat($1.day.rawValue - $0.day.rawValue)
            }.sorted()
            let height = daySpacings[daySpacings.count / 2]
            guard height > 0.025 else { continue }
            // 按节次跨度计算横向单位宽度，缺失的节次列不会并入邻列。
            let periodSpacings = zip(periods, periods.dropFirst()).map {
                ($1.bounds.midX - $0.bounds.midX) / CGFloat(Self.periodRange($1.text)!.start - Self.periodRange($0.text)!.start)
            }.sorted()
            let unitWidth = periodSpacings[periodSpacings.count / 2]
            guard unitWidth > 0.012 else { continue }
            var entries: [ImportDraftEntry] = []
            for day in days {
                for label in periods {
                    let range = Self.periodRange(label.text)!
                    let width = unitWidth * CGFloat(range.end - range.start + 1)
                    let cell = blocks.filter {
                        abs($0.bounds.midY - day.block.bounds.midY) < height * 0.49
                            && abs($0.bounds.midX - label.bounds.midX) < width * 0.49
                            && $0.bounds.minY > label.bounds.maxY
                            && $0.bounds.minX > left
                            && Self.weekday($0.text) == nil && !Self.isDecoration($0.text)
                    }
                    guard var entry = parseCell(readingOrder(cell), draftId: draftId, index: entries.count) else { continue }
                    entry.weekday = day.day
                    if !entry.hasPeriodInformation && !entry.hasCustomTimeInformation {
                        entry.startPeriod = range.start
                        entry.endPeriod = range.end
                    }
                    entries.append(entry)
                }
            }
            return entries
        }
        return nil
    }

    func parseAgenda(_ blocks: [TimetableOCRBlock], draftId: UUID) -> [ImportDraftEntry]? {
        for labels in weekdayColumns(in: blocks, allowsRepeatedDays: true) {
            var entries: [ImportDraftEntry] = []
            for (index, label) in labels.enumerated() {
                let top = label.block.bounds.minY - label.block.bounds.height * 0.45
                let bottom = index + 1 < labels.count
                    ? labels[index + 1].block.bounds.minY - labels[index + 1].block.bounds.height * 0.45 : 1
                let cell = readingOrder(blocks.filter {
                    $0.bounds.midY >= top && $0.bounds.midY < bottom
                        && $0.bounds.minX >= label.block.bounds.minX - label.block.bounds.height
                        && !Self.isDecoration($0.text)
                })
                // 卡片必须自带课节或钟点；只有星期和零散文字不组成课程。
                guard cell.contains(where: { Self.hasScheduleMetadata(Self.normalize($0.text)) }),
                      var entry = parseCell(cell, draftId: draftId, index: entries.count),
                      entry.hasPeriodInformation || entry.hasCustomTimeInformation else { continue }
                entry.weekday = label.day
                entries.append(entry)
            }
            if entries.count >= 2 { return entries }
        }
        return nil
    }

    /// 教务系统的课程详情以标题统领多条安排，时间与教室通常分行显示。
    /// 用「开课对象 + 课表 + 时间」确认卡片结构，不依赖学校、课程名或屏幕尺寸。
    func parseCourseDetails(_ blocks: [TimetableOCRBlock], draftId: UUID) -> [ImportDraftEntry]? {
        let rows = readingRows(blocks).map { row in
            TimetableOCRBlock(text: row.map { Self.normalize($0.text) }.joined(separator: " "),
                bounds: row.reduce(CGRect.null) { $0.union($1.bounds) },
                confidence: row.map(\.confidence).min() ?? 0)
        }
        let markers = rows.indices.filter {
            Self.match(#"^(?:开课对象|授课对象|面向对象)\s*[:：]?"#, rows[$0].text) != nil
        }
        func isSection(_ text: String) -> Bool {
            Self.match(#"^(?:课表|上课安排|课程安排|教学安排)\s*[:：]?\s*[vV∨⌄▾▼>]?$"#, text) != nil
        }
        func isTime(_ text: String) -> Bool {
            Self.match(#"^(?:时间|上课时间|授课时间)\s*[:：]"#, text) != nil && Self.hasScheduleMetadata(text)
        }
        guard !markers.isEmpty, rows.contains(where: { isSection($0.text) }),
              rows.contains(where: { isTime($0.text) }) else { return nil }

        var entries: [ImportDraftEntry] = []
        for (offset, marker) in markers.enumerated() {
            guard marker > 0 else { continue }
            let title = rows[marker - 1]
            let audience = rows[marker]
            let name = title.text.replacingOccurrences(of: #"^(?:课程名称|课程名|课程)\s*[:：]\s*"#,
                with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            // 标题必须紧邻且对齐；缺失标题时不借用页面标题、查询条件或另一张卡片。
            guard title.bounds.maxY <= audience.bounds.minY,
                  audience.bounds.minY - title.bounds.maxY < max(title.bounds.height * 5, 0.06),
                  abs(title.bounds.minX - audience.bounds.minX) < max(title.bounds.height * 2, 0.035),
                  name.contains(where: \.isLetter), !Self.isMetadata(name), !Self.isDecoration(name),
                  !Self.hasScheduleMetadata(name),
                  Self.match(#"^(?:学期|查询|请输入|开课对象|授课对象|面向对象|共\s*\d+|总计\s*\d+)|^(?:课程|课表)$"#, name) == nil else { continue }
            let end = offset + 1 < markers.count ? max(marker + 1, markers[offset + 1] - 1) : rows.count
            let card = (marker + 1)..<end
            guard let section = card.first(where: { isSection(rows[$0].text) }) else { continue }
            let times = card.filter { $0 > section && isTime(rows[$0].text) }
            for (timeOffset, time) in times.enumerated() {
                let next = timeOffset + 1 < times.count ? times[timeOffset + 1] : end
                let fields = rows[time..<next].filter {
                    Self.match(#"^(?:时间|上课时间|授课时间|周次|上课周次|任课教师|授课教师|教师|老师|教室|地点|上课地点|上课教室)\s*[:：]"#, $0.text) != nil
                }
                guard var entry = parseCell([title] + fields, draftId: draftId, index: entries.count) else { continue }
                entry.courseName = name
                entries.append(entry)
            }
        }
        // 已确认详情布局但没有可信标题时，留给本地失败 / AI 后备流程，不能退回逐行猜课名。
        return entries
    }

    func readingOrder(_ blocks: [TimetableOCRBlock]) -> [TimetableOCRBlock] {
        readingRows(blocks).flatMap { $0 }
    }

    func readingRows(_ blocks: [TimetableOCRBlock]) -> [[TimetableOCRBlock]] {
        var rows: [[TimetableOCRBlock]] = []
        for block in blocks.sorted(by: { $0.bounds.midY < $1.bounds.midY }) {
            if let first = rows.last?.first,
               abs(first.bounds.midY - block.bounds.midY) < max(min(first.bounds.height, block.bounds.height) * 0.55, 0.004) {
                rows[rows.count - 1].append(block)
            } else { rows.append([block]) }
        }
        return rows.map { $0.sorted { $0.bounds.minX < $1.bounds.minX } }
    }

    static func periodRange(_ text: String) -> (start: Int, end: Int)? {
        guard let groups = match(#"^第?\s*([0-9]{1,2})(?:\s*[-–—~～至到、,]\s*([0-9]{1,2}))?\s*节?$"#, normalize(text)),
              let start = Int(groups[0]), (1...30).contains(start) else { return nil }
        let end = Int(groups[1]) ?? start
        guard (start...30).contains(end) else { return nil }
        return (start, end)
    }

    func weekdayHeaders(in blocks: [TimetableOCRBlock]) -> [Header] {
        let candidates = blocks.compactMap { block -> Header? in
            guard let day = Self.weekday(block.text) else { return nil }
            return Header(day: day, block: block)
        }
        // 多个星期必须确实在同一横行，避免把纵向的日程列表误认为课表表头。
        return candidates.map { seed in
            var seen = Set<Weekday>()
            return candidates.filter { abs($0.block.bounds.midY - seed.block.bounds.midY) < max(seed.block.bounds.height, 0.018) }
                .sorted { $0.block.bounds.midX < $1.block.bounds.midX }
                .filter { seen.insert($0.day).inserted }
        }.filter { row in
            zip(row, row.dropFirst()).allSatisfy { $0.day.rawValue < $1.day.rawValue }
        }.max(by: { $0.count < $1.count }) ?? []
    }

    static func weekday(_ text: String) -> Weekday? {
        let text = text.filter { !$0.isWhitespace }
        if let groups = match(#"^(?:星期|周|礼拜)([一二三四五六日天1-7])(?:\(?\d{1,2}[/月.-]\d{1,2}日?\)?)?$"#, text) {
            return PlainTextTimetableParser.weekday(from: groups[0])
        }
        let short = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
        let full = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        let token = text.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if let index = short.firstIndex(of: token) ?? full.firstIndex(of: token) {
            return Weekday(rawValue: index + 1)
        }
        return nil
    }

    func periodAnchors(in blocks: [TimetableOCRBlock]) -> [PeriodAnchor] {
        blocks.compactMap { block in
            guard let range = Self.periodRange(block.text) else { return nil }
            return PeriodAnchor(start: range.start, end: range.end, y: block.bounds.midY)
        }.sorted { $0.y < $1.y }
    }

    func anchorIndex(for y: CGFloat, anchors: [PeriodAnchor]) -> Int? {
        guard anchors.count >= 2 else { return nil }
        let distances = zip(anchors, anchors.dropFirst()).map { $1.y - $0.y }.sorted()
        let spacing = distances[distances.count / 2]
        guard let index = anchors.indices.min(by: { abs(anchors[$0].y - y) < abs(anchors[$1].y - y) }),
              abs(anchors[index].y - y) <= spacing * 0.55 else { return nil }
        return index
    }

    func parseCell(_ blocks: [TimetableOCRBlock], draftId: UUID, index: Int) -> ImportDraftEntry? {
        let lines = blocks.map { Self.normalize($0.text) }
        let text = lines.joined(separator: ",")
        guard var entry = PlainTextTimetableParser().parse(text, draftId: draftId, startingIndex: index).entries.first,
              !entry.courseName.isBlank else { return nil }
        // 首行整段保留课程名，避免英文课名被空格截断。带元信息的单行仍交给文本解析器。
        if let first = lines.first(where: {
            !Self.isMetadata($0) && Self.weekday($0) == nil && Self.periodRange($0) == nil && !Self.isDecoration($0)
        }), !Self.hasScheduleMetadata(first) {
            entry.courseName = first
                .replacingOccurrences(of: #"^(?:课程名称|课程名|课程)\s*[:：]\s*"#, with: "", options: .regularExpression)
        }
        guard entry.courseName.contains(where: \.isLetter),
              Self.weekday(entry.courseName) == nil,
              !Self.isMetadata(entry.courseName), !Self.isDecoration(entry.courseName) else { return nil }
        applyWeekRanges(in: text, to: &entry)
        entry.rawPayload = blocks.map(\.text).joined(separator: "\n")
        entry.markParsed()
        return entry
    }

}

extension TimetableImageLayoutParser {
    // 每段可各带一个「周」，也可只在末尾写单位；匹配不得从前一行的空白开始。
    static let weekListPattern = #"(?<![0-9])((?:第\s*)?[0-9]{1,2}(?:\s*[-–—~～至到]\s*[0-9]{1,2})?(?:\s*周?\s*[,、，]\s*(?:第\s*)?[0-9]{1,2}(?:\s*[-–—~～至到]\s*[0-9]{1,2})?)*)\s*周"#
    static let weekExclusionPattern = #"(?:[（(]\s*)?(?:排除|除)\s*第?\s*[0-9]+(?:\s*[,、，]\s*[0-9]+)*\s*周(?:\s*[）)])?"#

    static func weekExclusionRanges(in text: String) -> [Range<String.Index>] {
        guard let regex = try? NSRegularExpression(pattern: weekExclusionPattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text) }
    }

    static func removingWeekExclusions(from text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: weekExclusionPattern) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
    }

    func applyWeekRanges(in text: String, to entry: inout ImportDraftEntry) {
        // 排除周已由文本解析器保留，不能将它们覆盖为正向上课周次。
        let positiveText = Self.removingWeekExclusions(from: text)
        guard let groups = Self.match(Self.weekListPattern, positiveText),
              groups[0].rangeOfCharacter(from: CharacterSet(charactersIn: ",、，")) != nil else { return }
        var weeks = Set<Int>()
        for part in groups[0].components(separatedBy: CharacterSet(charactersIn: ",、，")) {
            let numbers = part.replacingOccurrences(of: "周", with: "").replacingOccurrences(of: "第", with: "")
            let values = PlainTextTimetableParser.numbers(in: numbers)
            guard let first = values.first, first >= 1 else { return }
            if let range = Self.match(#"^\s*([0-9]+)\s*[-–—~～至到]\s*([0-9]+)\s*$"#, numbers),
               let start = Int(range[0]), let end = Int(range[1]) {
                guard start <= end else { return }
                weeks.formUnion(start...end)
            } else {
                weeks.formUnion(values)
            }
        }
        if entry.weekPattern == .oddWeeks { weeks = weeks.filter { $0 % 2 == 1 } }
        if entry.weekPattern == .evenWeeks { weeks = weeks.filter { $0 % 2 == 0 } }
        weeks.subtract(entry.excludedWeeks)
        entry.startWeek = nil
        entry.endWeek = nil
        entry.weekPattern = .customWeeks
        entry.customWeeks = weeks.sorted()
    }
}

private extension TimetableImageLayoutParser {
    func parseLines(_ blocks: [TimetableOCRBlock], draftId: UUID) -> [ImportDraftEntry] {
        var rows: [[TimetableOCRBlock]] = []
        for block in blocks.sorted(by: { $0.bounds.midY < $1.bounds.midY }) {
            if let first = rows.last?.first, abs(first.bounds.midY - block.bounds.midY) < max(first.bounds.height * 0.55, 0.007) {
                rows[rows.count - 1].append(block)
            } else {
                rows.append([block])
            }
        }
        return rows.enumerated().compactMap { index, row in
            let sorted = row.sorted { $0.bounds.minX < $1.bounds.minX }
            let text = sorted.map(\.text).joined(separator: ",")
            guard Self.hasScheduleMetadata(text) else { return nil }
            return parseCell(sorted, draftId: draftId, index: index)
        }
    }

}

extension TimetableImageLayoutParser {
    static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            // 限定在周规则上下文，避免改动「单片机」等课程名。
            .replacingOccurrences(of: #"[単單](?=\s*周|\s*\))"#, with: "单", options: .regularExpression)
            .replacingOccurrences(of: #"雙(?=\s*周|\s*\))"#, with: "双", options: .regularExpression)
            .replacingOccurrences(of: #"([单双])\s+周"#, with: "$1周", options: .regularExpression)
            // 小字 OCR 会把数字范围中的横线读成长音符或减号；只在两侧均为数字时归一化。
            .replacingOccurrences(of: #"(?<=[0-9])\s*[‐‑‒―−﹘﹣－ー]\s*(?=[0-9])"#, with: "-", options: .regularExpression)
            .replacingOccurrences(of: #"\(([0-9]+(?:\s*[-–—,、]\s*[0-9]+)*)\s*节\)"#, with: "$1节", options: .regularExpression)
            .replacingOccurrences(of: #"\(([单双])\)"#, with: "$1周", options: .regularExpression)
            .replacingOccurrences(of: #"\(([单双])周\)"#, with: "$1周", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension TimetableImageLayoutParser {
    static func hasScheduleMetadata(_ text: String) -> Bool {
        match(#"([0-9]{1,2}\s*[-–—~～至到]\s*[0-9]{1,2}\s*节|第\s*[0-9]{1,2}\s*节|[0-9]{1,2}[:：][0-9]{2}\s*[-–—~～至到]\s*[0-9]{1,2}[:：][0-9]{2})"#, text) != nil
    }

    static func isMetadata(_ text: String) -> Bool {
        match(#"^(?:第?\s*[0-9].*(?:周|节)|[单双]周|(?:时间|上课时间|授课时间|周次|上课周次|任课教师|授课教师|教师|老师|教室|地点|上课地点|上课教室|开课对象|授课对象|面向对象)\s*[:：]|.*(?:老师|教授)$)"#, text) != nil
            || match(#"^[0-9]{1,2}[:：][0-9]{2}"#, text) != nil
    }

    static func isDecoration(_ text: String) -> Bool {
        ["上午", "下午", "晚上", "中午", "午休", "晚休", "时间", "节次", "节数", "星期", "备注", "无课"].contains(text)
            || match(#"^(?:\d{1,2}[/月.-]\d{1,2}日?|第\s*\d+\s*周|.*(?:学期|课程表|课表))$"#, text) != nil
    }

    static func match(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }
}
