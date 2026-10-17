import Foundation

/// 课表网格的纯布局计算（不依赖 SwiftUI）。
/// 只负责每门课放在哪一行的哪个位置，重叠课程在列内分栏，界面只做渲染。
struct ScheduleGridLayout: Equatable {

    /// 网格尺寸常量；界面层从这里取值
    enum Metrics {
        /// 每一节的行高
        static let periodRowHeight: CGFloat = 44
        /// 没有课时也要撑出的最少课节数
        static let minimumPeriods = 8
        /// 课程块之间的竖直间隙
        static let blockGap: CGFloat = 2
        /// 自定时间换算出来的块最低高度
        static let minimumBlockHeight: CGFloat = 22
    }

    /// 纵轴：一行 = 一节
    struct Axis: Equatable {

        /// 左轴上的一节
        struct Row: Hashable {

            let periodNumber: Int
            /// 这一节的开始时刻；作息里没这一节时为 nil
            let startTime: TimeOfDay?
            /// 这一节的结束时刻；作息里没这一节时为 nil
            let endTime: TimeOfDay?

            /// 左轴第一行文字：`第1节`
            var periodText: String { "第\(periodNumber)节" }

            /// 左轴第二行文字：`08:00`（上课时刻）；没有时刻就没有这一行
            func startTimeText(format: TimeFormatPreference) -> String? {
                startTime?.displayText(format: format)
            }

            /// 左轴第三行文字：`08:45`（下课时刻）；没有时刻就没有这一行
            func endTimeText(format: TimeFormatPreference) -> String? {
                endTime?.displayText(format: format)
            }

            /// `08:00-08:45`；没有时刻时为 nil
            func timeRangeText(format: TimeFormatPreference) -> String? {
                guard let startTime, let endTime else { return nil }
                return "\(startTime.displayText(format: format))-\(endTime.displayText(format: format))"
            }
        }

        /// 时间锚点：某个钟点（从零点起的分钟数）落在纵轴上的哪个 y。
        struct TimeAnchor: Equatable {

            let minutes: Int
            let offset: CGFloat
        }

        let rows: [Row]
        let rowHeight: CGFloat
        /// 由 `rows` 派生，只服务 `offset(for:)` 的钟点换算
        private let timeAnchors: [TimeAnchor]

        init(rows: [Row], rowHeight: CGFloat = Metrics.periodRowHeight) {
            self.rows = rows
            self.rowHeight = rowHeight
            self.timeAnchors = Self.makeTimeAnchors(rows: rows, rowHeight: rowHeight)
        }

        var rowCount: Int { rows.count }
        var totalHeight: CGFloat { CGFloat(rows.count) * rowHeight }

        func offset(forRow row: Int) -> CGFloat { CGFloat(row) * rowHeight }

        /// 课节号 → 行下标
        func rowIndex(forPeriod periodNumber: Int) -> Int? {
            rows.firstIndex { $0.periodNumber == periodNumber }
        }

        /// 钟点 → 纵坐标；作息里一个时刻都没有（左轴是补出来的空行）时返回 nil。
        func offset(for time: TimeOfDay) -> CGFloat? {
            offset(forMinutes: time.minutesFromMidnight)
        }

        /// 钟点 → 纵坐标；越界值按最近一段外推，由调用方夹取。
        func offset(forMinutes minutes: Int) -> CGFloat? {
            guard let first = timeAnchors.first, let last = timeAnchors.last else { return nil }

            if minutes <= first.minutes {
                return first.offset + CGFloat(minutes - first.minutes) * leadingScale
            }
            if minutes >= last.minutes {
                return last.offset + CGFloat(minutes - last.minutes) * trailingScale
            }

            for index in 1..<timeAnchors.count {
                let lower = timeAnchors[index - 1]
                let upper = timeAnchors[index]
                guard minutes <= upper.minutes else { continue }

                let span = CGFloat(upper.minutes - lower.minutes)
                guard span > 0 else { return upper.offset }

                let ratio = CGFloat(minutes - lower.minutes) / span
                return lower.offset + ratio * (upper.offset - lower.offset)
            }

            return last.offset
        }
    }

    /// 一个课程块在网格中的位置
    struct Block: Identifiable, Equatable {

        let id: UUID
        let occurrence: ClassOccurrence
        let dayIndex: Int
        let top: CGFloat
        let height: CGFloat
        let lane: Int
        let laneCount: Int
    }

    let axis: Axis
    let blocks: [Block]

    init(
        timetable: Timetable,
        dates: [CalendarDate],
        calendar: Calendar = .current
    ) {
        let axis = Self.makeAxis(timetable: timetable, dates: dates, calendar: calendar)
        self.axis = axis
        self.blocks = Self.makeBlocks(
            timetable: timetable,
            dates: dates,
            axis: axis,
            calendar: calendar
        )
    }
}

// MARK: - 钟点换算

extension ScheduleGridLayout.Axis {

    /// 锚点不足两段时假定的单节课分钟数，用于估算换算比例。
    private static let assumedPeriodMinutes: CGFloat = 45

    /// 收集锚点：一行（一节）贡献「开始时刻 → 行首」「结束时刻 → 行尾」两个点。
    /// 时刻与纵坐标不严格递增的锚点被丢弃。
    private static func makeTimeAnchors(rows: [Row], rowHeight: CGFloat) -> [TimeAnchor] {
        var anchors: [TimeAnchor] = []

        for (index, row) in rows.enumerated() {
            guard let startTime = row.startTime, let endTime = row.endTime else { continue }

            let top = CGFloat(index) * rowHeight
            let bottom = top + rowHeight

            for anchor in [
                TimeAnchor(minutes: startTime.minutesFromMidnight, offset: top),
                TimeAnchor(minutes: endTime.minutesFromMidnight, offset: bottom),
            ] {
                if let last = anchors.last, anchor.minutes <= last.minutes || anchor.offset < last.offset {
                    continue
                }
                anchors.append(anchor)
            }
        }

        return anchors
    }

    /// 网格顶部之上（早于第一节）的换算比例（pt/分钟）。
    private var leadingScale: CGFloat {
        Self.scale(of: Array(timeAnchors.prefix(2)))
    }

    /// 网格底部之下（晚于最后一节）的换算比例（pt/分钟）。
    private var trailingScale: CGFloat {
        Self.scale(of: Array(timeAnchors.suffix(2)))
    }

    private static func scale(of anchors: [TimeAnchor]) -> CGFloat {
        guard anchors.count == 2 else {
            return ScheduleGridLayout.Metrics.periodRowHeight / assumedPeriodMinutes
        }

        let minutes = CGFloat(anchors[1].minutes - anchors[0].minutes)
        guard minutes > 0 else {
            return ScheduleGridLayout.Metrics.periodRowHeight / assumedPeriodMinutes
        }

        return (anchors[1].offset - anchors[0].offset) / minutes
    }
}

// MARK: - 纵轴

extension ScheduleGridLayout {

    /// 左轴：一行一节，行数取最大课节号与 `Metrics.minimumPeriods` 的较大值。
    private static func makeAxis(
        timetable: Timetable,
        dates: [CalendarDate],
        calendar: Calendar
    ) -> Axis {
        let periods = timetable.periods.sorted { $0.periodNumber < $1.periodNumber }
        let timesByNumber = Dictionary(
            periods.map { ($0.periodNumber, ($0.startTime, $0.endTime)) },
            uniquingKeysWith: { first, _ in first }
        )

        let referenced = dates
            .flatMap { timetable.classes(on: $0, calendar: calendar) }
            .compactMap { $0.classTime.periodRange?.end }

        let lastNumber = max(
            max(timesByNumber.keys.max() ?? 0, referenced.max() ?? 0),
            Metrics.minimumPeriods
        )

        let rows = (1...lastNumber).map { number in
            let times = timesByNumber[number]
            return Axis.Row(
                periodNumber: number,
                startTime: times?.0,
                endTime: times?.1
            )
        }

        return Axis(rows: rows, rowHeight: Metrics.periodRowHeight)
    }
}

// MARK: - 课程块定位

extension ScheduleGridLayout {

    private static func makeBlocks(
        timetable: Timetable,
        dates: [CalendarDate],
        axis: Axis,
        calendar: Calendar
    ) -> [Block] {
        var blocks: [Block] = []

        for (dayIndex, date) in dates.enumerated() {
            let slots = timetable.classes(on: date, calendar: calendar)
                .map { occurrence -> (occurrence: ClassOccurrence, top: CGFloat, height: CGFloat) in
                    let slot = verticalSlot(for: occurrence, axis: axis)
                    return (occurrence, slot.top, slot.height)
                }
                .sorted { $0.top < $1.top }

            for cluster in overlapClusters(of: slots) {
                var laneEnds: [CGFloat] = []
                var assigned: [(slot: (occurrence: ClassOccurrence, top: CGFloat, height: CGFloat), lane: Int)] = []

                for slot in cluster {
                    if let lane = laneEnds.firstIndex(where: { $0 <= slot.top + 0.5 }) {
                        laneEnds[lane] = slot.top + slot.height
                        assigned.append((slot, lane))
                    } else {
                        laneEnds.append(slot.top + slot.height)
                        assigned.append((slot, laneEnds.count - 1))
                    }
                }

                let laneCount = max(laneEnds.count, 1)
                for entry in assigned {
                    blocks.append(
                        Block(
                            id: entry.slot.occurrence.id,
                            occurrence: entry.slot.occurrence,
                            dayIndex: dayIndex,
                            top: entry.slot.top,
                            height: entry.slot.height,
                            lane: entry.lane,
                            laneCount: laneCount
                        )
                    )
                }
            }
        }

        return blocks
    }

    /// 把首尾相接的块归成同一组，组内再分栏。
    private static func overlapClusters(
        of slots: [(occurrence: ClassOccurrence, top: CGFloat, height: CGFloat)]
    ) -> [[(occurrence: ClassOccurrence, top: CGFloat, height: CGFloat)]] {
        var clusters: [[(occurrence: ClassOccurrence, top: CGFloat, height: CGFloat)]] = []

        for slot in slots {
            if var last = clusters.last,
               let bottom = last.map({ $0.top + $0.height }).max(),
               slot.top < bottom - 0.5 {
                last.append(slot)
                clusters[clusters.count - 1] = last
            } else {
                clusters.append([slot])
            }
        }

        return clusters
    }

    /// 把一门课落到轴上，返回其上下边界与高度。
    private static func verticalSlot(
        for occurrence: ClassOccurrence,
        axis: Axis
    ) -> (top: CGFloat, height: CGFloat) {
        if let range = occurrence.classTime.periodRange,
           let startRow = axis.rowIndex(forPeriod: range.start),
           let endRow = axis.rowIndex(forPeriod: range.end) {
            let rows = max(endRow - startRow + 1, 1)
            return (
                axis.offset(forRow: startRow),
                CGFloat(rows) * axis.rowHeight - Metrics.blockGap
            )
        }

        if let clockTime = occurrence.clockTime,
           let top = axis.offset(for: clockTime.start),
           let bottom = axis.offset(for: clockTime.end) {
            return clampedSlot(top: top, bottom: bottom, axis: axis)
        }

        let row = occurrence.classTime.periodRange
            .flatMap { axis.rowIndex(forPeriod: $0.start) }
            ?? 0

        return (axis.offset(forRow: row), axis.rowHeight - Metrics.blockGap)
    }

    /// 把按钟点算出的上下边界夹进 `0...axis.totalHeight`，高度不小于 `Metrics.minimumBlockHeight`。
    private static func clampedSlot(
        top: CGFloat,
        bottom: CGFloat,
        axis: Axis
    ) -> (top: CGFloat, height: CGFloat) {
        let available = axis.totalHeight
        let duration = min(max(bottom - top, 0), available)
        let height = max(duration - Metrics.blockGap, Metrics.minimumBlockHeight)
        let clampedTop = min(max(top, 0), max(available - height, 0))

        return (clampedTop, height)
    }
}
