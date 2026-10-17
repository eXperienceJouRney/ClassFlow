import SwiftUI
import WidgetKit

// MARK: - 组件 02：今日课程 · 中尺寸

/// 今日课程列表（中尺寸）：时刻、课名与「地点 · 状态」，每行链接到课程详情。
struct TodayScheduleEntryView: View {

    @Environment(\.colorScheme) private var colorScheme

    let entry: ClassFlowWidgetEntry

    private var style: WidgetStyle { .of(colorScheme) }
    /// 中尺寸可见行数上限：3。
    private let maximumRows = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetSectionHeader(
                title: WidgetText.monthDayWeekdayText(entry.snapshot.today),
                trailing: "\(entry.snapshot.todaySlots.count) 门课",
                style: style
            )

            if visibleSlots.isEmpty {
                Spacer(minLength: 6)
                WidgetEmptyState(
                    title: "今天没有课程",
                    message: "打开 ClassFlow 查看本周安排",
                    style: style,
                    titleSize: 14
                )
                Spacer(minLength: 6)
            } else {
                Spacer(minLength: 8)

                VStack(alignment: .leading, spacing: 9) {
                    ForEach(visibleSlots, id: \.entryId) { slot in
                        row(slot)
                    }
                }

                Spacer(minLength: 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(WidgetDeepLink.url(.scheduleToday))
    }
}

extension TodayScheduleEntryView {

    private var visibleSlots: [WidgetClassSlot] {
        Array(entry.snapshot.todaySlots.prefix(maximumRows))
    }

    private func row(_ slot: WidgetClassSlot) -> some View {
        let highlighted = isHighlighted(slot)

        return WidgetLink(url: WidgetDeepLink.url(.course(slot.courseId)) ?? fallbackURL) {
            HStack(alignment: .center, spacing: 8) {
                // 竖线只高亮当前 / 下一节，其它行等宽留白以保持左对齐。
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(highlighted ? style.primaryText : Color.clear)
                    .frame(width: 3, height: 26)

                Text(slot.startText ?? "待定")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(slot.isTimeConfigured ? style.primaryText : style.secondaryText)
                    .frame(width: 42, alignment: .leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.courseName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(style.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(auxiliaryText(for: slot))
                        .font(.system(size: 11))
                        .foregroundStyle(style.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func isHighlighted(_ slot: WidgetClassSlot) -> Bool {
        entry.snapshot.activeSlot(at: entry.date)?.entryId == slot.entryId
    }

    /// `教室 B201 · 已结束`
    private func auxiliaryText(for slot: WidgetClassSlot) -> String {
        [slot.location, slot.progressText(at: entry.date)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var fallbackURL: URL {
        WidgetDeepLink.url(.scheduleToday) ?? URL(string: "classflow://schedule/today")!
    }
}

// MARK: - 组件 06：今日课毕 · 小尺寸

/// 今日课毕卡片（小尺寸）：今天还剩课时提示「还有 N 节课」。
struct DayDoneEntryView: View {

    @Environment(\.colorScheme) private var colorScheme

    let entry: ClassFlowWidgetEntry

    private var style: WidgetStyle { .of(colorScheme) }

    private var remaining: [WidgetClassSlot] {
        entry.snapshot.todayRemaining(at: entry.date)
    }

    @ViewBuilder
    var body: some View {
        if remaining.isEmpty {
            finished
        } else {
            stillBusy
        }
    }
}

extension DayDoneEntryView {

    private var finished: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetCheckBadge(style: style, size: 32)

            Spacer(minLength: 8)

            Text("休息一下，\n放松片刻。")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(style.primaryText)
                .lineSpacing(2)
                .widgetTextFit(lines: 3, minimumScale: 0.8)

            Spacer(minLength: 6)

            Text("今天没有更多课程。")
                .font(.system(size: 11))
                .foregroundStyle(style.secondaryText)
                .lineLimit(2)

            Spacer(minLength: 6)

            if let hint = nextClassHint {
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(style.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var stillBusy: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetCheckBadge(style: style, size: 32, systemImage: "clock")

            Spacer(minLength: 8)

            Text("今天还有 \(remaining.count) 节课")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(style.primaryText)
                .widgetTextFit(lines: 2, minimumScale: 0.8)

            Spacer(minLength: 6)

            if let slot = remaining.first {
                Text("下一节 \(slot.startText ?? slot.periodText ?? "")")
                    .font(.system(size: 11))
                    .foregroundStyle(style.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(slot.courseName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(style.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// `下节课 · 周二第 5–6 节`；没有更多课程时返回 nil。
    private var nextClassHint: String? {
        guard let slot = entry.snapshot.upcomingSlots.first else { return nil }

        let weekday = WidgetText.weekdayShortName(slot.weekday)
        guard let period = slot.periodText else {
            guard let time = slot.timeText else { return "下节课 · \(weekday)" }
            return "下节课 · \(weekday) \(time)"
        }

        return "下节课 · \(weekday)\(period)"
    }
}

// MARK: - 预览

#Preview("02 今日课程 · 中尺寸画布") {
    TodayScheduleEntryView(entry: .placeholder())
        .frame(width: 338, height: 158)
        .containerBackground(for: .widget) { WidgetPalette.cardLight }
}

#Preview("06 今日课毕 · 小尺寸画布") {
    DayDoneEntryView(entry: .placeholder())
        .frame(width: 158, height: 158)
        .containerBackground(for: .widget) { WidgetPalette.cardLight }
}
