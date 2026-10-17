import SwiftUI

/// 课表网格（日视图一列、周视图七列共用）：左轴为课节与时刻，右侧每天一列，课块按时间定位。
struct ScheduleGridView: View {

    let timetable: Timetable
    let dates: [CalendarDate]
    var timeFormat: TimeFormatPreference = .twentyFourHour
    var showsDayHeader: Bool = true
    /// 点击列头跳转（周视图用；为 nil 时列头不可点）
    var onSelectDay: ((CalendarDate) -> Void)? = nil
    /// 点击课程块 → 底部面板
    var onSelectCourse: ((Course) -> Void)? = nil
    /// 课程块里是否显示授课教师（设置里的「周视图显示教师」；日视图一列很宽，始终显示）
    var showsTeacherInCourseBlock: Bool = true

    private let calendar = Calendar.current
    private let columnSpacing = DesignTokens.Grid.columnSpacing
    private let headerHeight: CGFloat = 34

    var body: some View {
        let layout = ScheduleGridLayout(
            timetable: timetable,
            dates: dates,
            calendar: calendar
        )

        GeometryReader { proxy in
            let available = proxy.size.width
                - DesignTokens.Grid.axisWidth
                - CGFloat(max(dates.count - 1, 0)) * columnSpacing
            let columnWidth = max(28, available / CGFloat(max(dates.count, 1)))

            VStack(spacing: 0) {
                if showsDayHeader {
                    dayHeaderRow(columnWidth: columnWidth)
                }

                HStack(alignment: .top, spacing: columnSpacing) {
                    axisColumn(axis: layout.axis)

                    ForEach(Array(dates.enumerated()), id: \.element) { index, _ in
                        dayColumn(
                            axis: layout.axis,
                            columnWidth: columnWidth,
                            blocks: layout.blocks.filter { $0.dayIndex == index }
                        )
                    }
                }
            }
        }
        .frame(height: layoutHeight(layout))
    }
}

// MARK: - 轴与列

extension ScheduleGridView {

    private func layoutHeight(_ layout: ScheduleGridLayout) -> CGFloat {
        layout.axis.totalHeight + (showsDayHeader ? headerHeight : 0)
    }

    /// 左轴：一行一节，行内为课节号、上课时刻、下课时刻；该节无作息时只显示课节号。
    private func axisColumn(axis: ScheduleGridLayout.Axis) -> some View {
        VStack(spacing: 0) {
            ForEach(axis.rows, id: \.self) { row in
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(row.periodNumber)")
                        .font(DesignTokens.Typography.gridAxisNumber)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    if let time = row.startTimeText(format: timeFormat) {
                        axisTimeText(time)
                    }

                    if let time = row.endTimeText(format: timeFormat) {
                        axisTimeText(time)
                    }
                }
                // 内边距必须留在 `.frame` 里面：写在外面会把行撑成 46pt，左轴与右列课块逐行错位。
                .padding(.top, 2)
                .frame(width: DesignTokens.Grid.axisWidth, height: axis.rowHeight, alignment: .topLeading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(axisAccessibilityLabel(row: row))
            }
        }
        .frame(width: DesignTokens.Grid.axisWidth, alignment: .top)
    }

    private func axisTimeText(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.Typography.gridAxisTime)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    /// 左轴一行的无障碍文案，格式 `第1节 08:00-08:45`；该节无作息时只有课节号。
    private func axisAccessibilityLabel(row: ScheduleGridLayout.Axis.Row) -> String {
        guard let range = row.timeRangeText(format: timeFormat) else { return row.periodText }
        return "\(row.periodText) \(range)"
    }

    private func dayHeaderRow(columnWidth: CGFloat) -> some View {
        HStack(spacing: columnSpacing) {
            Color.clear.frame(width: DesignTokens.Grid.axisWidth, height: headerHeight)

            ForEach(dates, id: \.self) { date in
                let isToday = date == CalendarDate.today()
                let weekday = date.weekday(calendar: calendar)?.shortName.replacingOccurrences(of: "周", with: "") ?? ""

                Button {
                    onSelectDay?(date)
                } label: {
                    VStack(spacing: 1) {
                        Text(weekday)
                            .font(DesignTokens.Typography.label)
                            .foregroundStyle(.secondary)
                        Text("\(date.day)")
                            .font(DesignTokens.Typography.secondary.weight(.semibold))
                            .foregroundStyle(isToday ? Color.accentColor : Color.primary)
                    }
                    .frame(width: columnWidth, height: headerHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(onSelectDay == nil)
            }
        }
    }

    private func dayColumn(
        axis: ScheduleGridLayout.Axis,
        columnWidth: CGFloat,
        blocks: [ScheduleGridLayout.Block]
    ) -> some View {
        ZStack(alignment: .topLeading) {
            rowLines(axis: axis, columnWidth: columnWidth)

            ForEach(blocks) { block in
                let laneWidth = (columnWidth - 2) / CGFloat(block.laneCount)

                Button {
                    onSelectCourse?(block.occurrence.course)
                } label: {
                    ClassBlockView(
                        occurrence: block.occurrence,
                        isCompact: dates.count > 1,
                        showsTeacher: showsTeacherInCourseBlock
                    )
                }
                .buttonStyle(.plain)
                .disabled(onSelectCourse == nil)
                .frame(width: max(laneWidth - 1, 20), height: block.height, alignment: .top)
                .offset(x: CGFloat(block.lane) * laneWidth, y: block.top)
            }
        }
        .frame(width: columnWidth, height: axis.totalHeight, alignment: .topLeading)
    }

    private func rowLines(axis: ScheduleGridLayout.Axis, columnWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<axis.rowCount, id: \.self) { row in
                Rectangle()
                    .fill(Color(uiColor: .separator).opacity(row == 0 ? 0 : 0.35))
                    .frame(width: columnWidth, height: 1)
                    .frame(height: axis.rowHeight, alignment: .top)
            }
        }
    }
}

#Preview("周课表网格") {
    let seed = PreviewSupport.seed

    NavigationStack {
        ScheduleGridView(timetable: seed.timetable, dates: seed.timetable.dates(inWeek: 1))
    }
    .environment(seed.store)
}

#Preview("周课表网格 · 没有课的一周") {
    let store = PreviewSupport.emptyStore
    let timetable = store.timetable(for: store.currentSemester!.id)!

    NavigationStack {
        ScheduleGridView(timetable: timetable, dates: timetable.dates(inWeek: 1))
    }
    .environment(store)
}

#Preview("日课表网格") {
    let seed = PreviewSupport.seed

    NavigationStack {
        ScheduleGridView(
            timetable: seed.timetable,
            dates: [seed.monday],
            showsDayHeader: false
        )
    }
    .environment(seed.store)
}
