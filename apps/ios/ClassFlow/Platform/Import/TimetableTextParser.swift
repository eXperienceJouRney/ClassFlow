import Foundation

// MARK: - 解析结果
/// 导入解析结果。
struct TimetableParseOutcome: Hashable, Sendable {

    var entries: [ImportDraftEntry]
    var unparsedLines: [String]

    static let empty = TimetableParseOutcome(entries: [], unparsedLines: [])
}

// MARK: - 解析器协议
/// 文本课表解析器的适配器接口。
/// 解析结果只作为候选数据，识别成功不等于导入成功。
protocol TimetableTextParser: Sendable {

    func parse(_ text: String, draftId: UUID, startingIndex: Int) -> TimetableParseOutcome
}

// MARK: - 纯文本解析器
/// 首版支持的纯文本 / CSV 课表解析器。
/// 每行一条候选记录，字段顺序不限；行内第一个无法识别的片段作为课程名称。
struct PlainTextTimetableParser: TimetableTextParser {

    func parse(_ text: String, draftId: UUID, startingIndex: Int = 0) -> TimetableParseOutcome {
        var entries: [ImportDraftEntry] = []
        var unparsed: [String] = []

        for (offset, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            if let entry = parseLine(line, draftId: draftId, index: startingIndex + offset) {
                entries.append(entry)
            } else {
                unparsed.append(line)
            }
        }

        return TimetableParseOutcome(entries: entries, unparsedLines: unparsed)
    }
}

// MARK: - 逐行解析
extension PlainTextTimetableParser {

    private func parseLine(_ line: String, draftId: UUID, index: Int) -> ImportDraftEntry? {
        var scanner = LineScanner(work: line)
        var entry = ImportDraftEntry(draftId: draftId, sourceIndex: index, rawPayload: line)
        entry.markParsed()

        applyWeeks(to: &entry, scanner: &scanner)
        applyTime(to: &entry, scanner: &scanner)
        applyTeacherAndLocation(to: &entry, scanner: &scanner)

        if let groups = scanner.extract(#"(?:星期|周|礼拜)\s*([一二三四五六日天]|[1-7])"#) {
            entry.weekday = Self.weekday(from: groups[0])
        }

        let fields = Self.remainingFields(from: scanner.work)
        entry.courseName = fields.name
        if entry.teacher == nil { entry.teacher = fields.teacher }
        if entry.location == nil { entry.location = fields.location }

        let hasInformation = !entry.courseName.isBlank || entry.weekday != nil
        guard hasInformation else { return nil }

        return entry
    }

    private func applyWeeks(to entry: inout ImportDraftEntry, scanner: inout LineScanner) {
        if let groups = scanner.extract(#"(?:除|排除)\s*第?\s*([0-9]+(?:\s*[,、，]\s*[0-9]+)*)\s*周"#) {
            entry.weekRule.excludedWeeks = Self.numbers(in: groups[0])
        } else if let groups = scanner.extract(#"[（(]\s*除\s*([0-9]+(?:\s*[,、，]\s*[0-9]+)*)\s*周\s*[)）]"#) {
            entry.weekRule.excludedWeeks = Self.numbers(in: groups[0])
        }

        if let groups = scanner.extract(#"第?\s*([0-9]+(?:\s*[,、，]\s*[0-9]+)+)\s*周"#) {
            entry.weekRule.pattern = .customWeeks
            entry.weekRule.customWeeks = Self.numbers(in: groups[0])
        } else if let groups = scanner.extract(#"第?\s*([0-9]{1,2})\s*[-–—~～至到]\s*([0-9]{1,2})\s*周"#) {
            entry.weekRule.startWeek = Int(groups[0])
            entry.weekRule.endWeek = Int(groups[1])
        } else if let groups = scanner.extract(#"第?\s*([0-9]{1,2})\s*周"#) {
            let week = Int(groups[0])
            entry.weekRule.startWeek = week
            entry.weekRule.endWeek = week
        }

        if scanner.extract(#"单周|奇数周"#) != nil {
            entry.weekRule.pattern = .oddWeeks
        } else if scanner.extract(#"双周|偶数周"#) != nil {
            entry.weekRule.pattern = .evenWeeks
        }

        if entry.weekRule.pattern == .customWeeks {
            entry.weekRule.startWeek = nil
            entry.weekRule.endWeek = nil
        }
    }

    private func applyTime(to entry: inout ImportDraftEntry, scanner: inout LineScanner) {
        if let groups = scanner.extract(#"([0-9]{1,2})\s*[:：]\s*([0-9]{2})\s*[-–—~～至到]\s*([0-9]{1,2})\s*[:：]\s*([0-9]{2})"#),
           let startHour = Int(groups[0]), let startMinute = Int(groups[1]),
           let endHour = Int(groups[2]), let endMinute = Int(groups[3]) {
            entry.startTime = TimeOfDay(hour: startHour, minute: startMinute)
            entry.endTime = TimeOfDay(hour: endHour, minute: endMinute)
        }

        if let groups = scanner.extract(#"第?\s*([0-9]{1,2})\s*[-–—~～至到]\s*([0-9]{1,2})\s*节"#) {
            entry.startPeriod = Int(groups[0])
            entry.endPeriod = Int(groups[1])
        } else if let groups = scanner.extract(#"第?\s*([0-9]{1,2})\s*节"#) {
            let period = Int(groups[0])
            entry.startPeriod = period
            entry.endPeriod = period
        }
    }

    private func applyTeacherAndLocation(to entry: inout ImportDraftEntry, scanner: inout LineScanner) {
        if let groups = scanner.extract(#"(?:任课教师|授课教师|教师|老师)\s*[:：]\s*([^,，;；、\t\s]+)"#) {
            entry.teacher = groups[0].normalizedOrNil
        }
        if let groups = scanner.extract(#"(?:上课地点|地点|教室|上课教室)\s*[:：]\s*([^,，;；、\t\s]+)"#) {
            entry.location = groups[0].normalizedOrNil
        }
    }
}

// MARK: - 字段识别
extension PlainTextTimetableParser {

    static func weekday(from token: String) -> Weekday? {
        switch token {
        case "一", "1": .monday
        case "二", "2": .tuesday
        case "三", "3": .wednesday
        case "四", "4": .thursday
        case "五", "5": .friday
        case "六", "6": .saturday
        case "日", "天", "7": .sunday
        default: nil
        }
    }

    static func numbers(in text: String) -> [Int] {
        text.split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
            .sorted()
    }

    static func courseName(from remainder: String) -> String {
        remainingFields(from: remainder).name
    }

    /// 把剩余片段按分隔符切开：第一个普通片段视为课程名，
    /// 形如「王老师 / 李教授」的片段视为教师，像教室的片段视为地点。
    static func remainingFields(from remainder: String) -> (name: String, teacher: String?, location: String?) {
        let separators = CharacterSet(charactersIn: ",，;；、\t|")
            .union(.whitespacesAndNewlines)

        let tokens = remainder
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var name = ""
        var teacher: String?
        var location: String?

        for token in tokens {
            if teacher == nil, isTeacher(token) {
                teacher = token
                continue
            }
            if location == nil, isLocation(token) {
                location = token
                continue
            }
            if name.isEmpty {
                name = token
            }
        }

        return (name, teacher, location)
    }

    private static func isTeacher(_ token: String) -> Bool {
        token.hasSuffix("老师") || token.hasSuffix("教授") || token.hasSuffix("教师")
    }

    private static func isLocation(_ token: String) -> Bool {
        let strongMarkers = ["楼", "室", "馆", "场", "校区", "教室", "报告厅"]
        if strongMarkers.contains(where: token.contains) { return true }

        // 「教三201」这类带数字的教学楼写法
        if token.contains("教"), token.contains(where: \.isNumber) { return true }

        let ambiguousMarkers = ["实验", "区", "号"]
        return ambiguousMarkers.contains(where: token.contains) && token.contains(where: \.isNumber)
    }
}

// MARK: - 扫描器
/// 逐行扫描器：按正则提取字段，并把已识别的片段从待处理文本中移除。
private struct LineScanner {

    var work: String

    mutating func extract(_ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let text = work as NSString
        let range = NSRange(location: 0, length: text.length)
        guard let match = regex.firstMatch(in: work, range: range) else { return nil }

        var groups: [String] = []
        for index in 1..<match.numberOfRanges {
            let groupRange = match.range(at: index)
            groups.append(groupRange.location == NSNotFound ? "" : text.substring(with: groupRange))
        }

        work = text.replacingCharacters(in: match.range, with: " ")
        return groups
    }
}
