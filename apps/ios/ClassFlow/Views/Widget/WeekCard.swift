import AppIntents
import SwiftUI
import WidgetKit

// MARK: - 组件 03：本周课表 · 大尺寸

/// 一周课程网格：横向周一–周日，纵向固定 8 行课节，窗口按当前时间滑动。
/// 窗口边界避开课块，不把任何一门课切成半截。
/// 课程卡片按节次区间占位并自动分栏，点击整卡打开主 App 对应周课表。
struct WeekTimetableEntryView: View {

    @Environment(\.colorScheme) private var colorScheme

    let entry: ClassFlowWidgetEntry

    private var style: WidgetStyle { .of(colorScheme) }

    /// 纵轴列宽，单位 pt。
    private let axisWidth: CGFloat = 30
    private let columnSpacing: CGFloat = 3
    /// 课程块左侧色条宽度，单位 pt。
    private let colorBarWidth: CGFloat = 2
    /// 显示上课地点的高度门槛，单位 pt。
    private let minimumLocationHeight: CGFloat = 22
    /// 地点排两行的高度门槛，单位 pt。
    private let minimumTwoLineLocationHeight: CGFloat = 30
    /// 地点排三行的高度门槛，单位 pt。
    private let minimumThreeLineLocationHeight: CGFloat = 60
    /// 课名缩一档的高度门槛，单位 pt。
    private let minimumFullTitleHeight: CGFloat = 48

    /// 课程名字号：格子低于门槛时缩一档，下限 7pt。
    private func titleSize(for cellHeight: CGFloat, base: CGFloat) -> CGFloat {
        cellHeight >= minimumFullTitleHeight ? base : max(base - 1, 7)
    }

    /// 上课地点字号：比课名小两档，下限 6pt。
    private func locationSize(for fontSize: CGFloat) -> CGFloat {
        max(fontSize - 3, 6)
    }

    /// 上课地点行数上限：按格子高度取 1–3 行。
    private func locationLineLimit(for cellHeight: CGFloat) -> Int {
        if cellHeight >= minimumThreeLineLocationHeight { return 3 }
        if cellHeight >= minimumTwoLineLocationHeight { return 2 }
        return 1
    }

    @ViewBuilder
    var body: some View {
        if let grid = entry.snapshot.week(offset: entry.weekOffset) {
            content(grid)
        } else {
            empty
        }
    }
}

extension WeekTimetableEntryView {

    private func content(_ grid: WidgetWeekGrid) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(grid)

            dayStrip(grid)
                .padding(.top, 6)

            GeometryReader { proxy in
                gridBody(grid, size: proxy.size)
            }
            .frame(maxHeight: .infinity)
            .padding(.top, 4)
            // 置为内容失效态：刷新期间由系统呈现「正在更新」。
            // 不要再自行调用 reloadTimelines，否则会双轮呈现、置灰态结束两次。
            .invalidatableContent()

            WidgetHairline(color: style.divider)
                .padding(.top, 4)

            Text(statsText)
                .font(.system(size: 10))
                .foregroundStyle(style.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(WidgetDeepLink.url(.scheduleWeek(offset: grid.weekOffset)))
    }

    // MARK: 头部

    private func header(_ grid: WidgetWeekGrid) -> some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(grid.rangeText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(style.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(grid.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(style.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 6)

            HStack(spacing: 6) {
                weekButton(delta: -1, systemImage: "chevron.left", enabled: canShift(grid, by: -1))
                weekButton(delta: 1, systemImage: "chevron.right", enabled: canShift(grid, by: 1))
            }
        }
    }

    /// 周切换按钮：越界一侧置灰并禁用。
    private func weekButton(delta: Int, systemImage: String, enabled: Bool) -> some View {
        Button(intent: ShiftWidgetWeekIntent(delta: delta)) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(enabled ? style.primaryText : style.secondaryText.opacity(0.35))
                .frame(width: 22, height: 22)
                .background(Circle().fill(style.fill))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func canShift(_ grid: WidgetWeekGrid, by delta: Int) -> Bool {
        entry.snapshot.hasWeek(offset: grid.weekOffset + delta)
    }

    // MARK: 日期条

    private func dayStrip(_ grid: WidgetWeekGrid) -> some View {
        HStack(spacing: columnSpacing) {
            Color.clear.frame(width: axisWidth, height: 1)

            ForEach(Array(grid.days.enumerated()), id: \.offset) { _, day in
                dayChip(day, isToday: isToday(day, in: grid))
            }
        }
    }

    private func dayChip(_ day: Date, isToday: Bool) -> some View {
        VStack(spacing: 1) {
            Text(dayLabel(day))
                .font(.system(size: 9))
                .foregroundStyle(isToday ? Color.white : style.secondaryText)

            Text(dayNumber(day))
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(isToday ? Color.white : style.primaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isToday ? WidgetPalette.cardDark : Color.clear)
        )
    }

    private func isToday(_ day: Date, in grid: WidgetWeekGrid) -> Bool {
        grid.weekOffset == 0 && Calendar.current.isDate(day, inSameDayAs: entry.snapshot.today)
    }

    /// `一`
    private func dayLabel(_ day: Date) -> String {
        String(WidgetText.weekdayShortName(WidgetText.isoWeekday(of: day)).suffix(1))
    }

    /// `12`
    private func dayNumber(_ day: Date) -> String {
        String(Calendar.current.component(.day, from: day))
    }

    // MARK: 网格

    private func gridBody(_ grid: WidgetWeekGrid, size: CGSize) -> some View {
        // 八行窗口：窗口恒为 8 行，课节不足 8 节时窗口即整份纵轴，那几行摊满、不补空行。
        // 窗口边界按整周课块避让，见 `WidgetWeekWindow`。
        let window = WidgetWeekWindow.range(in: grid.periods, courses: grid.courses, at: entry.date)
        let periods = Array(grid.periods[window])
        let rowCount = max(periods.count, 1)
        let rowHeight = max(size.height / CGFloat(rowCount), 14)
        let columnWidth = max(
            (size.width - axisWidth - columnSpacing * 7) / 7,
            1
        )
        let fontSize = min(max(rowHeight * 0.28, 8), 11)

        return HStack(alignment: .top, spacing: columnSpacing) {
            axisColumn(periods, rowHeight: rowHeight)
                .frame(width: axisWidth, alignment: .topLeading)

            ForEach(1...7, id: \.self) { weekday in
                weekdayColumn(
                    grid,
                    weekday: weekday,
                    window: window,
                    rowHeight: rowHeight,
                    columnWidth: columnWidth,
                    fontSize: fontSize
                )
                .frame(width: columnWidth, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func axisColumn(_ periods: [WidgetPeriod], rowHeight: CGFloat) -> some View {
        let numberSize = axisNumberSize(for: rowHeight)
        let timeSize = axisTimeSize(for: rowHeight)

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(periods, id: \.number) { period in
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(period.number)")
                        .font(.system(size: numberSize, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(style.primaryText)

                    // 上课与下课各占一行。
                    if let time = period.timeText {
                        axisTime(time, size: timeSize)
                    }

                    if let endTime = period.endTimeText {
                        axisTime(endTime, size: timeSize)
                    }
                }
                // 内边距必须留在 `.frame` 内部，否则左轴逐行累计偏移、课节号对不上格子。
                .padding(.top, 1)
                .frame(height: rowHeight, alignment: .topLeading)
            }
        }
    }

    /// 左轴上的一行时刻：`08:00` 上课、`08:45` 下课；不换行。
    private func axisTime(_ text: String, size: CGFloat) -> some View {
        Text(text)
            .font(.system(size: size))
            .monospacedDigit()
            .foregroundStyle(style.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    /// 左轴课节号字号：单位 pt，随行高三行文字取档。
    private func axisNumberSize(for rowHeight: CGFloat) -> CGFloat {
        min(max(rowHeight * 0.32, 8), 10)
    }

    /// 左轴时刻字号：比课节号小一档。
    private func axisTimeSize(for rowHeight: CGFloat) -> CGFloat {
        min(max(rowHeight * 0.23, 6), 7)
    }

    private func weekdayColumn(
        _ grid: WidgetWeekGrid,
        weekday: Int,
        window: Range<Int>,
        rowHeight: CGFloat,
        columnWidth: CGFloat,
        fontSize: CGFloat
    ) -> some View {
        let cells = grid.courses
            .filter { $0.weekday == weekday }
            .compactMap { course -> (course: WidgetWeekCourse, row: Int, span: Int)? in
                guard let placement = WidgetWeekWindow.placement(of: course, in: grid.periods, window: window)
                else { return nil }

                return (course, placement.row, placement.span)
            }

        // 网格不画横向分隔线；列高必须自行撑出：`.offset` 不参与布局，否则低位课程会被 `.clipped()` 裁掉。
        let columnHeight = rowHeight * CGFloat(max(window.count, 1))

        return ZStack(alignment: .topLeading) {
            ForEach(cells, id: \.course.entryId) { cell in
                let laneWidth = max((columnWidth - 2) / CGFloat(max(cell.course.laneCount, 1)), 1)
                let cellHeight = max(CGFloat(cell.span) * rowHeight - 3, 13)

                courseCell(cell.course, fontSize: fontSize, cellHeight: cellHeight)
                    .frame(width: laneWidth, height: cellHeight, alignment: .topLeading)
                    .offset(
                        x: CGFloat(cell.course.lane) * laneWidth,
                        y: CGFloat(cell.row) * rowHeight + 1.5
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: columnHeight, alignment: .topLeading)
        .clipped()
    }

    private func courseCell(
        _ course: WidgetWeekCourse,
        fontSize: CGFloat,
        cellHeight: CGFloat
    ) -> some View {
        // 配色与 App 内课表块同源：课程颜色 + 左侧色条 + 16% 淡色底。
        let palette = course.color ?? .fallback

        return HStack(spacing: 0) {
            Rectangle()
                .fill(palette.color)
                .frame(width: colorBarWidth)

            VStack(alignment: .center, spacing: 0.5) {
                Text(course.courseName)
                    .font(.system(size: titleSize(for: cellHeight, base: fontSize), weight: .semibold))
                    .foregroundStyle(style.primaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(cellHeight >= 34 ? 2 : 1)
                    .minimumScaleFactor(0.85)

                if let location = course.location, cellHeight >= minimumLocationHeight {
                    Text(location)
                        .font(.system(size: locationSize(for: fontSize)))
                        .foregroundStyle(style.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineLimit(locationLineLimit(for: cellHeight))
                        .minimumScaleFactor(0.6)
                }
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 0.75)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(palette.blockFill)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    // MARK: 底部统计与空态

    private var statsText: String {
        let stats = entry.snapshot.todayStats
        return "今日 \(stats.periodCount) 节课 · 上课 \(stats.durationText)"
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("本周课表")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(style.primaryText)

            Spacer(minLength: 8)

            WidgetEmptyState(
                title: "这一周还没有课程",
                message: "打开 ClassFlow 导入或添加课程安排",
                style: style,
                titleSize: 14
            )

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - 预览

#Preview("03 本周课表 · 大尺寸画布") {
    WeekTimetableEntryView(entry: .placeholder())
        .frame(width: 338, height: 354)
        .containerBackground(for: .widget) { WidgetPalette.cardLight }
}
