import SwiftUI
import WidgetKit

/// ClassFlow 的桌面小组件集合：六个组件共用同一份 `WidgetSnapshot` 快照与卡片视图，
/// 时间线由 `ClassFlowWidgetEntryProvider` 统一调度。
@main
struct ClassFlowWidgetBundle: WidgetBundle {

    var body: some Widget {
        NextClassSmallWidget()
        TodayScheduleWidget()
        WeekTimetableWidget()
        TodoWidget()
        QuickMemoWidget()
        DayDoneWidget()
    }
}
