import Foundation
import WidgetKit

// MARK: - 组件种类

/// 六种组件的 `kind`，`rawValue` 即 `StaticConfiguration` 使用的标识。
enum WidgetKind: String, CaseIterable, Hashable, Sendable {

    case nextClass = "ClassFlowNextClassSmallWidget"
    case today = "ClassFlowTodayWidget"
    case week = "ClassFlowWeekWidget"
    case todo = "ClassFlowTodoWidget"
    case memo = "ClassFlowMemoWidget"
    case dayDone = "ClassFlowDayDoneWidget"
    // 其余 kind 的 rawValue 不可修改：有单测锁定。

    /// 全部组件
    static var all: [WidgetKind] { allCases }
}

/// 共享容器里的快照文件：主 App 写、widget 读。
/// 课表时间的解释规则集中在这里，组件视图只负责排版。
enum WidgetSnapshotStore {

    static let appGroupIdentifier = "group.com.wuhanbingyanonlinetechnologycoltd.ClassFlow"
    static let fileName = "classflow-widget.json"

    /// App Group 容器目录；无相应资格或目录不存在时返回 nil。
    /// 调用方需用 `fallbackDirectory` 兜底。
    static func containerURL(fileManager: FileManager = .default) -> URL? {
        guard let url = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        else { return nil }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return nil }

        return url
    }

    /// 快照文件位置：优先 App Group 容器，没有资格时退回 `fallbackDirectory`（主 App 的数据目录）。
    static func fileURL(fallbackDirectory: URL? = nil, fileManager: FileManager = .default) -> URL? {
        if let container = containerURL(fileManager: fileManager) {
            return container.appendingPathComponent(fileName)
        }
        return fallbackDirectory?.appendingPathComponent(fileName)
    }

    static func load(from url: URL) -> WidgetSnapshot? {
        guard let payload = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(WidgetSnapshot.self, from: payload)
    }

    static func save(_ snapshot: WidgetSnapshot, to url: URL) throws {
        let payload = try encoder.encode(snapshot)
        try payload.write(to: url, options: .atomic)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - 快照生成与读取（主 App 写、组件跨天自愈时重写）

extension WidgetSnapshotStore {

    /// 从主 App 的整份数据算出组件要渲染的一切，只取当前学期。
    /// 没有学期时仍会产出待办与笔记。
    static func makeSnapshot(
        data: AppData,
        from now: Date = Date(),
        timeFormat: TimeFormatPreference? = nil,
        calendar: Calendar = .current
    ) -> WidgetSnapshot {
        let format = timeFormat ?? data.preferences.timeFormat
        let today = CalendarDate(date: now, calendar: calendar)

        var snapshot = WidgetSnapshot(
            generatedAt: now,
            today: today.startOfDay(in: calendar) ?? now
        )
        snapshot.semesterName = data.currentSemester?.name

        let todos = makeTodos(data, format: format, calendar: calendar)
        snapshot.todos = todos.items
        snapshot.openTodoCount = todos.openCount

        snapshot.latestMemo = makeLatestMemo(data)

        guard let semester = data.currentSemester,
              let timetable = data.timetable(for: semester.id)
        else { return snapshot }

        let todayOccurrences = timetable.classes(on: today, calendar: calendar)
        snapshot.todaySlots = todayOccurrences.map { makeSlot($0, format: format, calendar: calendar) }
        snapshot.upcomingSlots = makeUpcoming(
            timetable, from: now, today: today, format: format, calendar: calendar
        )
        snapshot.weeks = makeWeeks(timetable, today: today, format: format, calendar: calendar)
        snapshot.todayStats = makeStats(todayOccurrences, periods: timetable.periods)

        return snapshot
    }

    /// 写入共享容器并请求刷新；写盘失败返回 false。
    @discardableResult
    static func write(
        _ data: AppData,
        to url: URL,
        now: Date = Date(),
        calendar: Calendar = .current,
        reloading kinds: [WidgetKind] = WidgetKind.all
    ) -> Bool {
        let snapshot = makeSnapshot(data: data, from: now, calendar: calendar)
        do {
            try save(snapshot, to: url)
        } catch {
            return false
        }

        reloadWidgets(of: kinds)
        return true
    }

    @discardableResult
    static func write(
        _ data: AppData,
        fallbackDirectory: URL?,
        now: Date = Date(),
        calendar: Calendar = .current,
        reloading kinds: [WidgetKind] = WidgetKind.all
    ) -> Bool {
        guard let url = fileURL(fallbackDirectory: fallbackDirectory) else { return false }
        return write(data, to: url, now: now, calendar: calendar, reloading: kinds)
    }

    /// 组件侧取快照：文件里的 `today` 不是今天就按数据文件重算一次并写回。
    /// 主 App 一整天没被打开时，组件靠这份重算跨过零点，不会一直画昨天的课。
    /// 数据文件读不到时退回旧快照（再不行才空快照），绝不因为重算失败把卡片清空。
    static func snapshotForWidget(
        dataURL: URL,
        snapshotURL: URL,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WidgetSnapshot {
        if let snapshot = load(from: snapshotURL),
           calendar.isDate(snapshot.today, inSameDayAs: now) {
            return snapshot
        }

        let store = FileDataStore(url: dataURL)
        store.widgetSnapshotDirectory = snapshotURL.deletingLastPathComponent()
        // 时间线正是在重排中被调用的，扩展里不要再请求一轮刷新。
        store.widgetReloadKinds = []

        // 数据文件不存在 = 还没同步过来（或用户清空了数据），保留旧快照比清空卡片好。
        guard FileManager.default.fileExists(atPath: dataURL.path),
              let data = try? store.load()
        else {
            return load(from: snapshotURL) ?? WidgetSnapshot(today: calendar.startOfDay(for: now))
        }

        let snapshot = makeSnapshot(data: data, from: now, calendar: calendar)
        try? save(snapshot, to: snapshotURL)
        return snapshot
    }

    /// 是否需要在 `load()` 之后补写快照：文件缺失或比数据文件旧。
    /// 判据失效时一律偏向跳过，避免每次 `load()` 都重算快照。
    static func needsRefresh(
        snapshotURL: URL?,
        dataURL: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        guard let snapshotURL else { return false }

        guard let snapshotDate = modificationDate(of: snapshotURL, fileManager: fileManager) else { return true }
        guard let dataDate = modificationDate(of: dataURL, fileManager: fileManager) else { return true }
        return snapshotDate < dataDate
    }

    /// 快照是不是「隔夜」了：`today` / `todaySlots` / `weeks` 都按天烘焙，跨天必须重算。
    /// 位置为空（没有共享容器也没有兜底目录）时返回 false；文件读不出按过期处理，交给调用方重写。
    static func isStaleDay(
        at url: URL?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let url else { return false }
        guard let snapshot = load(from: url) else { return true }
        return !calendar.isDate(snapshot.today, inSameDayAs: now)
    }

    /// `needsRefresh` 的便利版本：快照位置按「共享容器优先」解析。
    static func needsRefresh(than dataURL: URL, fileManager: FileManager = .default) -> Bool {
        needsRefresh(
            snapshotURL: fileURL(
                fallbackDirectory: dataURL.deletingLastPathComponent(),
                fileManager: fileManager
            ),
            dataURL: dataURL,
            fileManager: fileManager
        )
    }

    /// 磁盘上的快照是否缺失、读不出或为旧格式，需要补写。
    /// 旧格式退化后 `generatedAt == .distantPast`，可当作格式标记。
    static func isLegacy(at url: URL) -> Bool {
        guard let snapshot = load(from: url) else { return true }
        return snapshot.generatedAt == .distantPast
    }

    /// 文件修改时间；取不到返回 nil，调用方按「需要补写」处理。
    private static func modificationDate(of url: URL, fileManager: FileManager) -> Date? {
        (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}

// MARK: - 单节课

extension WidgetSnapshotStore {

    private static func makeSlot(
        _ occurrence: ClassOccurrence,
        format: TimeFormatPreference,
        calendar: Calendar
    ) -> WidgetClassSlot {
        let clock = occurrence.clockTime
        let period = occurrence.classTime.periodRange

        return WidgetClassSlot(
            entryId: occurrence.entry.id,
            courseId: occurrence.course.id,
            courseName: occurrence.course.name,
            day: occurrence.date.startOfDay(in: calendar) ?? Date(),
            weekday: occurrence.weekday.rawValue,
            startText: clock.map { $0.start.displayText(format: format) },
            timeText: clock.map { rangeText($0, format: format) },
            periodText: period.map { WidgetText.periodText(start: $0.start, end: $0.end) },
            location: occurrence.location,
            start: clock.flatMap { occurrence.date.instant(at: $0.start, in: calendar) },
            end: clock.flatMap { occurrence.date.instant(at: $0.end, in: calendar) }
        )
    }

    /// `10:10–11:50` 形式的区间文案，跟随 `format` 的 24 / 12 小时制。
    private static func rangeText(_ range: TimeRange, format: TimeFormatPreference) -> String {
        "\(range.start.displayText(format: format))–\(range.end.displayText(format: format))"
    }

    /// 从今天起 14 天内尚未结束的课，顺序沿用 `Timetable.classes(on:)`；
    /// 超过 `maximumUpcomingSlots` 时优先保留今天的课。
    private static func makeUpcoming(
        _ timetable: Timetable,
        from now: Date,
        today: CalendarDate,
        format: TimeFormatPreference,
        calendar: Calendar
    ) -> [WidgetClassSlot] {
        var slots: [WidgetClassSlot] = []

        for offset in 0..<14 {
            guard let date = today.adding(days: offset, calendar: calendar) else { continue }

            for occurrence in timetable.classes(on: date, calendar: calendar) {
                let slot = makeSlot(occurrence, format: format, calendar: calendar)
                guard !slot.isFinished(at: now) else { continue }
                slots.append(slot)
            }
        }

        guard slots.count > maximumUpcomingSlots else { return slots }

        var todayCount = 0
        if let todayInstant = today.startOfDay(in: calendar) {
            todayCount = slots.prefix { calendar.isDate($0.day, inSameDayAs: todayInstant) }.count
        }

        return Array(slots.prefix(max(maximumUpcomingSlots, todayCount)))
    }
}

// MARK: - 周课表

extension WidgetSnapshotStore {

    /// 周课表纵轴最多留几节，仅为防脏数据把快照撑大。
    private static let maximumGridPeriods = 16
    /// 周课表纵轴最少留几节（本周课少时也要撑出网格）。
    private static let minimumGridPeriods = 4
    /// 「今天起 14 天内的课」最多留几条。
    private static let maximumUpcomingSlots = 40
    /// 未完成待办最多留几条（列表只画三行）。
    private static let maximumOpenTodos = 3

    private struct WeekDraft {
        let offset: Int
        let week: Int
        let days: [CalendarDate]
        let occurrences: [ClassOccurrence]
    }

    private static func makeWeeks(
        _ timetable: Timetable,
        today: CalendarDate,
        format: TimeFormatPreference,
        calendar: Calendar
    ) -> [WidgetWeekGrid] {
        guard let currentWeek = timetable.semester.weekIndex(of: today, calendar: calendar),
              currentWeek >= 1
        else { return [] }

        let weekCount = max(timetable.semester.weekCount(calendar: calendar), 1)
        let periodTimes = timetable.periods

        var drafts: [WeekDraft] = []
        var maxPeriod = 0

        for offset in [-1, 0, 1] {
            let week = currentWeek + offset
            guard week >= 1, week <= weekCount else { continue }

            let days = timetable.dates(inWeek: week, calendar: calendar)
            let occurrences = days.flatMap { timetable.classes(on: $0, calendar: calendar) }
            maxPeriod = max(maxPeriod, occurrences.compactMap { $0.classTime.periodRange?.end }.max() ?? 0)
            drafts.append(WeekDraft(offset: offset, week: week, days: days, occurrences: occurrences))
        }

        guard !drafts.isEmpty else { return [] }

        let rowCount = min(max(maxPeriod, minimumGridPeriods), maximumGridPeriods)
        let periods = (1...rowCount).map { number in
            let slot = periodTimes.first { $0.periodNumber == number }

            return WidgetPeriod(
                number: number,
                timeText: slot?.startTime.displayText(format: format),
                endTimeText: slot?.endTime.displayText(format: format),
                // startMinute：相对午夜的分钟数，组件用它定位八行窗口。
                startMinute: slot?.startTime.minutesFromMidnight
            )
        }

        return drafts.map { draft in
            let days = draft.days.compactMap { $0.startOfDay(in: calendar) }

            return WidgetWeekGrid(
                weekOffset: draft.offset,
                rangeText: WidgetText.weekRangeText(days: days, calendar: calendar),
                subtitle: "第 \(draft.week) 周 · \(timetable.semester.name)",
                days: days,
                periods: periods,
                courses: makeWeekCourses(
                    draft.occurrences,
                    periods: periodTimes,
                    rowCount: rowCount,
                    format: format
                )
            )
        }
    }

    private static func makeWeekCourses(
        _ occurrences: [ClassOccurrence],
        periods: [ClassPeriodTime],
        rowCount: Int,
        format: TimeFormatPreference
    ) -> [WidgetWeekCourse] {
        var placement: [(occurrence: ClassOccurrence, start: Int, end: Int)] = []

        for occurrence in occurrences {
            guard let range = gridRange(for: occurrence, periods: periods, rowCount: rowCount) else { continue }
            placement.append((occurrence, range.start, range.end))
        }

        var courses: [WidgetWeekCourse] = []

        for weekday in 1...7 {
            let column = placement
                .filter { $0.occurrence.weekday.rawValue == weekday }
                .sorted { lhs, rhs in
                    if lhs.start != rhs.start { return lhs.start < rhs.start }
                    return lhs.occurrence.course.name < rhs.occurrence.course.name
                }

            let lanes = assignLanes(column.map { ($0.start, $0.end) })
            let laneCount = max((lanes.max() ?? 0) + 1, 1)

            for (index, item) in column.enumerated() {
                let occurrence = item.occurrence
                let clock = occurrence.clockTime

                courses.append(
                    WidgetWeekCourse(
                        entryId: occurrence.entry.id,
                        courseId: occurrence.course.id,
                        courseName: occurrence.course.name,
                        // color 为 nil 表示课程未设颜色，App 与组件都按灰色画。
                        color: occurrence.course.color,
                        location: occurrence.location,
                        weekday: weekday,
                        startPeriod: item.start,
                        endPeriod: item.end,
                        periodText: WidgetText.periodText(start: item.start, end: item.end),
                        timeText: clock.map { rangeText($0, format: format) },
                        lane: lanes[index],
                        laneCount: laneCount
                    )
                )
            }
        }

        return courses
    }

    /// 把一条安排落到网格的节次区间；整个区间都在网格之外时返回 nil。
    /// 自定时间的安排取开始时刻所在的那一节，卡片时间文案仍写真实钟点。
    private static func gridRange(
        for occurrence: ClassOccurrence,
        periods: [ClassPeriodTime],
        rowCount: Int
    ) -> (start: Int, end: Int)? {
        if let range = occurrence.classTime.periodRange {
            guard range.start <= rowCount else { return nil }
            let start = max(range.start, 1)
            return (start, min(max(range.end, start), rowCount))
        }

        guard let clock = occurrence.clockTime else { return nil }

        let row = periods
            .filter { $0.periodNumber >= 1 && $0.periodNumber <= rowCount }
            .sorted { $0.periodNumber < $1.periodNumber }
            .last { $0.startTime <= clock.start }?
            .periodNumber

        guard let row else { return nil }
        return (row, row)
    }

    /// 同一列里节次区间重叠的安排分栏：贪心地把每条放进「已经结束的最早一栏」。
    private static func assignLanes(_ ranges: [(start: Int, end: Int)]) -> [Int] {
        var laneEnds: [Int] = []
        var lanes: [Int] = []

        for range in ranges {
            if let lane = laneEnds.firstIndex(where: { $0 < range.start }) {
                laneEnds[lane] = range.end
                lanes.append(lane)
            } else {
                laneEnds.append(range.end)
                lanes.append(laneEnds.count - 1)
            }
        }

        return lanes
    }
}

// MARK: - 统计

extension WidgetSnapshotStore {

    /// `今日 4 节课 · 上课 3 小时` 的两个数字。
    /// `minutes` 只累加上课时长，不含课间；自定时间按自己的起止钟点算。
    private static func makeStats(
        _ occurrences: [ClassOccurrence],
        periods: [ClassPeriodTime]
    ) -> WidgetDayStats {
        var periodCount = 0
        var minutes = 0

        let durations = Dictionary(
            periods.map { ($0.periodNumber, $0.durationMinutes) },
            uniquingKeysWith: { first, _ in first }
        )

        for occurrence in occurrences {
            if let range = occurrence.classTime.periodRange {
                periodCount += max(range.end - range.start + 1, 1)
                minutes += (range.start...range.end).reduce(0) { $0 + max(durations[$1] ?? 0, 0) }
            } else {
                periodCount += 1
                minutes += occurrence.clockTime?.durationMinutes ?? 0
            }
        }

        return WidgetDayStats(periodCount: periodCount, minutes: minutes)
    }
}

// MARK: - 待办与笔记

extension WidgetSnapshotStore {

    /// 待办：组件会画的那几条（未完成按到期时间在前 + 最近完成的 2 条）与未完成总数。
    private static func makeTodos(
        _ data: AppData,
        format: TimeFormatPreference,
        calendar: Calendar
    ) -> (items: [WidgetTodoItem], openCount: Int) {
        let coursesById = Dictionary(data.courses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        func item(_ task: CourseTask) -> WidgetTodoItem {
            WidgetTodoItem(
                id: task.id,
                title: task.title,
                courseName: task.courseId.flatMap { coursesById[$0]?.name },
                dueDay: task.dueDate?.startOfDay(in: calendar),
                dueTimeText: task.dueTime?.displayText(format: format),
                isCompleted: !task.status.isOpen
            )
        }

        let openTasks = data.tasks.filter { $0.status.isOpen }

        let open = openTasks
            .sorted { lhs, rhs in
                let left = lhs.dueInstant(calendar: calendar) ?? .distantFuture
                let right = rhs.dueInstant(calendar: calendar) ?? .distantFuture
                if left != right { return left < right }
                return lhs.createdAt < rhs.createdAt
            }
            .prefix(maximumOpenTodos)
            .map(item)

        let finished = data.tasks
            .filter { !$0.status.isOpen }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(2)
            .map(item)

        return (open + finished, openTasks.count)
    }

    private static func makeLatestMemo(_ data: AppData) -> WidgetMemoItem? {
        let coursesById = Dictionary(data.courses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        return data.memos
            .filter { !$0.content.isBlank }
            .max { $0.updatedAt < $1.updatedAt }
            .map { memo in
                WidgetMemoItem(
                    id: memo.id,
                    courseId: memo.courseId,
                    courseName: coursesById[memo.courseId]?.name ?? "未知课程",
                    title: memo.displayTitle,
                    updatedAt: memo.updatedAt
                )
            }
    }
}

// MARK: - 周切换与刷新

extension WidgetSnapshotStore {

    /// 周课表卡片的周切换偏移，取值范围 -1 / 0 / 1，存在 App Group 共享偏好里供主 App 与 widget 共用。
    static let weekOffsetKey = "widget.weekOffset"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    static func weekOffset() -> Int {
        min(max(sharedDefaults?.integer(forKey: weekOffsetKey) ?? 0, -1), 1)
    }

    static func setWeekOffset(_ offset: Int) {
        sharedDefaults?.set(min(max(offset, -1), 1), forKey: weekOffsetKey)
    }

    /// 数据变了就请系统重排时间线；受影响的组件尽量定向刷新。
    /// 传 `WidgetKind.all` 时走 `reloadAllTimelines()`；传空数组表示一个都不刷。
    static func reloadWidgets(of kinds: [WidgetKind] = WidgetKind.all) {
        let center = WidgetCenter.shared

        if Set(kinds) == Set(WidgetKind.allCases) {
            center.reloadAllTimelines()
            return
        }

        for kind in Set(kinds) {
            center.reloadTimelines(ofKind: kind.rawValue)
        }
    }
}

// MARK: - 从组件跳回 App 的路由

/// `classflow://` 深链的构造与解析。
/// 组件通过 `widgetURL` / `Link` 或 App Intent 打开，主 App 的 `AppRouter` 负责解析。
enum WidgetDeepLink {

    static let scheme = "classflow"
    /// 主 App 启动 / 回前台时来取的这个键（App Intent 触发跳转时用）。
    static let pendingKey = "widget.pendingDeepLink"

    enum Destination: Hashable, Sendable {
        case scheduleToday
        case scheduleWeek(offset: Int)
        case course(UUID)
        case task(UUID)
        case memo(UUID)
        case newMemo(courseId: UUID?)
        case periodTimes
        case tasks
        case notes
    }

    static func url(_ destination: Destination) -> URL? {
        switch destination {
        case .scheduleToday:
            return URL(string: "\(scheme)://schedule/today")

        case let .scheduleWeek(offset):
            return URL(string: "\(scheme)://schedule/week?offset=\(offset)")

        case let .course(id):
            return URL(string: "\(scheme)://course/\(id.uuidString)")

        case let .task(id):
            return URL(string: "\(scheme)://task/\(id.uuidString)")

        case let .memo(id):
            return URL(string: "\(scheme)://memo/\(id.uuidString)")

        case let .newMemo(courseId):
            guard let courseId else { return URL(string: "\(scheme)://memo/new") }
            return URL(string: "\(scheme)://memo/new?course=\(courseId.uuidString)")

        case .periodTimes:
            return URL(string: "\(scheme)://settings/period-times")

        case .tasks:
            return URL(string: "\(scheme)://tasks")

        case .notes:
            return URL(string: "\(scheme)://notes")
        }
    }

    static func parse(_ url: URL) -> Destination? {
        guard url.scheme?.lowercased() == scheme else { return nil }

        let segments = ([url.host] + url.pathComponents.filter { $0 != "/" })
            .compactMap { $0 }
            .map { $0.lowercased() }

        guard let head = segments.first else { return nil }

        switch head {
        case "schedule":
            let tail = segments.dropFirst().first
            if tail == "week" {
                let offset = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first { $0.name == "offset" }?
                    .value
                    .flatMap(Int.init) ?? 0
                return .scheduleWeek(offset: min(max(offset, -1), 1))
            }
            return .scheduleToday

        case "course":
            guard let id = segments.dropFirst().first.flatMap(UUID.init(uuidString:)) else { return nil }
            return .course(id)

        case "task":
            guard let id = segments.dropFirst().first.flatMap(UUID.init(uuidString:)) else { return nil }
            return .task(id)

        case "memo":
            guard let tail = segments.dropFirst().first else { return nil }
            if tail == "new" {
                let courseId = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first { $0.name == "course" }?
                    .value
                    .flatMap(UUID.init(uuidString:))
                return .newMemo(courseId: courseId)
            }
            guard let id = UUID(uuidString: tail) else { return nil }
            return .memo(id)

        case "settings":
            return segments.dropFirst().first == "period-times" ? .periodTimes : nil

        case "tasks":
            return .tasks

        case "notes":
            return .notes

        default:
            return nil
        }
    }

    // MARK: 待处理深链（App Intent 用）

    /// 把目标深链写入共享偏好，供 App 回到前台时取走。
    static func storePending(_ destination: Destination) {
        guard let url = url(destination) else { return }
        sharedDefaults?.set(url.absoluteString, forKey: pendingKey)
    }

    static func takePending() -> Destination? {
        guard let text = sharedDefaults?.string(forKey: pendingKey),
              let url = URL(string: text)
        else { return nil }

        sharedDefaults?.removeObject(forKey: pendingKey)
        return parse(url)
    }

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: WidgetSnapshotStore.appGroupIdentifier)
    }
}
