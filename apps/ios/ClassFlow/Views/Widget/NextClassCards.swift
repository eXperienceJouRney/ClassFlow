import SwiftUI
import WidgetKit

// MARK: - 组件 01：下一节课 · 小尺寸

/// 下一节课卡片（小尺寸）：课名、时间、地点与当天日期。
struct NextClassSmallEntryView: View {

    @Environment(\.colorScheme) private var colorScheme

    let entry: ClassFlowWidgetEntry

    private var style: WidgetStyle { .of(colorScheme) }

    @ViewBuilder
    var body: some View {
        if let slot = entry.snapshot.activeSlot(at: entry.date) {
            filled(slot)
        } else {
            empty
        }
    }
}

extension NextClassSmallEntryView {

    private func filled(_ slot: WidgetClassSlot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 4) {
                Text("下一节课")
                    .font(.system(size: 11))
                    .foregroundStyle(style.secondaryText)
                    .lineLimit(1)

                Spacer(minLength: 4)

                WidgetChip(text: chipText(for: slot), fontSize: 11)
            }

            Spacer(minLength: 6)

            Text(slot.courseName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(style.primaryText)
                .widgetTextFit(lines: 2, minimumScale: 0.7)

            Spacer(minLength: 4)

            // 时间未配置时显示占位文案，不得推测开始时间。
            Text(slot.timeText ?? "具体时间待设置")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(slot.isTimeConfigured ? style.primaryText : style.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let detail = slot.locationPeriodText {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(style.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 2)
            }

            Spacer(minLength: 6)

            WidgetHairline(color: style.divider)

            Text(WidgetText.monthDayWeekdayText(entry.snapshot.today))
                .font(.system(size: 10))
                .foregroundStyle(style.secondaryText)
                .lineLimit(1)
                .padding(.top, 5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("下一节课")
                .font(.system(size: 11))
                .foregroundStyle(style.secondaryText)

            Spacer(minLength: 6)

            Text("今天没有更多课程")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(style.primaryText)
                .widgetTextFit(lines: 2, minimumScale: 0.75)

            Text("打开 ClassFlow 查看后续安排")
                .font(.system(size: 10))
                .foregroundStyle(style.secondaryText)
                .lineLimit(2)
                .padding(.top, 3)

            Spacer(minLength: 6)

            WidgetHairline(color: style.divider)

            Text(WidgetText.monthDayWeekdayText(entry.snapshot.today))
                .font(.system(size: 10))
                .foregroundStyle(style.secondaryText)
                .lineLimit(1)
                .padding(.top, 5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 倒计时胶囊文案：时间未配置时返回 `待设置`。
    private func chipText(for slot: WidgetClassSlot) -> String {
        slot.isTimeConfigured ? slot.countdownText(at: entry.date) : "待设置"
    }
}

// MARK: - 预览

#Preview("01 下一节课 · 小尺寸画布") {
    NextClassSmallEntryView(entry: .placeholder())
        .frame(width: 158, height: 158)
        .containerBackground(for: .widget) { WidgetPalette.cardLight }
}
