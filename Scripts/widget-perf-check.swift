// 小组件交互性能基准：把「点一下组件」要走的链路拆开逐段计时。
//
// 运行（macOS，不需要模拟器、不需要 WidgetKit 宿主）：
//
//   cd /Users/ray/classflow
//   xcrun swiftc -O -parse-as-library -o /tmp/classflow-widget-perf \
//     apps/ios/ClassFlow/Models/*.swift \
//     apps/ios/ClassFlow/Services/{AppData,AppDataStore,Inputs,WidgetSnapshotStore}.swift \
//     apps/ios/ClassFlow/Views/Widget/WidgetTimeline.swift \
//     Scripts/widget-perf-check.swift
//   /tmp/classflow-widget-perf
import Foundation

// MARK: - 计时

/// 跑 `iterations` 次取中位数：单次测量会被进程调度噪声淹没，中位数更能代表体感。
func measure(_ label: String, iterations: Int = 7, _ body: () throws -> Void) rethrows -> Double {
    var samples: [Double] = []

    for _ in 0..<iterations {
        let start = DispatchTime.now().uptimeNanoseconds
        try body()
        let end = DispatchTime.now().uptimeNanoseconds
        samples.append(Double(end - start) / 1_000_000)
    }

    samples.sort()
    let median = samples[samples.count / 2]
    print(String(format: "   %-34@ %8.2f ms   (min %.2f / max %.2f)",
                 label as NSString, median, samples.first ?? 0, samples.last ?? 0))
    return median
}

// MARK: - 合成数据

/// 造一份「像真的」的数据：一个学期 + N 门课 + 每门课几节课 + 待办 + 笔记。
func makeData(
    semesterWeeks: Int,
    courseCount: Int,
    entriesPerCourse: Int,
    taskCount: Int,
    memoCount: Int
) -> AppData {
    let calendar = Calendar.current
    let now = Date()
    // 学期要**跨过今天往后延伸**，否则「今天起 14 天内的课」几乎为空，
    // 组件时间线就只剩当前时刻一条，测不出真实规模。
    let start = calendar.date(byAdding: .day, value: -7 * (semesterWeeks / 2), to: now) ?? now
    let end = calendar.date(byAdding: .day, value: 7 * (semesterWeeks / 2), to: now) ?? now

    let semester = Semester(
        name: "2026 年春季学期",
        startDate: CalendarDate(date: start, calendar: calendar),
        endDate: CalendarDate(date: end, calendar: calendar)
    )

    let palette = CourseColor.allCases
    var courses: [Course] = []
    var entries: [ScheduleEntry] = []

    for index in 0..<courseCount {
        let course = Course(
            semesterId: semester.id,
            name: "课程 \(index + 1) · 专业课名称偏长的那种",
            teacher: "老师 \(index % 7)",
            location: "教学楼 \(index % 5 + 1)0\(index % 4 + 1)",
            color: palette[index % palette.count]
        )
        courses.append(course)

        for slot in 0..<entriesPerCourse {
            entries.append(
                ScheduleEntry(
                    courseId: course.id,
                    weekday: Weekday.allCases[(index + slot) % 7],
                    time: .period(start: slot * 2 + 1, end: slot * 2 + 2),
                    startWeek: 1,
                    endWeek: semesterWeeks
                )
            )
        }
    }

    let tasks = (0..<taskCount).map { index in
        CourseTask(
            title: "待办事项 \(index + 1)",
            courseId: courses[index % courses.count].id,
            dueDate: CalendarDate(date: calendar.date(byAdding: .day, value: index % 14, to: now) ?? now, calendar: calendar),
            dueTime: TimeOfDay(hour: 18, minute: 0),
            status: index % 5 == 0 ? .completed : .todo
        )
    }

    let memos = (0..<memoCount).map { index in
        Memo(
            courseId: courses[index % courses.count].id,
            title: "笔记 \(index + 1)",
            content: String(repeating: "课堂要点记录内容。", count: 12),
            createdAt: now.addingTimeInterval(Double(-index) * 3600),
            updatedAt: now.addingTimeInterval(Double(-index) * 3600)
        )
    }

    return AppData(
        currentSemesterId: semester.id,
        semesters: [semester],
        courses: courses,
        scheduleEntries: entries,
        periodTimes: ClassPeriodTime.defaults(for: semester.id),
        tasks: tasks,
        memos: memos
    )
}

// MARK: - 单档数据的完整链路

/// 改动前 `ClassFlowWidgetEntryProvider.entryDates` 的排法（照抄旧实现，只用于对照）。
///
/// 差别只有一处但影响很大：旧实现把**未来 14 天**里每一节课的开始 / 结束时刻都塞进时间线，
/// 再按 120 条截断 —— 于是时间线经常横跨好几天，而这些 entry 是要连同快照一起归档的。
func legacyEntryDates(
    from now: Date,
    snapshot: WidgetSnapshot,
    calendar: Calendar = .current
) -> [Date] {
    var dates: Set<Date> = [now]

    for slot in snapshot.upcomingSlots {
        if let start = slot.start, start > now { dates.insert(start) }
        if let end = slot.end, end > now { dates.insert(end) }
    }

    if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
        dates.insert(tomorrow)
    }

    if let slot = snapshot.activeSlot(at: now), let start = slot.start, start > now {
        let stop = min(start, now.addingTimeInterval(60 * 60))
        var tick = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 60).rounded(.down) * 60 + 60)

        while tick < stop, dates.count < 120 {
            dates.insert(tick)
            tick = tick.addingTimeInterval(60)
        }
    }

    return Array(dates.filter { $0 >= now }.sorted().prefix(120))
}

func profile(_ name: String, data: AppData, directory: URL) {
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let dataURL = directory.appendingPathComponent("classflow.json")
    let store = FileDataStore(url: dataURL)
    // 数据文件与快照都放进这个临时目录：真机上快照在 App Group 容器里，
    // 而这台 macOS 上容器目录并不存在（写快照会静默失败），测出来的数就没意义了。
    store.widgetSnapshotDirectory = directory
    // 组件里点一下走的就是这条路径：一个 kind 都不点名刷新 ——
    // 被点那张卡的时间线由系统在 `perform()` 返回后保证重排（见 WidgetIntents.swift）。
    store.widgetReloadKinds = []

    let snapshotURL = directory.appendingPathComponent(WidgetSnapshotStore.fileName)
    try? FileManager.default.removeItem(at: dataURL)
    try? FileManager.default.removeItem(at: snapshotURL)

    print("\n=== \(name)：\(data.courses.count) 门课 / \(data.scheduleEntries.count) 条安排 / "
        + "\(data.tasks.count) 待办 / \(data.memos.count) 笔记 ===")

    // 冷启动第一步：把数据文件准备好（不然下面的 load 读的是空文件）
    try? store.save(data)
    if !FileManager.default.fileExists(atPath: snapshotURL.path) {
        print("   ⚠️ 快照没写成功（\(snapshotURL.path)），下面的交互耗时不含快照写入")
    }
    let dataSize = (try? Data(contentsOf: dataURL).count) ?? 0
    print(String(format: "   数据文件 %.0f KB", Double(dataSize) / 1024))

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let payload = (try? Data(contentsOf: dataURL)) ?? Data()

    _ = measure("① 解码数据文件（冷启动必做）") {
        _ = try? decoder.decode(AppData.self, from: payload)
    }

    let pretty = JSONEncoder()
    pretty.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    pretty.dateEncodingStrategy = .iso8601

    let compact = JSONEncoder()
    compact.outputFormatting = [.withoutEscapingSlashes]
    compact.dateEncodingStrategy = .iso8601

    _ = measure("② 编码数据（当前：美化 + 排序）") {
        _ = try? pretty.encode(data)
    }

    _ = measure("② 编码数据（紧凑）") {
        _ = try? compact.encode(data)
    }

    let prettySize = (try? pretty.encode(data).count) ?? 0
    let compactSize = (try? compact.encode(data).count) ?? 0
    print(String(format: "   编码后体积：美化 %.0f KB / 紧凑 %.0f KB", Double(prettySize) / 1024, Double(compactSize) / 1024))

    _ = measure("③ 生成组件快照") {
        _ = WidgetSnapshotStore.makeSnapshot(data: data)
    }

    let snapshot = WidgetSnapshotStore.makeSnapshot(data: data)
    _ = measure("④ 写快照文件") {
        try? WidgetSnapshotStore.save(snapshot, to: snapshotURL)
    }
    let snapshotSize = (try? Data(contentsOf: snapshotURL).count) ?? 0
    print(String(format: "   快照文件 %.0f KB（%d 条 upcoming / %d 个周网格 / %d 条待办）",
                 Double(snapshotSize) / 1024,
                 snapshot.upcomingSlots.count, snapshot.weeks.count, snapshot.todos.count))

    // 时间线规模：系统每次交互后都要重新排一遍，条目是要连同快照一起归档的。
    // 同时把**改动前的排法**复现一遍做对照（旧代码：把 14 天内的开始/结束时刻全塞进去，
    // 只在最后截断到 120 条，所以时间线可能横跨好几天）。
    let now = Date()
    let entryDates = WidgetTimeline.entryDates(from: now, snapshot: snapshot)
    // 大课表 / 待办卡没有分钟级文案，不铺每分钟一条（`minuteTicks: false`）
    let quietDates = WidgetTimeline.entryDates(from: now, snapshot: snapshot, minuteTicks: false)
    // 大课表还要为每一节的开始时刻排一条（八行窗口按时间滑，`periodTicks: true`）——
    // 这些是「版面真的会变」的时刻，不能省；量出来才知道它比待办卡贵多少。
    let weekDates = WidgetTimeline.entryDates(
        from: now, snapshot: snapshot, minuteTicks: false, periodTicks: true
    )
    let legacyDates = legacyEntryDates(from: now, snapshot: snapshot)
    print(String(format: "   时间线：倒计时卡片 %d 条 / 待办卡 %d 条 / 大课表 %d 条（改动前 %d 条；上限 %d），覆盖到 %.1f 小时后",
                 entryDates.count, quietDates.count, weekDates.count, legacyDates.count, WidgetTimeline.entryLimit,
                 (entryDates.last ?? now).timeIntervalSince(now) / 3600))
    print("           （大课表 = 现在 + 零点 + 今天还没到的每一节开始时刻，条数随跑这份基准的钟点变）")
    print(String(format: "   条目归档量级：%.0f KB/条 × 大课表 %d 条 ≈ %.1f MB（改动前 ≈ %.1f MB）",
                 Double(snapshotSize) / 1024, weekDates.count,
                 Double(snapshotSize) * Double(weekDates.count) / 1024 / 1024,
                 Double(snapshotSize) * Double(legacyDates.count) / 1024 / 1024))

    // ⑤ 交互全链路：组件里点一下复选框 = load() + 改 + save()
    //    这段就是用户按下去到 intent 返回之间的真实工作量（**不含系统重排时间线**，
    //    那部分由系统调度，在这台机器上量不出真机上的值）。
    //
    //    每轮都**真的翻转一次**状态（模拟用户连点），而不是反复写同一份数据 ——
    //    改动前的实现无论内容变没变都会重写两遍快照并请求两轮刷新，所以这里的「前」数值
    //    （见 ⑤对照）与「每轮真翻转」是同一口径。
    print("   load 是否要补写快照 = \(WidgetSnapshotStore.needsRefresh(than: dataURL))"
        + "（应为 false：保存之后快照比数据文件新）")

    var toggled = data
    let openIndices = toggled.tasks.indices.filter { toggled.tasks[$0].status.isOpen }
    var round = 0

    func flip() {
        guard !openIndices.isEmpty else { return }
        let index = openIndices[round % openIndices.count]
        toggled.tasks[index].status = toggled.tasks[index].status.isOpen ? .completed : .todo
        round += 1
    }

    _ = measure("⑤a 点按第一步：load()") {
        _ = try? store.load()
    }

    _ = measure("⑤b 点按第二步：翻转 + save()", iterations: 5) {
        flip()
        try? store.save(toggled)
    }

    _ = measure("⑤ 点一下复选框（load + 翻转 + save）", iterations: 5) {
        flip()
        _ = try? store.load()
        try? store.save(toggled)
    }
    // ⑤对照：手工复现**改动前**的调用顺序。旧 `load()` 每次都会重算并重写快照、
    // 再请求刷新全部组件；`save()` 又做一遍。所以同一次点按要写两次快照、刷新两轮。
    _ = measure("⑤对照 改动前：读+写各重写一次快照", iterations: 5) {
        if let payload = try? Data(contentsOf: dataURL),
           let decoded = try? decoder.decode(AppData.self, from: payload) {
            let snapshot = WidgetSnapshotStore.makeSnapshot(data: decoded)
            try? WidgetSnapshotStore.save(snapshot, to: snapshotURL)
            WidgetSnapshotStore.reloadWidgets(of: WidgetKind.all)
        }

        if let payload = try? pretty.encode(toggled) {
            try? payload.write(to: dataURL, options: .atomic)
            let snapshot = WidgetSnapshotStore.makeSnapshot(data: toggled)
            try? WidgetSnapshotStore.save(snapshot, to: snapshotURL)
            WidgetSnapshotStore.reloadWidgets(of: WidgetKind.all)
        }
    }

    // ⑥ 内容没变时的空写（App 里随手保存一次、或同一状态重复保存）：
    //    改动后这里应该几乎不花时间，也不会惊动系统重排时间线。
    _ = measure("⑥ 内容没变的保存（应直接跳过）", iterations: 5) {
        try? store.save(toggled)
    }
}

// MARK: - 主流程

@main
enum WidgetPerfCheck {

    static func main() {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("classflow-widget-perf", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        print("小组件交互性能基准（中位数，单位 ms）")
        print("临时目录：\(directory.path)")

        profile(
            "典型",
            data: makeData(semesterWeeks: 18, courseCount: 8, entriesPerCourse: 2, taskCount: 20, memoCount: 15),
            directory: directory.appendingPathComponent("typical", isDirectory: true)
        )

        profile(
            "重度",
            data: makeData(semesterWeeks: 24, courseCount: 24, entriesPerCourse: 4, taskCount: 200, memoCount: 120),
            directory: directory.appendingPathComponent("heavy", isDirectory: true)
        )

        print("")
    }
}
