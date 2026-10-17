import SwiftUI

/// 日视图：单列课表网格，左轴为课节与上课 / 下课时刻。
struct DayScheduleView: View {

    let timetable: Timetable
    let date: CalendarDate
    var timeFormat: TimeFormatPreference = .twentyFourHour
    /// 点课程块 → 底部面板
    var onSelectCourse: ((Course) -> Void)? = nil
    /// 左右滑动翻页（+1 = 后一天，-1 = 前一天）
    var onSwipePage: ((Int) -> Void)? = nil

    var body: some View {
        let classes = timetable.classes(on: date)

        ScrollView {
            if classes.isEmpty {
                EmptyStateView(
                    icon: "cup.and.saucer",
                    title: "这天没有课",
                    message: "换一天看看，或者到设置里检查课程的上课安排。"
                )
                .frame(minHeight: 260)
            } else {
                ScheduleGridView(
                    timetable: timetable,
                    dates: [date],
                    timeFormat: timeFormat,
                    showsDayHeader: false,
                    onSelectCourse: onSelectCourse
                )
                .padding(.horizontal, DesignTokens.Spacing.page)
                .padding(.vertical, DesignTokens.Spacing.item)
            }
        }
        .pageSwipe(next: "后一天", previous: "前一天") { delta in onSwipePage?(delta) }
    }
}

#Preview("日视图") {
    let seed = PreviewSupport.seed

    NavigationStack {
        DayScheduleView(timetable: seed.timetable, date: seed.monday)
    }
    .environment(seed.store)
}

#Preview("日视图 · 这天没有课") {
    let seed = PreviewSupport.seed
    let sunday = seed.timetable.dates(inWeek: 1).first { $0.weekday() == .sunday } ?? seed.monday

    NavigationStack {
        DayScheduleView(timetable: seed.timetable, date: sunday)
    }
    .environment(seed.store)
}

#Preview("日视图 · 还没有配置作息（用内置默认作息）") {
    let store = PreviewSupport.emptyStore
    let timetable = store.timetable(for: store.currentSemester!.id)!

    NavigationStack {
        DayScheduleView(timetable: timetable, date: timetable.dates(inWeek: 1).first!)
    }
    .environment(store)
}
