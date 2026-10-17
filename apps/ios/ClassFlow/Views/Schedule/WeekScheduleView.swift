import SwiftUI

/// 周视图：七列课表网格（横轴七天，纵轴「课节 + 时刻」）。
struct WeekScheduleView: View {

    let timetable: Timetable
    let week: Int
    var timeFormat: TimeFormatPreference = .twentyFourHour
    /// 一周日期的排列起点（偏好设置里的「每周起始日」）
    var firstWeekday: Weekday = .monday
    /// 课程块里是否显示授课教师（偏好设置里的「周视图显示教师」）
    var showsTeacherInCourseBlock: Bool = true
    var onSelectDay: (CalendarDate) -> Void
    /// 点课程块 → 底部面板
    var onSelectCourse: ((Course) -> Void)? = nil
    /// 左右滑动翻页（+1 = 下一周，-1 = 上一周）
    var onSwipePage: ((Int) -> Void)? = nil

    var body: some View {
        let dates = timetable.dates(inWeek: week).ordered(from: firstWeekday)

        ScrollView {
            if dates.isEmpty {
                EmptyStateView(icon: "calendar", title: "没有这一周", message: "这个学期还没有这么多周。")
                    .frame(minHeight: 260)
            } else {
                ScheduleGridView(
                    timetable: timetable,
                    dates: dates,
                    timeFormat: timeFormat,
                    showsDayHeader: true,
                    onSelectDay: onSelectDay,
                    onSelectCourse: onSelectCourse,
                    showsTeacherInCourseBlock: showsTeacherInCourseBlock
                )
                .padding(.horizontal, DesignTokens.Spacing.page)
                .padding(.vertical, DesignTokens.Spacing.item)
            }
        }
        .pageSwipe(next: "下一周", previous: "上一周") { delta in onSwipePage?(delta) }
    }
}

#Preview("周视图") {
    let seed = PreviewSupport.seed

    NavigationStack {
        WeekScheduleView(timetable: seed.timetable, week: 1) { _ in }
    }
    .environment(seed.store)
}

#Preview("周视图 · 时间冲突") {
    let scenario = PreviewSupport.conflictScenario

    NavigationStack {
        WeekScheduleView(timetable: scenario.timetable, week: 1) { _ in }
    }
    .environment(scenario.store)
}

#Preview("周视图 · 超出学期周次") {
    let seed = PreviewSupport.seed

    NavigationStack {
        WeekScheduleView(timetable: seed.timetable, week: 99) { _ in }
    }
    .environment(seed.store)
}
