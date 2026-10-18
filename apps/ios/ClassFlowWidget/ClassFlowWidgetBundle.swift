import SwiftUI
import WidgetKit

/// ClassFlow 的小组件集合：六个桌面组件共用同一份 `WidgetSnapshot` 快照与卡片视图，
/// 时间线由 `ClassFlowWidgetEntryProvider` 统一调度；此外还承载课程 Live Activity。
@main
struct ClassFlowWidgetBundle: WidgetBundle {

    var body: some Widget {
        NextClassSmallWidget()
        TodayScheduleWidget()
        WeekTimetableWidget()
        TodoWidget()
        QuickMemoWidget()
        DayDoneWidget()
        CourseLiveActivity()
    }
}
