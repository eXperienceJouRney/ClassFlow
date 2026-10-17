import SwiftUI
import WidgetKit

// MARK: - 设计令牌

/// 桌面组件的基础配色，浅色 / 深色两套，均为显式固定色值。
enum WidgetPalette {

    /// 浅色卡片底色 `#FFFFFF`
    static let cardLight = Color(red: 1, green: 1, blue: 1)
    /// 页面参考背景 `#F5F5F5`
    static let pageLight = Color(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF5 / 255)
    /// 深色外观下的卡片底色 `#171717`
    static let cardDark = Color(red: 0x17 / 255, green: 0x17 / 255, blue: 0x17 / 255)

    /// 主要文字 `#171717`
    static let textPrimaryLight = Color(red: 0x17 / 255, green: 0x17 / 255, blue: 0x17 / 255)
    /// 次要文字 `#777777`
    static let textSecondaryLight = Color(red: 0x77 / 255, green: 0x77 / 255, blue: 0x77 / 255)
    /// 深色外观下的主要文字 `#FFFFFF`
    static let textPrimaryDark = Color.white
    /// 深色外观下的次要文字 `#858585`
    static let textSecondaryDark = Color(red: 0x85 / 255, green: 0x85 / 255, blue: 0x85 / 255)

    /// 浅色分割线 `#E5E5E5`
    static let dividerLight = Color(red: 0xE5 / 255, green: 0xE5 / 255, blue: 0xE5 / 255)
    /// 深色外观下的分割线 `#393939`
    static let dividerDark = Color(red: 0x39 / 255, green: 0x39 / 255, blue: 0x39 / 255)

    /// 冲突强调 `#D92D20`
    static let conflict = Color(red: 0xD9 / 255, green: 0x2D / 255, blue: 0x20 / 255)

    /// 浅色下的浅灰填充（课程卡片、复选框、圆形图标底）
    static let fillLight = Color(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF2 / 255)
    /// 深色下的浅灰填充
    static let fillDark = Color(red: 0x26 / 255, green: 0x26 / 255, blue: 0x26 / 255)
}

/// 把当前外观解析成一套具体颜色，不覆盖系统外观。
struct WidgetStyle {

    let scheme: ColorScheme

    static func of(_ scheme: ColorScheme) -> WidgetStyle { WidgetStyle(scheme: scheme) }

    static let light = WidgetStyle(scheme: .light)
    static let dark = WidgetStyle(scheme: .dark)

    var isDark: Bool { scheme == .dark }

    var background: Color { isDark ? WidgetPalette.cardDark : WidgetPalette.cardLight }
    var primaryText: Color { isDark ? WidgetPalette.textPrimaryDark : WidgetPalette.textPrimaryLight }
    var secondaryText: Color { isDark ? WidgetPalette.textSecondaryDark : WidgetPalette.textSecondaryLight }
    var divider: Color { isDark ? WidgetPalette.dividerDark : WidgetPalette.dividerLight }
    var fill: Color { isDark ? WidgetPalette.fillDark : WidgetPalette.fillLight }
}

// MARK: - 时间线条目

/// 六种组件共用的时间线条目：一份快照 + 一个时刻。
struct ClassFlowWidgetEntry: TimelineEntry {

    let date: Date
    let snapshot: WidgetSnapshot
    /// 当前停在哪一周：-1 / 0 / 1
    var weekOffset: Int = 0

    static func placeholder(_ date: Date = Date()) -> ClassFlowWidgetEntry {
        ClassFlowWidgetEntry(date: date, snapshot: .placeholder)
    }
}

// MARK: - 共用小部件

/// 浅灰色细分割线，组件内所有分栏统一使用。
struct WidgetHairline: View {

    var color: Color
    var vertical: Bool = false

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

/// 胶囊标签：黑色倒计时胶囊。
struct WidgetChip: View {

    let text: String
    var isProminent: Bool = false
    var fontSize: CGFloat = 12

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(background))
    }

    private var foreground: Color { .white }

    private var background: Color {
        isProminent ? WidgetPalette.conflict : Color(red: 0x17 / 255, green: 0x17 / 255, blue: 0x17 / 255)
    }
}

/// 组件右下角的 `ClassFlow` 署名。
struct WidgetBrandMark: View {

    var color: Color

    var body: some View {
        Text("ClassFlow")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// 组件里的空状态：一行主文案 + 一行可选说明。
struct WidgetEmptyState: View {

    let title: String
    var message: String?
    var style: WidgetStyle
    var titleSize: CGFloat = 15
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(title)
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundStyle(style.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            if let message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(style.secondaryText)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
    }
}

/// 组件区块标题：左标题 + 右计数 + 下方分割线。
struct WidgetSectionHeader: View {

    let title: String
    var trailing: String?
    var style: WidgetStyle
    var titleSize: CGFloat = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(style.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 4)

                if let trailing {
                    Text(trailing)
                        .font(.system(size: 12))
                        .foregroundStyle(style.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            WidgetHairline(color: style.divider)
        }
    }
}

/// 待办左侧的空心 / 已完成复选框，只画状态；点按区域由调用方提供。
struct WidgetCheckCircle: View {

    let isCompleted: Bool
    var style: WidgetStyle
    var size: CGFloat = 15

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    isCompleted ? style.secondaryText.opacity(0.5) : style.secondaryText,
                    lineWidth: 1.2
                )
                .frame(width: size, height: size)

            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.55, weight: .bold))
                    .foregroundStyle(style.secondaryText)
            }
        }
        .frame(width: size, height: size)
    }
}

/// `WidgetCheckCircle` 的 `Toggle` 外观：不接手势，只按 `configuration.isOn` 绘制。
struct WidgetCheckToggleStyle: ToggleStyle {

    var style: WidgetStyle

    func makeBody(configuration: Configuration) -> some View {
        WidgetCheckCircle(isCompleted: configuration.isOn, style: style, size: 15)
            .padding(.top, 1)
            .contentShape(Rectangle())
            .padding(3)
    }
}

/// 顶部的浅灰圆形图标，默认是对勾。
struct WidgetCheckBadge: View {

    var style: WidgetStyle
    var size: CGFloat = 34
    var systemImage: String = "checkmark"

    var body: some View {
        ZStack {
            Circle()
                .fill(style.fill)
                .frame(width: size, height: size)

            Image(systemName: systemImage)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(style.primaryText)
        }
        .frame(width: size, height: size)
    }
}

/// 组件的底色：浅色卡片给白色，深色外观给 `#171717`。
struct WidgetBackground: View {

    @Environment(\.colorScheme) private var colorScheme
    var fixed: Color?

    var body: some View {
        (fixed ?? WidgetStyle.of(colorScheme).background)
    }
}

/// 条目级深链包装：`WIDGET_VISUAL_CHECK` 编译下退化为纯内容。
struct WidgetLink<Content: View>: View {

    let url: URL
    @ViewBuilder var content: Content

    var body: some View {
        #if WIDGET_VISUAL_CHECK
        content
        #else
        Link(destination: url) { content }
        #endif
    }
}

extension View {

    /// 统一处理「长文本不许溢出」：限行 + 允许缩放。
    func widgetTextFit(lines: Int = 1, minimumScale: CGFloat = 0.75) -> some View {
        lineLimit(lines).minimumScaleFactor(minimumScale)
    }
}
