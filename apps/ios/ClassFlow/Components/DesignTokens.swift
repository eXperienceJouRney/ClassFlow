import SwiftUI

/// 界面结构令牌：间距、圆角、字号层级与课表网格尺寸。
enum DesignTokens {

    /// 间距
    enum Spacing {
        /// 页面左右边距
        static let page: CGFloat = 16
        /// 区块之间
        static let section: CGFloat = 20
        /// 区块内元素之间
        static let item: CGFloat = 10
        /// 卡片内边距
        static let card: CGFloat = 12
        /// 紧凑行间距
        static let tight: CGFloat = 6
    }

    /// 圆角
    enum Radius {
        static let card: CGFloat = 12
        static let block: CGFloat = 8
        static let control: CGFloat = 8
        static let chip: CGFloat = 999
    }

    /// 字号层级。
    enum Typography {
        /// 页面大标题（如「1月12日周一」）
        static let pageTitle = Font.system(size: 28, weight: .semibold)
        /// 页面副标题（如学期名）
        static let pageSubtitle = Font.system(size: 15, weight: .regular)
        /// 区块标题 / 卡片标题
        static let sectionTitle = Font.system(size: 17, weight: .semibold)
        /// 正文
        static let body = Font.system(size: 17, weight: .regular)
        /// 列表行主文字
        static let rowTitle = Font.system(size: 17, weight: .regular)
        /// 次要信息（时间、地点）
        static let secondary = Font.system(size: 15, weight: .regular)
        /// 说明文字
        static let caption = Font.system(size: 13, weight: .regular)
        /// 标签
        static let label = Font.system(size: 11, weight: .medium)
        /// 课表格子里的紧凑文字
        static let gridBlock = Font.system(size: 11, weight: .regular)
        /// 课表格子里的课程名
        static let gridBlockTitle = Font.system(size: 11, weight: .semibold)
        /// 课表左轴的课节号（11pt 半粗等宽数字，左轴最深最粗的一档）。
        static let gridAxisNumber = Font.system(size: 11, weight: .semibold).monospacedDigit()
        /// 课表左轴的上课 / 下课时刻（10pt 等宽数字，比课节号浅一档、小一档）；须单行显示。
        static let gridAxisTime = Font.system(size: 10, weight: .regular).monospacedDigit()
        /// 课表格子里的上课地点（8pt）；教师那一行共用这一档，但不缩字号。
        static let gridBlockLocation = Font.system(size: 8, weight: .regular)
    }

    /// 课表网格尺寸
    enum Grid {
        /// 左侧「课节号 + 上下课时刻」轴宽度（要放得下 `12` 与 `上午8:00` 这两行）
        static let axisWidth: CGFloat = 52
        /// 每一节的行高（与布局计算共用同一份数字）
        static let periodRowHeight = ScheduleGridLayout.Metrics.periodRowHeight
        /// 列间距
        static let columnSpacing: CGFloat = 2
        /// 一天最少的课节数（没有课时也要撑出网格）
        static let minimumPeriods = ScheduleGridLayout.Metrics.minimumPeriods
    }
}

/// 外观偏好 → SwiftUI 配色方案（`nil` 表示跟随系统）。
extension AppearancePreference {

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

// MARK: - 按钮与控件样式

/// 页面主操作：整行实心按钮。
struct PrimaryActionButtonStyle: ButtonStyle {

    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignTokens.Typography.sectionTitle)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                    .fill(Color.accentColor.opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.35))
            )
            .foregroundStyle(.white)
    }
}

/// 次级操作：整行描边按钮。
struct SecondaryActionButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignTokens.Typography.sectionTitle)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                    .fill(Color(uiColor: .tertiarySystemFill).opacity(configuration.isPressed ? 1.4 : 1))
            )
            .foregroundStyle(Color.accentColor)
    }
}

/// 快捷选项胶囊。
struct QuickChip: View {

    let title: String
    var systemImage: String?
    var isSelected: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage).font(.caption)
                }
                Text(title).font(DesignTokens.Typography.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(
                    isSelected
                        ? Color.accentColor.opacity(0.15)
                        : Color(uiColor: .tertiarySystemFill)
                )
            )
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

/// 表单里的「小标题 + 值」字段行。
struct FormFieldRow<Content: View>: View {

    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.secondary)

            content
        }
        .padding(.vertical, 2)
    }
}

/// 表单区块标题（如「截止日期　选填」）。
struct FormSectionTitle: View {

    let title: String
    var isOptional: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            if isOptional {
                Spacer(minLength: 6)
                Text("选填")
                    .font(DesignTokens.Typography.label)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
