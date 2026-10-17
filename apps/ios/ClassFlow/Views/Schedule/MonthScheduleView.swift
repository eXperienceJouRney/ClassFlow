import SwiftUI

/// 月视图：月历网格（有课 / 有到期待办的日子带圆点）与选中日期的课程、到期待办。
struct MonthScheduleView: View {

    @Environment(AppStore.self) private var store

    let timetable: Timetable
    let anchor: CalendarDate

    @Binding var selectedDate: CalendarDate

    /// 点课程 → 底部面板
    var onSelectCourse: ((Course) -> Void)? = nil
    /// 点到期待办 → 编辑
    var onSelectTask: ((CourseTask) -> Void)? = nil
    var timeFormat: TimeFormatPreference = .twentyFourHour
    /// 月网格的起始星期（偏好设置里的「每周起始日」）
    var firstWeekday: Weekday = .monday
    /// 左右滑动翻页（+1 = 下一个月，-1 = 上一个月）
    var onSwipePage: ((Int) -> Void)? = nil

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.item) {
                    calendarGrid
                    legend
                }

                Divider()

                selectedDaySection
            }
            .padding(DesignTokens.Spacing.page)
        }
        .pageSwipe(next: "下个月", previous: "上个月") { delta in onSwipePage?(delta) }
    }
}

// MARK: - 月历网格
extension MonthScheduleView {

    private var calendarGrid: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(weekdayOrder, id: \.self) { weekday in
                    Text(weekday.shortName.replacingOccurrences(of: "周", with: ""))
                        .font(DesignTokens.Typography.label)
                        .foregroundStyle(weekday.isWeekend ? Color.secondary : Color.primary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, cell in
                    if let cell {
                        dayCell(cell)
                    } else {
                        Color.clear.frame(height: 46)
                    }
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: DesignTokens.Spacing.section) {
            legendItem(color: .accentColor, title: "上课")
            legendItem(color: .orange, title: "待办到期")
        }
        .padding(.top, 2)
    }

    private func legendItem(color: Color, title: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(title)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func dayCell(_ date: CalendarDate) -> some View {
        let isSelected = date == selectedDate
        let isToday = date == CalendarDate.today()
        let hasClasses = !timetable.classes(on: date).isEmpty
        let hasTasks = !tasks(on: date).isEmpty

        return Button {
            selectedDate = date
        } label: {
            VStack(spacing: 3) {
                Text("\(date.day)")
                    .font(DesignTokens.Typography.secondary)
                    .fontWeight(isSelected || isToday ? .semibold : .regular)
                    .foregroundStyle(isSelected ? Color.white : (isToday ? Color.accentColor : Color.primary))

                HStack(spacing: 3) {
                    Circle()
                        .fill(isSelected ? Color.white : Color.accentColor)
                        .frame(width: 4, height: 4)
                        .opacity(hasClasses ? 1 : 0)

                    Circle()
                        .fill(isSelected ? Color.white : Color.orange)
                        .frame(width: 4, height: 4)
                        .opacity(hasTasks ? 1 : 0)
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var selectedDaySection: some View {
        let classes = timetable.classes(on: selectedDate)
        let dueTasks = tasks(on: selectedDate)

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.item) {
            HStack(spacing: 6) {
                Text(selectedDate.monthDayText)
                    .font(DesignTokens.Typography.sectionTitle)

                Text(selectedDate.weekday(calendar: calendar)?.fullName ?? "")
                    .font(DesignTokens.Typography.secondary)
                    .foregroundStyle(.secondary)

                Spacer()

                if let week = timetable.semester.weekIndex(of: selectedDate, calendar: calendar) {
                    Text("第 \(week) 周")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if classes.isEmpty && dueTasks.isEmpty {
                Text("这天没有安排")
                    .font(DesignTokens.Typography.secondary)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }

            if !classes.isEmpty {
                groupTitle("课程")

                ForEach(classes) { occurrence in
                    Button {
                        onSelectCourse?(occurrence.course)
                    } label: {
                        ClassCardView(occurrence: occurrence, timeFormat: timeFormat)
                    }
                    .buttonStyle(.plain)
                    .disabled(onSelectCourse == nil)
                }
            }

            if !dueTasks.isEmpty {
                groupTitle("到期待办")

                ForEach(dueTasks) { task in
                    TaskRowView(task: task, showsCourse: true) {
                        onSelectTask?(task)
                    }
                }
            }
        }
    }

    private func groupTitle(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.Typography.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 2)
    }

    private func tasks(on date: CalendarDate) -> [CourseTask] {
        store.allTasks.filter { $0.dueDate == date }
    }

    /// 月网格的表头顺序：从偏好设置里的「每周起始日」开始。
    private var weekdayOrder: [Weekday] {
        let all = Weekday.allCases.sorted { $0.rawValue < $1.rawValue }
        guard let index = all.firstIndex(of: firstWeekday) else { return all }
        return Array(all[index...]) + Array(all[..<index])
    }

    private var monthCells: [CalendarDate?] {
        let first = anchor.startOfMonth
        let last = anchor.endOfMonth
        let weekdayValue = first.weekday(calendar: calendar)?.rawValue ?? 1
        let leading = (weekdayValue - firstWeekday.rawValue + 7) % 7

        var cells: [CalendarDate?] = Array(repeating: nil, count: leading)
        for day in 1...last.day {
            cells.append(CalendarDate(year: anchor.year, month: anchor.month, day: day))
        }
        return cells
    }
}

#Preview("月视图 · 选中 10 月 15 日") {
    let seed = PreviewSupport.seed

    NavigationStack {
        MonthScheduleView(
            timetable: seed.timetable,
            anchor: CalendarDate("2026-10-01")!,
            selectedDate: .constant(CalendarDate("2026-10-15")!)
        )
    }
    .environment(seed.store)
}
