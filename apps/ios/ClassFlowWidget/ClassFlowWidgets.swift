import SwiftUI
import WidgetKit

// MARK: - 时间线

/// 六种组件共用的时间线提供者：排期规则由 `WidgetTimeline` 决定，无需唤醒扩展进程。
struct ClassFlowWidgetEntryProvider: TimelineProvider {

    /// 卡片是否有分钟级变化的文字（倒计时 / 「N 分钟前」）；文案只精确到「天」时应传 `false`。
    var minuteTicks: Bool = true

    /// 版面是否随「上到第几节」变化（如大课表的八行窗口）。
    /// 为 `true` 时需为每一节的开始时刻排一条 entry，否则换课窗口不会推进。
    var periodTicks: Bool = false

    func placeholder(in context: Context) -> ClassFlowWidgetEntry {
        ClassFlowWidgetEntry.placeholder()
    }

    func getSnapshot(in context: Context, completion: @escaping (ClassFlowWidgetEntry) -> Void) {
        completion(entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClassFlowWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = Self.loadSnapshot(now: now)
        let weekOffset = WidgetSnapshotStore.weekOffset()
        let dates = WidgetTimeline.entryDates(
            from: now,
            snapshot: snapshot,
            minuteTicks: minuteTicks,
            periodTicks: periodTicks
        )

        let entries = dates.map {
            ClassFlowWidgetEntry(date: $0, snapshot: snapshot, weekOffset: weekOffset)
        }

        // 时间线止于下一个零点，到点由系统重新请求。
        let refresh = WidgetTimeline.refreshDate(after: dates, from: now)

        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

extension ClassFlowWidgetEntryProvider {

    private func entry(at now: Date) -> ClassFlowWidgetEntry {
        ClassFlowWidgetEntry(
            date: now,
            snapshot: Self.loadSnapshot(now: now),
            weekOffset: WidgetSnapshotStore.weekOffset()
        )
    }

    /// 读共享容器里的快照；快照不是今天就按主 App 的数据就地重算并写回（跨天自愈）。
    /// 数据文件读不到时退回旧快照，卡片不至于因为重算失败变空。
    static func loadSnapshot(now: Date = Date()) -> WidgetSnapshot {
        let dataURL = FileDataStore.defaultURL()
        // 共享容器不可用时退回 App 自己的目录：数据与快照必须用同一个兜底，路径才对得上。
        guard let snapshotURL = WidgetSnapshotStore.fileURL(
            fallbackDirectory: dataURL.deletingLastPathComponent()
        ) else { return .empty }

        return WidgetSnapshotStore.snapshotForWidget(
            dataURL: dataURL,
            snapshotURL: snapshotURL,
            now: now
        )
    }
}

// MARK: - 组件 01：下一节课 · 小尺寸

struct NextClassSmallWidget: Widget {

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.nextClass.rawValue, provider: ClassFlowWidgetEntryProvider()) { entry in
            NextClassSmallEntryView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("下一节课")
        .description("最近一节课的课程名、时间与教室，右上角是倒计时。")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - 组件 02：今日课程 · 中尺寸

struct TodayScheduleWidget: Widget {

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.today.rawValue, provider: ClassFlowWidgetEntryProvider()) { entry in
            TodayScheduleEntryView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("今日课程")
        .description("今天的时间轴：每节课的时刻、课名、教室与当前状态。")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - 组件 03：本周课表 · 大尺寸

struct WeekTimetableWidget: Widget {

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: WidgetKind.week.rawValue,
            provider: ClassFlowWidgetEntryProvider(minuteTicks: false, periodTicks: true)
        ) { entry in
            WeekTimetableEntryView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("本周课表")
        .description("一整周的课程网格，右上角箭头可以前后翻周。")
        .supportedFamilies([.systemLarge])
    }
}

// MARK: - 组件 04：课程待办 · 中尺寸

struct TodoWidget: Widget {

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.todo.rawValue, provider: ClassFlowWidgetEntryProvider(minuteTicks: false)) { entry in
            TodoEntryView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("课程待办")
        .description("即将到期的待办，点圆圈可以直接勾选完成。")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - 组件 05：快速笔记 · 小尺寸

struct QuickMemoWidget: Widget {

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.memo.rawValue, provider: ClassFlowWidgetEntryProvider()) { entry in
            QuickMemoEntryView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("快速笔记")
        .description("最近编辑的一条课程笔记，底部可以直接新建笔记。")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - 组件 06：今日课毕 · 小尺寸

struct DayDoneWidget: Widget {

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.dayDone.rawValue, provider: ClassFlowWidgetEntryProvider()) { entry in
            DayDoneEntryView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("今日课毕")
        .description("一眼看到今天还剩几节课；全部上完后给出收工提示，并预告下一节课。")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - 预览

#Preview("01 下一节课 · 小", as: .systemSmall) {
    NextClassSmallWidget()
} timeline: {
    ClassFlowWidgetEntry.placeholder()
}

#Preview("02 今日课程 · 中", as: .systemMedium) {
    TodayScheduleWidget()
} timeline: {
    ClassFlowWidgetEntry.placeholder()
}

#Preview("03 本周课表 · 大", as: .systemLarge) {
    WeekTimetableWidget()
} timeline: {
    ClassFlowWidgetEntry.placeholder()
}

#Preview("04 课程待办 · 中", as: .systemMedium) {
    TodoWidget()
} timeline: {
    ClassFlowWidgetEntry.placeholder()
}

#Preview("05 快速笔记 · 小", as: .systemSmall) {
    QuickMemoWidget()
} timeline: {
    ClassFlowWidgetEntry.placeholder()
}

#Preview("06 今日课毕 · 小", as: .systemSmall) {
    DayDoneWidget()
} timeline: {
    ClassFlowWidgetEntry.placeholder()
}
