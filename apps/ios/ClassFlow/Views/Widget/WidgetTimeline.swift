import Foundation

// MARK: - 时间线条目排期

/// 组件时间线要渲染哪些时刻，以及何时请系统重排。
enum WidgetTimeline {

    /// 一条时间线最多塞多少条 entry
    static let entryLimit = 120
    /// 倒计时逐分钟刷新的最长覆盖窗口
    static let countdownWindow: TimeInterval = 60 * 60

    /// 时间线的地平线：下一个零点，快照按天烘焙，越界会把昨天的数据当今天。
    static func horizon(for now: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(24 * 60 * 60)
    }

    /// 需要渲染的时刻集合（升序、去重、含 `now` 与地平线）。
    /// - Parameters: minuteTicks 卡片是否有分钟级文字；periodTicks 版面是否随「上到第几节」变化。
    static func entryDates(
        from now: Date,
        snapshot: WidgetSnapshot,
        minuteTicks: Bool = true,
        periodTicks: Bool = false,
        calendar: Calendar = .current
    ) -> [Date] {
        let horizon = horizon(for: now, calendar: calendar)
        var dates: Set<Date> = [now, horizon]

        for slot in snapshot.upcomingSlots {
            if let start = slot.start, start > now, start < horizon { dates.insert(start) }
            if let end = slot.end, end > now, end < horizon { dates.insert(end) }
        }

        // 整份纵轴里每一节的开始时刻；跨不过零点（地平线就是今天）。
        if periodTicks, let periods = snapshot.currentWeek?.periods {
            let midnight = calendar.startOfDay(for: now)
            for period in periods {
                guard let minute = period.startMinute,
                      let moment = calendar.date(byAdding: .minute, value: minute, to: midnight),
                      moment > now, moment < horizon
                else { continue }

                dates.insert(moment)
            }
        }

        // 倒计时逐分钟：只在下一次「状态变化」之前铺，最多铺一小时，也不越过地平线。
        if minuteTicks,
           let slot = snapshot.activeSlot(at: now),
           let start = slot.start,
           start > now {
            let stop = min(min(start, now.addingTimeInterval(countdownWindow)), horizon)
            // 对齐到下一个整分钟：`10:09:37` → `10:10:00`
            var tick = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 60).rounded(.down) * 60 + 60)

            while tick < stop, dates.count < entryLimit {
                dates.insert(tick)
                tick = tick.addingTimeInterval(60)
            }
        }

        return Array(dates.filter { $0 >= now }.sorted().prefix(entryLimit))
    }

    /// 最后一条 entry 之后请系统重新问一次的时刻：地平线之后再等 60 秒。
    static func refreshDate(
        after entries: [Date],
        from now: Date,
        calendar: Calendar = .current
    ) -> Date {
        let horizon = horizon(for: now, calendar: calendar)
        return max(entries.last ?? now, horizon).addingTimeInterval(60)
    }
}

// MARK: - 大课表的八行窗口

/// 大课表纵轴上的八行窗口：卡片只画连续 8 节课节，窗口随当前时间滑动。
///
/// 窗口起点与终点都不得落在课块内部，否则某门课只会露出半截（例如 1–2 节的课只剩第 2 节）。
/// 起点取「不割裂任何课块」的候选里离理想位置（当前节次 − 3）最近的一个，同样近时取靠前的窗口；
/// 一整周都找不到不割裂的窗口时，取切开课块最少的一个。
/// 不足 8 节时整份纵轴即为窗口，行高摊满。
enum WidgetWeekWindow {

    /// 卡片上固定画几行课节
    static let rowLimit = 8
    /// 当前节次落在窗口的第几行（0 起）
    static let anchorRow = 3

    /// 按「现在」挑窗口：返回窗口在整份纵轴（`WidgetWeekGrid.periods`）里的下标区间。
    /// - Parameter courses: 整周所有课程块；窗口要按它们避让，跨天的课也一样，因为窗口是一天里的固定时段。
    static func range(
        in axis: [WidgetPeriod],
        courses: [WidgetWeekCourse] = [],
        at now: Date,
        calendar: Calendar = .current
    ) -> Range<Int> {
        // 不足 8 节：整份纵轴就是窗口，行高摊满（不补空行）
        guard axis.count > rowLimit else { return axis.indices }

        let start = windowStart(in: axis, courses: courses, at: now, calendar: calendar)
        return start..<(start + rowLimit)
    }

    /// 窗口里的那几节（组件画纵轴、算行高都用它）。
    static func periods(
        in axis: [WidgetPeriod],
        courses: [WidgetWeekCourse] = [],
        at now: Date,
        calendar: Calendar = .current
    ) -> [WidgetPeriod] {
        Array(axis[range(in: axis, courses: courses, at: now, calendar: calendar)])
    }

    /// 在「不割裂课块」的起点里挑一个：优先割裂最少，其次离理想位置最近，最后取靠前的窗口。
    private static func windowStart(
        in axis: [WidgetPeriod],
        courses: [WidgetWeekCourse],
        at now: Date,
        calendar: Calendar
    ) -> Int {
        let lastStart = axis.count - rowLimit
        let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        // `startMinute` 为 nil 的节次用 Int.max 兜底，永远不会「已经开讲」
        let anchor = axis.lastIndex { ($0.startMinute ?? Int.max) <= minute } ?? axis.startIndex
        let ideal = min(max(anchor - anchorRow, axis.startIndex), lastStart)

        // 课块在纵轴里的闭区间（下标）；纵轴里查不到的节次不猜位置。
        let blocks: [(start: Int, end: Int)] = courses.compactMap { course in
            guard let start = axis.firstIndex(where: { $0.number == course.startPeriod }),
                  let end = axis.lastIndex(where: { $0.number == course.endPeriod }),
                  end >= start
            else { return nil }

            return (start, end)
        }

        var best = (start: ideal, cuts: Int.max, distance: Int.max)

        for start in axis.startIndex...lastStart {
            let end = start + rowLimit - 1
            let cuts = blocks.filter { block in
                // 上沿落在课块内部（课块已开始但没画全）或下沿落在课块内部（课块没画完就被截断）
                (block.start < start && block.end >= start)
                    || (block.start >= start && block.start <= end && block.end > end)
            }.count
            let distance = abs(start - ideal)

            // 只严格更好才替换：同样好时保留靠前的窗口，避免一天里来回跳。
            if cuts < best.cuts || (cuts == best.cuts && distance < best.distance) {
                best = (start, cuts, distance)
            }
        }

        return best.start
    }

    /// 一节课在窗口里占的行（0 起）与占几行；整块滑出窗口时返回 nil。
    /// 正常情况下窗口起点避开了课块边界，这里不会裁到课；只有极端排课（找不到不割裂的窗口）
    /// 才会用到裁剪。分栏在完整纵轴上计算，裁剪不会让不重叠的课重叠。
    static func placement(
        of course: WidgetWeekCourse,
        in axis: [WidgetPeriod],
        window: Range<Int>
    ) -> (row: Int, span: Int)? {
        guard window.lowerBound < window.upperBound,
              let start = axis.firstIndex(where: { $0.number == course.startPeriod }),
              let end = axis.lastIndex(where: { $0.number == course.endPeriod })
        else { return nil }

        let first = window.lowerBound
        let last = window.upperBound - 1
        guard end >= first, start <= last else { return nil }

        let visibleStart = max(start, first)
        let visibleEnd = min(end, last)
        return (row: visibleStart - first, span: visibleEnd - visibleStart + 1)
    }
}
