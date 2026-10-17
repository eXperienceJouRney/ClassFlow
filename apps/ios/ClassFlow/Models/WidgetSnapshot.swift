import Foundation

// MARK: - 卡片上的一节课

/// 桌面小组件渲染的一节课；主 App 写、widget 读。
/// 节次编号不等于实际时间：`timeText` / `start` / `end` 查不到作息时为 nil，组件不得推测。
struct WidgetClassSlot: Codable, Hashable, Sendable {

    /// 对应的 `ScheduleEntry.id`，用于点击后跳回主 App 的这节课。
    let entryId: UUID
    let courseId: UUID
    let courseName: String
    /// 上课那一日的零点；用来判断「这一节是不是今天的」。
    let day: Date
    /// ISO 星期：1 = 周一 … 7 = 周日
    let weekday: Int
    /// `08:00`（这一节开始的那一刻）；时间未配置时为 nil。
    let startText: String?
    /// `10:10–11:50`；时间未配置时为 nil。
    let timeText: String?
    /// `第 3–4 节`；自定时间的安排没有课节，为 nil。
    let periodText: String?
    /// `教室 302` / `教三 201`（沿用课程或安排里填的原文，不额外加前缀）。
    let location: String?
    /// 实际上课时刻；**时间未配置时为 nil**（绝不猜测开始时间）。
    let start: Date?
    let end: Date?
}

extension WidgetClassSlot {

    var isTimeConfigured: Bool { start != nil && end != nil }

    /// 这节课是按课节排的，但学期作息里查不到对应课节 → 「时间待设置」。
    var hasUnresolvedPeriodTime: Bool { periodText != nil && !isTimeConfigured }

    func isOngoing(at now: Date) -> Bool {
        guard let start, let end else { return false }
        return start <= now && now < end
    }

    func isFinished(at now: Date) -> Bool {
        guard let end else { return false }
        return end <= now
    }

    /// 倒计时文案：`29 分钟` / `正在上课` / `时间待设置`。
    func countdownText(at now: Date) -> String {
        if isOngoing(at: now) { return "正在上课" }
        guard let start else { return "时间待设置" }

        let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 0 { return "马上开始" }
        if minutes < 60 { return "\(minutes) 分钟" }

        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) 小时" : "\(hours) 小时 \(rest) 分钟"
    }

    /// 倒计时文案：`29 分钟后` / `正在上课` / `时间待设置`。
    func statusText(at now: Date) -> String {
        if isOngoing(at: now) { return "正在上课" }
        guard let start else { return "时间待设置" }

        let seconds = start.timeIntervalSince(now)
        if seconds <= 0 { return "刚刚开始" }

        let minutes = Int(seconds / 60)
        if minutes < 1 { return "马上开始" }
        if minutes < 60 { return "\(minutes) 分钟后" }

        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) 小时后" : "\(hours) 小时 \(rest) 分钟后"
    }

    /// 状态文案：`已结束` / `进行中` / `29 分钟后开始`。
    func progressText(at now: Date) -> String {
        guard isTimeConfigured else { return "时间待设置" }
        if isOngoing(at: now) { return "进行中" }
        if isFinished(at: now) { return "已结束" }
        guard let start else { return "时间待设置" }

        let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 1 { return "即将开始" }
        if minutes < 60 { return "\(minutes) 分钟后开始" }

        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) 小时后开始" : "\(hours) 小时 \(rest) 分钟后开始"
    }

    /// `10:10–11:50 · 第 3–4 节`；缺哪一段就只留另一段。
    var detailText: String {
        [timeText, periodText].compactMap { $0 }.joined(separator: " · ")
    }

    /// `教室 302 · 第 3–4 节`；两段都缺时为 nil。
    var locationPeriodText: String? {
        let parts = [location, periodText].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - 待办 / 笔记 / 冲突

/// 小组件里的一条待办。
struct WidgetTodoItem: Codable, Hashable, Sendable {

    let id: UUID
    let title: String
    /// 关联课程名；没有关联课程时为 nil。
    let courseName: String?
    /// 截止日（当天零点）；没有截止日期时为 nil。
    let dueDay: Date?
    /// `18:00`（按用户时间格式偏好格式化）；没设时刻为 nil。
    let dueTimeText: String?
    let isCompleted: Bool
}

extension WidgetTodoItem {

    /// `高等数学 · 今天, 18:00`；没有截止日期时只写「无截止日期」。
    func auxiliaryText(now: Date = Date(), calendar: Calendar = .current) -> String {
        var parts: [String] = []
        if let courseName { parts.append(courseName) }
        parts.append(WidgetText.dueDayText(for: dueDay, now: now, calendar: calendar, timeText: dueTimeText))
        return parts.joined(separator: " · ")
    }
}

/// 最近编辑的一条课程笔记。
struct WidgetMemoItem: Codable, Hashable, Sendable {

    let id: UUID
    let courseId: UUID
    let courseName: String
    /// 笔记标题（显式标题优先，否则取正文第一行）。
    let title: String
    let updatedAt: Date
}

// MARK: - 周课表

/// 周课表纵轴上的一节。
struct WidgetPeriod: Codable, Hashable, Sendable {

    let number: Int
    /// 这一节的开始时刻 `08:00`；学期作息里没有这一节时为 nil。
    let timeText: String?
    /// 这一节的结束（下课）时刻 `08:45`；学期作息里没有这一节时为 nil。
    let endTimeText: String?
    /// 这一节开始时刻的「当天第几分钟」（`08:00` → 480），机器可读；作息里没有这一节时为 nil。
    let startMinute: Int?

    init(number: Int, timeText: String?, endTimeText: String? = nil, startMinute: Int? = nil) {
        self.number = number
        self.timeText = timeText
        self.endTimeText = endTimeText
        self.startMinute = startMinute
    }
}

/// 周课表里的课程卡片：位置用节次区间表达，同列重叠的安排按 `lane` / `laneCount` 分栏。
struct WidgetWeekCourse: Codable, Hashable, Sendable {

    let entryId: UUID
    let courseId: UUID
    let courseName: String
    /// 课程颜色；未设置时为 nil，按灰色绘制。
    let color: CourseColor?
    let location: String?
    /// ISO 星期：1 = 周一 … 7 = 周日
    let weekday: Int
    /// 起始 / 结束节次（绝对课节编号，不是行号）
    let startPeriod: Int
    let endPeriod: Int
    /// `第 3–4 节`
    let periodText: String
    /// `10:10–11:50`；时间未配置时为 nil
    let timeText: String?
    /// 同列重叠时的分栏下标与总栏数（无重叠恒为 0 / 1）
    let lane: Int
    let laneCount: Int

    /// 占几行
    var rowSpan: Int { max(endPeriod - startPeriod + 1, 1) }
}

/// 一周的课表网格。
struct WidgetWeekGrid: Codable, Hashable, Sendable {

    /// 相对当前周的偏移：0 = 本周，-1 = 上周，1 = 下周。
    let weekOffset: Int
    /// `1 月 12–18 日`
    let rangeText: String
    /// `第 1 周 · 2026 年春季`
    let subtitle: String
    /// 周一到周日七天的零点
    let days: [Date]
    /// 纵轴：第 1 节起逐节向下的整份纵轴，快照里必须完整保留。
    let periods: [WidgetPeriod]
    let courses: [WidgetWeekCourse]
}

// MARK: - 今日统计

/// 今日统计：`今日 4 节课 · 上课 3 小时`。
struct WidgetDayStats: Codable, Hashable, Sendable {

    /// 今天的**课节数**（跨 2 节的安排算 2 节）
    let periodCount: Int
    /// 今天的上课总时长（分钟）
    let minutes: Int

    static let zero = WidgetDayStats(periodCount: 0, minutes: 0)

    /// `3 小时` / `45 分钟`
    var durationText: String { WidgetText.durationText(minutes: minutes) }
}

// MARK: - 快照

/// 桌面小组件读到的全部共享数据（App Group 里的 `classflow-widget.json`），主 App 写、widget 读。
/// 与当前时间有关的相对文案不在快照里，由 widget 渲染时按 entry 的日期现算。
struct WidgetSnapshot: Codable, Hashable, Sendable {

    var generatedAt: Date
    /// 当前学期名，例如 `2026 秋季学期`
    var semesterName: String?
    /// 今天（当天零点）
    var today: Date
    /// 今天的全部课程（含已结束），按课表顺序排列
    var todaySlots: [WidgetClassSlot]
    /// 今天起 14 天内**还没有结束**的课（含今天剩余的），按课表顺序排列
    var upcomingSlots: [WidgetClassSlot]
    /// 周课表：上周 / 本周 / 下周（本周在中间）
    var weeks: [WidgetWeekGrid]
    var todayStats: WidgetDayStats
    /// 未完成待办（按到期时间排序）+ 最近完成的待办（排在最后），条数已按 `maximumOpenTodos` 截断。
    var todos: [WidgetTodoItem]
    /// 未完成待办的总数
    var openTodoCount: Int
    /// 最近编辑的一条课程笔记
    var latestMemo: WidgetMemoItem?

    init(
        generatedAt: Date = .distantPast,
        semesterName: String? = nil,
        today: Date = Date(timeIntervalSince1970: 0),
        todaySlots: [WidgetClassSlot] = [],
        upcomingSlots: [WidgetClassSlot] = [],
        weeks: [WidgetWeekGrid] = [],
        todayStats: WidgetDayStats = .zero,
        todos: [WidgetTodoItem] = [],
        openTodoCount: Int = 0,
        latestMemo: WidgetMemoItem? = nil
    ) {
        self.generatedAt = generatedAt
        self.semesterName = semesterName
        self.today = today
        self.todaySlots = todaySlots
        self.upcomingSlots = upcomingSlots
        self.weeks = weeks
        self.todayStats = todayStats
        self.todos = todos
        self.openTodoCount = openTodoCount
        self.latestMemo = latestMemo
    }

    /// 空快照：没有学期 / 没有课程 / 快照文件读不到时使用。
    /// `today` 必须取今天零点，该字段会直接绘制在卡片上。
    static var empty: WidgetSnapshot {
        WidgetSnapshot(today: Calendar.current.startOfDay(for: Date()))
    }
}

extension WidgetSnapshot {

    enum CodingKeys: String, CodingKey {
        case generatedAt
        case semesterName
        case today
        case todaySlots
        case upcomingSlots
        case weeks
        case todayStats
        case todos
        case openTodoCount
        case latestMemo
    }

    /// 宽容解码：任何字段缺失或类型不符都退回默认值。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = WidgetSnapshot()

        generatedAt = try container.decodeIfPresent(Date.self, forKey: .generatedAt) ?? fallback.generatedAt
        semesterName = try container.decodeIfPresent(String.self, forKey: .semesterName)
        today = try container.decodeIfPresent(Date.self, forKey: .today)
            ?? Calendar.current.startOfDay(for: Date())
        todaySlots = try container.decodeIfPresent([WidgetClassSlot].self, forKey: .todaySlots) ?? []
        upcomingSlots = try container.decodeIfPresent([WidgetClassSlot].self, forKey: .upcomingSlots) ?? []
        weeks = try container.decodeIfPresent([WidgetWeekGrid].self, forKey: .weeks) ?? []
        todayStats = try container.decodeIfPresent(WidgetDayStats.self, forKey: .todayStats) ?? .zero
        todos = try container.decodeIfPresent([WidgetTodoItem].self, forKey: .todos) ?? []
        openTodoCount = try container.decodeIfPresent(Int.self, forKey: .openTodoCount)
            ?? todos.filter { !$0.isCompleted }.count
        latestMemo = try container.decodeIfPresent(WidgetMemoItem.self, forKey: .latestMemo)
    }
}

extension WidgetSnapshot {

    /// 小组件关心的「那一节课」：正在上的课优先，其次是下一节。
    /// 时间未配置的安排无法比较先后，按「下一节」兜底。
    func activeSlot(at now: Date = Date()) -> WidgetClassSlot? {
        if let ongoing = upcomingSlots.first(where: { $0.isOngoing(at: now) }) { return ongoing }

        return upcomingSlots.first { slot in
            guard let start = slot.start else { return true }
            return start > now
        }
    }

    /// 今天还没有结束的课。
    func todayRemaining(at now: Date = Date(), calendar: Calendar = .current) -> [WidgetClassSlot] {
        upcomingSlots.filter {
            calendar.isDate($0.day, inSameDayAs: today) && !$0.isFinished(at: now)
        }
    }

    /// 指定某一天的课。
    func slots(on day: Date, calendar: Calendar = .current) -> [WidgetClassSlot] {
        upcomingSlots.filter { calendar.isDate($0.day, inSameDayAs: day) }
    }

    /// 某个偏移量的周网格。
    /// 该偏移量的网格不存在时退回最接近的一周。
    func week(offset: Int) -> WidgetWeekGrid? {
        if let exact = weeks.first(where: { $0.weekOffset == offset }) { return exact }
        return weeks.min { abs($0.weekOffset - offset) < abs($1.weekOffset - offset) }
    }

    /// 该偏移量是否真的做出了网格（周切换按钮用它判断越界）。
    func hasWeek(offset: Int) -> Bool {
        weeks.contains { $0.weekOffset == offset }
    }

    var currentWeek: WidgetWeekGrid? { week(offset: 0) }
}

// MARK: - 占位数据

extension WidgetSnapshot {

    /// 预览 / 占位数据，倒计时按真实时钟现算。
    static var placeholder: WidgetSnapshot {
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        let mathStart = now.addingTimeInterval(29 * 60)
        let mathEnd = mathStart.addingTimeInterval(100 * 60)
        let englishStart = calendar.date(byAdding: .minute, value: 8 * 60, to: today) ?? today
        let englishEnd = englishStart.addingTimeInterval(100 * 60)

        let english = WidgetClassSlot(
            entryId: UUID(),
            courseId: UUID(),
            courseName: "英语",
            day: today,
            weekday: 1,
            startText: "08:00",
            timeText: "08:00–09:40",
            periodText: "第 1–2 节",
            location: "教室 B201",
            start: englishStart,
            end: englishEnd
        )

        let math = WidgetClassSlot(
            entryId: UUID(),
            courseId: UUID(),
            courseName: "高等数学",
            day: today,
            weekday: 1,
            startText: "10:10",
            timeText: "10:10–11:50",
            periodText: "第 3–4 节",
            location: "教室 302",
            start: mathStart,
            end: mathEnd
        )

        let dataStructures = WidgetClassSlot(
            entryId: UUID(),
            courseId: UUID(),
            courseName: "数据结构",
            day: calendar.date(byAdding: .day, value: 1, to: today) ?? today,
            weekday: 2,
            startText: "14:00",
            timeText: "14:00–15:40",
            periodText: "第 5–6 节",
            location: "教室 A201",
            start: mathStart.addingTimeInterval(24 * 60 * 60),
            end: mathEnd.addingTimeInterval(24 * 60 * 60)
        )

        return WidgetSnapshot(
            generatedAt: now,
            semesterName: "2026 年春季",
            today: today,
            todaySlots: [english, math],
            upcomingSlots: [math, dataStructures],
            weeks: [placeholderWeek(offset: 0, now: now, calendar: calendar)],
            todayStats: WidgetDayStats(periodCount: 4, minutes: 180),
            todos: [
                WidgetTodoItem(
                    id: UUID(),
                    title: "完成习题集",
                    courseName: "高等数学",
                    dueDay: today,
                    dueTimeText: "18:00",
                    isCompleted: false
                ),
                WidgetTodoItem(
                    id: UUID(),
                    title: "阅读第四章",
                    courseName: "英语",
                    dueDay: calendar.date(byAdding: .day, value: 1, to: today),
                    dueTimeText: nil,
                    isCompleted: false
                ),
            ],
            openTodoCount: 2,
            latestMemo: WidgetMemoItem(
                id: UUID(),
                courseId: UUID(),
                courseName: "数据结构",
                title: "树与遍历",
                updatedAt: now.addingTimeInterval(-2 * 60 * 60)
            )
        )
    }

    private static func placeholderWeek(offset: Int, now: Date, calendar: Calendar) -> WidgetWeekGrid {
        let monday = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }

        let courses = [
            WidgetWeekCourse(
                entryId: UUID(), courseId: UUID(), courseName: "英语", color: .green, location: "B201",
                weekday: 1, startPeriod: 1, endPeriod: 2,
                periodText: "第 1–2 节", timeText: "08:00–09:40", lane: 0, laneCount: 1
            ),
            WidgetWeekCourse(
                entryId: UUID(), courseId: UUID(), courseName: "高等数学", color: .blue, location: "302",
                weekday: 1, startPeriod: 3, endPeriod: 4,
                periodText: "第 3–4 节", timeText: "10:10–11:50", lane: 0, laneCount: 1
            ),
            WidgetWeekCourse(
                entryId: UUID(), courseId: UUID(), courseName: "高等数学", color: .blue, location: "302",
                weekday: 3, startPeriod: 3, endPeriod: 4,
                periodText: "第 3–4 节", timeText: "10:10–11:50", lane: 0, laneCount: 1
            ),
            WidgetWeekCourse(
                entryId: UUID(), courseId: UUID(), courseName: "英语", color: .green, location: "B201",
                weekday: 5, startPeriod: 1, endPeriod: 2,
                periodText: "第 1–2 节", timeText: "08:00–09:40", lane: 0, laneCount: 1
            ),
        ]

        return WidgetWeekGrid(
            weekOffset: offset,
            rangeText: WidgetText.weekRangeText(days: days, calendar: calendar),
            subtitle: "第 1 周 · 2026 年春季",
            days: days,
            // 占位周故意不给 `startMinute`，以保持固定版面。
            periods: (1...6).map { number in
                let slot = Self.placeholderPeriodTimes[number - 1]
                return WidgetPeriod(number: number, timeText: slot.start, endTimeText: slot.end)
            },
            courses: courses
        )
    }

    /// 占位周纵轴的时刻（`ClassPeriodTime.defaultSlots` 的前 6 节）：`上课 / 下课`。
    private static let placeholderPeriodTimes: [(start: String, end: String)] = [
        ("08:00", "08:45"),
        ("08:55", "09:40"),
        ("10:00", "10:45"),
        ("10:55", "11:40"),
        ("14:00", "14:45"),
        ("14:55", "15:40"),
    ]
}

// MARK: - 共享文案

/// 组件上的日期 / 时长文案。
/// 只依赖 Foundation：主 App 用它把文案烘焙进快照，widget 用它现算相对时间文案。
enum WidgetText {

    /// ISO 星期 → `周一`
    static func weekdayShortName(_ isoWeekday: Int) -> String {
        switch isoWeekday {
        case 1: "周一"
        case 2: "周二"
        case 3: "周三"
        case 4: "周四"
        case 5: "周五"
        case 6: "周六"
        case 7: "周日"
        default: "—"
        }
    }

    /// 某个日期落在 ISO 星期几（1 = 周一 … 7 = 周日）。
    static func isoWeekday(of date: Date, calendar: Calendar = .current) -> Int {
        let foundationWeekday = calendar.component(.weekday, from: date)
        return foundationWeekday == 1 ? 7 : foundationWeekday - 1
    }

    /// `1 月 12 日`
    static func monthDayText(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 1) 月 \(parts.day ?? 1) 日"
    }

    /// `1 月 12 日 周一`
    static func monthDayWeekdayText(_ date: Date, calendar: Calendar = .current) -> String {
        "\(monthDayText(date, calendar: calendar)) \(weekdayShortName(isoWeekday(of: date, calendar: calendar)))"
    }

    /// `1 月 12–18 日`；跨月时写成 `1 月 28 日–2 月 3 日`。
    static func weekRangeText(days: [Date], calendar: Calendar = .current) -> String {
        guard let first = days.first, let last = days.last else { return "" }

        let start = calendar.dateComponents([.month, .day], from: first)
        let end = calendar.dateComponents([.month, .day], from: last)

        guard let startMonth = start.month, let startDay = start.day,
              let endMonth = end.month, let endDay = end.day
        else { return "" }

        guard startMonth == endMonth else {
            return "\(startMonth) 月 \(startDay) 日–\(endMonth) 月 \(endDay) 日"
        }
        return "\(startMonth) 月 \(startDay)–\(endDay) 日"
    }

    /// `第 3–4 节` / `第 5 节`
    static func periodText(start: Int, end: Int) -> String {
        start == end ? "第 \(start) 节" : "第 \(start)–\(end) 节"
    }

    /// `今天, 18:00` / `明天` / `周一, 9月22日`
    static func dueDayText(
        for dueDay: Date?,
        now: Date = Date(),
        calendar: Calendar = .current,
        timeText: String?
    ) -> String {
        guard let dueDay else { return "无截止日期" }

        let offset = dayOffset(from: now, to: dueDay, calendar: calendar)
        let dayText: String
        switch offset {
        case 0: dayText = "今天"
        case 1: dayText = "明天"
        case -1: dayText = "昨天"
        default:
            dayText = offset < -1
                ? monthDayText(dueDay, calendar: calendar)
                : "\(weekdayShortName(isoWeekday(of: dueDay, calendar: calendar))), \(shortMonthDayText(dueDay, calendar: calendar))"
        }

        guard let timeText, offset >= 0 else { return dayText }
        return "\(dayText), \(timeText)"
    }

    /// `9月22日`
    static func shortMonthDayText(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 1)月\(parts.day ?? 1)日"
    }

    /// `3 小时` / `45 分钟` / `2 小时 30 分钟`
    static func durationText(minutes: Int) -> String {
        guard minutes > 0 else { return "0 分钟" }
        guard minutes >= 60 else { return "\(minutes) 分钟" }

        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) 小时" : "\(hours) 小时 \(rest) 分钟"
    }

    /// `2 小时前编辑`
    static func relativeEditText(from date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "刚刚编辑" }

        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) 分钟前编辑" }

        let hours = minutes / 60
        if hours < 24 { return "\(hours) 小时前编辑" }

        let offset = dayOffset(from: now, to: date, calendar: calendar)
        if offset == -1 { return "昨天编辑" }
        if offset > -7 { return "\(-offset) 天前编辑" }

        return "\(monthDayText(date, calendar: calendar))编辑"
    }

    /// 两个日期相差几天（`to` 晚于 `from` 为正）。
    static func dayOffset(from: Date, to date: Date, calendar: Calendar = .current) -> Int {
        let fromDay = calendar.startOfDay(for: from)
        let toDay = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: fromDay, to: toDay).day ?? 0
    }
}
