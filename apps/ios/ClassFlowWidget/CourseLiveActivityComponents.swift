import Foundation
import SwiftUI

// MARK: - 配色

/// 实时活动固定使用黑底白字，不跟随系统明暗外观。
enum CourseActivityPalette {

    /// 背景 `#000000`
    static let background = Color.black
    /// 主要文字 `#FFFFFF`
    static let primary = Color.white
    /// 次要文字：白 62%
    static let secondary = Color.white.opacity(0.62)
    /// 更弱的辅助符号：白 40%
    static let tertiary = Color.white.opacity(0.4)
    /// 分割线：白 14%
    static let divider = Color.white.opacity(0.14)
    /// 进度条底槽：白 18%
    static let track = Color.white.opacity(0.18)
}

// MARK: - 排版

/// 实时活动的字号阶梯。
///
/// 四种形态共用同一套层级，只按可用空间收放，不另起一套样式：
/// 课程名 > 时刻 / 倒计时 > 正文 > 标签。
///
/// 展开态的字号由基准字号乘 `CourseActivityMetrics.expandedScale`（90%）得到：
/// 灵动岛展开后的外框由系统固定，内容收一档，四周才留得出空白。
enum CourseActivityType {

    /// 锁屏课程名：整张卡片唯一的大字号。
    static let lockTitle = Font.system(size: 17, weight: .semibold)
    /// 展开态课程名：受灵动岛上方区域高度限制，比锁屏小一号，再按展开态缩放收一档。
    static let expandedTitle = expanded(15, weight: .semibold)
    /// 紧凑态课程名。
    static let compactTitle = Font.system(size: 13, weight: .semibold)

    /// 剩余时间：锁屏。
    static let lockValue = Font.system(size: 15, weight: .semibold).monospacedDigit()
    /// 起止时刻：展开态。
    static let expandedValue = expanded(14, weight: .semibold, monospacedDigits: true)
    /// 倒计时：紧凑态。
    static let compactValue = Font.system(size: 13, weight: .semibold).monospacedDigit()
    /// 倒计时：最小化。区域只放得下几个字符。
    static let minimalValue = Font.system(size: 11, weight: .semibold).monospacedDigit()

    /// 正文：锁屏的时段与地点。
    static let meta = Font.system(size: 13)
    /// 正文里的时刻，等宽以免倒计时跳动时抖动。
    static let metaValue = Font.system(size: 13, weight: .medium).monospacedDigit()

    /// 次要正文：「剩余」以外的说明文字。
    static let caption = Font.system(size: 12)
    /// 下一节课的课程名。
    static let captionStrong = Font.system(size: 12, weight: .semibold)
    /// 下一节课的开始时刻。
    static let captionValue = Font.system(size: 12, weight: .medium).monospacedDigit()

    /// 小标签：「剩余」「下一节」。
    static let label = Font.system(size: 11, weight: .medium)

    /// 展开态的次要正文：地点、已下课的说明。
    static let expandedCaption = expanded(12)
    /// 展开态下一节课的课程名。
    static let expandedCaptionStrong = expanded(12, weight: .semibold)
    /// 展开态下一节课的开始时刻。
    static let expandedCaptionValue = expanded(12, weight: .medium, monospacedDigits: true)
    /// 展开态的小标签：「下一节」。
    static let expandedLabel = expanded(11, weight: .medium)

    /// 展开态字号：基准字号 × `expandedScale`；层级与锁屏完全相同，只是整体收一档。
    private static func expanded(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        monospacedDigits: Bool = false
    ) -> Font {
        let font = Font.system(size: size * CourseActivityMetrics.expandedScale, weight: weight)
        return monospacedDigits ? font.monospacedDigit() : font
    }
}

/// 实时活动的间距与尺寸。
///
/// 所有形态都从这里取值，避免每个状态各写一套 padding：
/// 同一类间距在锁屏与展开态里是同一个数字（展开态再乘 `expandedScale`）。
enum CourseActivityMetrics {

    // MARK: 展开态缩放

    /// 展开态的整体缩放：字号与间距一起按 90% 收，省下的空间留给四周的空白。
    static let expandedScale: CGFloat = 0.9
    /// 展开态在系统内边距之外再让出的左右留白。
    static let expandedInsetHorizontal: CGFloat = 6
    /// 展开态在系统内边距之外再让出的上下留白。
    static let expandedInsetVertical: CGFloat = 4

    // MARK: 锁屏

    /// 锁屏卡片的内边距（与系统实时活动卡片的常用留白一致）。
    static let lockPaddingH: CGFloat = 16
    static let lockPaddingV: CGFloat = 14
    /// 锁屏卡片里相邻两行之间的距离。
    static let lockGap: CGFloat = 6
    /// 分割线上下的额外留白。
    static let dividerGap: CGFloat = 2

    /// 展开态：进度条与下一节课之间的距离。
    static let expandedGap: CGFloat = 8 * expandedScale
    /// 展开态：上方课程名 / 地点两行之间。
    static let tightGap: CGFloat = 2 * expandedScale

    /// 同一行里各段文字之间的距离。
    static let rowGap: CGFloat = 6
    /// 展开态：同一行里各段文字之间的距离。
    static let expandedRowGap: CGFloat = rowGap * expandedScale
    /// 进度条高度（`ProgressView` 线性样式的默认高度）。
    ///
    /// 展开态不跟着缩放：这条粗细由系统的线性进度条自己决定，
    /// 只缩小外框反而会让进度条显得更粗。
    static let progressHeight: CGFloat = 4
    /// 分割线高度。
    static let hairline: CGFloat = 1
}

// MARK: - 展示数据

/// 实时活动界面需要的全部数据。
///
/// 从 `ActivityViewContext` 里取一次，之后界面只读这份值：
/// - 课程名 / 地点在这里统一去掉首尾空白，换行折成空格；
/// - 地点为空串时按「没有地点」处理（`nil`），各形态不必再各写一遍 `isEmpty` 判断。
///
/// 只依赖 Foundation / SwiftUI，不引用 ActivityKit：
/// `Scripts/live-activity-visual-check.swift` 用它把三种形态离屏渲染成 PNG 自检。
struct CourseActivityPresentation: Equatable {

    /// 下一节课；当天没有后续课程时为 `nil`。
    struct NextCourse: Equatable {

        /// 课程名称
        let name: String
        /// 开始时间
        let startTime: Date
        /// 上课地点；没有地点时为 `nil`，界面不画分隔点。
        let location: String?

        init(name: String, startTime: Date, location: String?) {
            self.name = CourseActivityPresentation.cleanedText(name)
            self.startTime = startTime
            self.location = CourseActivityPresentation.cleaned(location)
        }
    }

    /// 课程名称
    let courseName: String
    /// 开始时间
    let startTime: Date
    /// 结束时间
    let endTime: Date
    /// 上课地点；没有地点时为 `nil`。
    let location: String?
    /// 下一节课
    let nextCourse: NextCourse?
    /// 已过下课时刻（系统把活动标成过期）：不再画进度条与倒计时。
    let isStale: Bool

    init(
        courseName: String,
        startTime: Date,
        endTime: Date,
        location: String?,
        nextCourse: NextCourse?,
        isStale: Bool
    ) {
        self.courseName = Self.cleanedText(courseName)
        self.startTime = startTime
        self.endTime = endTime
        self.location = Self.cleaned(location)
        self.nextCourse = nextCourse
        self.isStale = isStale
    }

    /// 本节课的时间区间；结束时间不晚于开始时间时退化为零长度区间。
    var timeRange: ClosedRange<Date> {
        startTime...max(startTime, endTime)
    }

    /// 上课时段，如「08:00–09:40」。
    var timeRangeText: String {
        CourseActivityFormat.timeRange(start: startTime, end: endTime)
    }

    /// 去掉首尾空白；名称里的换行折成空格，避免在窄区域里多撑一行。
    static func cleanedText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 空串 / 只有空白的地点按「没有地点」处理。
    static func cleaned(_ text: String?) -> String? {
        guard let text else { return nil }
        let value = cleanedText(text)
        return value.isEmpty ? nil : value
    }
}

// MARK: - 文案

enum CourseActivityFormat {

    /// 上课 / 下课时刻，如「08:00」，跟随系统区域设置。
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// 上课时段，如「08:00–09:40」。
    static func timeRange(start: Date, end: Date) -> String {
        "\(time(start))–\(time(end))"
    }

    /// 下一节的开始时刻；不是今天时补上「明天」或月日，避免只看时刻分不清是哪天。
    static func nextCourseTime(
        _ date: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let clock = time(date)

        switch WidgetText.dayOffset(from: now, to: date, calendar: calendar) {
        case 0:
            return clock
        case 1:
            return "明天 \(clock)"
        default:
            let day = date.formatted(.dateTime.month().day().weekday(.abbreviated))
            return "\(day) \(clock)"
        }
    }
}

// MARK: - 离屏自检开关

/// 离屏自检专用开关：`ImageRenderer` 画不出 `ProgressView(timerInterval:)`，
/// 会渲染成系统的黄红占位图，既看不出进度也量不准高度。
///
/// 打开后改用一根静态胶囊近似进度条，`Scripts/live-activity-visual-check.swift`
/// 才能核对它的位置与粗细；真机 / 模拟器上始终走系统 `ProgressView`。
private struct CourseActivityStaticProgressKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {

    var courseActivityRendersStaticProgress: Bool {
        get { self[CourseActivityStaticProgressKey.self] }
        set { self[CourseActivityStaticProgressKey.self] = newValue }
    }
}

// MARK: - 共享片段

/// 距下课的倒计时，交给系统按秒自绘（App 不按秒刷新活动）。
///
/// 活动已过期时换成静态文案：`Text(timerInterval:)` 会一直停在 0:00。
struct CourseActivityCountdown: View {

    let presentation: CourseActivityPresentation
    let font: Font
    let showsHours: Bool
    var staleText: String = "已结束"

    var body: some View {
        Group {
            if presentation.isStale {
                Text(staleText)
            } else {
                Text(
                    timerInterval: presentation.timeRange,
                    countsDown: true,
                    showsHours: showsHours
                )
            }
        }
        .font(font)
        .foregroundStyle(CourseActivityPalette.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// 本节课的进度条。区间无效时退化为一条空轨道，避免 `ProgressView` 处理零长度区间。
struct CourseActivityProgress: View {

    let range: ClosedRange<Date>

    @Environment(\.courseActivityRendersStaticProgress) private var rendersStatically

    var body: some View {
        if range.upperBound > range.lowerBound {
            if rendersStatically {
                CourseActivityStaticProgressBar(fraction: progressFraction)
            } else {
                ProgressView(timerInterval: range, countsDown: false)
                    .progressViewStyle(.linear)
                    .tint(CourseActivityPalette.primary)
            }
        } else {
            Capsule()
                .fill(CourseActivityPalette.track)
                .frame(height: CourseActivityMetrics.progressHeight)
        }
    }

    /// 此刻走过的比例；只给离屏自检用。
    private var progressFraction: Double {
        let total = range.upperBound.timeIntervalSince(range.lowerBound)
        guard total > 0 else { return 0 }
        let elapsed = Date().timeIntervalSince(range.lowerBound)
        return min(max(elapsed / total, 0), 1)
    }
}

/// `CourseActivityProgress` 的静态替身：底槽 + 已走过的部分，与系统线性进度条同高。
private struct CourseActivityStaticProgressBar: View {

    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(CourseActivityPalette.track)

                Capsule()
                    .fill(CourseActivityPalette.primary)
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: CourseActivityMetrics.progressHeight)
    }
}

/// 下一节课那一行的字号与行距。
///
/// 这一行锁屏与灵动岛展开态共用，字号阶梯只有一份：锁屏用基准值，
/// 展开态按 `CourseActivityMetrics.expandedScale` 收一档。
enum CourseActivityNextCourseStyle {

    case lockScreen
    case expanded

    var label: Font {
        switch self {
        case .lockScreen: CourseActivityType.label
        case .expanded: CourseActivityType.expandedLabel
        }
    }

    var name: Font {
        switch self {
        case .lockScreen: CourseActivityType.captionStrong
        case .expanded: CourseActivityType.expandedCaptionStrong
        }
    }

    var meta: Font {
        switch self {
        case .lockScreen: CourseActivityType.caption
        case .expanded: CourseActivityType.expandedCaption
        }
    }

    var time: Font {
        switch self {
        case .lockScreen: CourseActivityType.captionValue
        case .expanded: CourseActivityType.expandedCaptionValue
        }
    }

    var rowGap: CGFloat {
        switch self {
        case .lockScreen: CourseActivityMetrics.rowGap
        case .expanded: CourseActivityMetrics.expandedRowGap
        }
    }
}

/// 下一节课：左侧标签，中间课程名与地点，右侧开始时刻；没有后续课程时只留一行说明。
///
/// 长课名先缩放再截断，开始时刻固定在最右侧（`.fixedSize()`），
/// 这样课名再长也不会把「几点上课」挤掉；地点缺失时连分隔点一起省掉。
struct CourseActivityNextCourseRow: View {

    let nextCourse: CourseActivityPresentation.NextCourse?
    var style: CourseActivityNextCourseStyle = .lockScreen

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: style.rowGap) {
            if let nextCourse {
                Text("下一节")
                    .font(style.label)
                    .foregroundStyle(CourseActivityPalette.secondary)
                    .fixedSize()

                Text(nextCourse.name)
                    .font(style.name)
                    .foregroundStyle(CourseActivityPalette.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .truncationMode(.tail)

                if let location = nextCourse.location {
                    Text("·")
                        .font(style.meta)
                        .foregroundStyle(CourseActivityPalette.tertiary)
                        .fixedSize()

                    Text(location)
                        .font(style.meta)
                        .foregroundStyle(CourseActivityPalette.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                Text(CourseActivityFormat.nextCourseTime(nextCourse.startTime))
                    .font(style.time)
                    .foregroundStyle(CourseActivityPalette.secondary)
                    .lineLimit(1)
                    .fixedSize()
            } else {
                Text("今天没有更多课程")
                    .font(style.meta)
                    .foregroundStyle(CourseActivityPalette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - 灵动岛 · 紧凑 / 最小化

/// 紧凑态左侧：课程名。区域由系统分配且很窄，长课名先缩放再截断，不换行。
struct CourseActivityCompactLeadingView: View {

    let presentation: CourseActivityPresentation

    var body: some View {
        Text(presentation.courseName)
            .font(CourseActivityType.compactTitle)
            .foregroundStyle(CourseActivityPalette.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .truncationMode(.tail)
    }
}

/// 紧凑态右侧：距下课的倒计时。
struct CourseActivityCompactTrailingView: View {

    let presentation: CourseActivityPresentation

    var body: some View {
        CourseActivityCountdown(
            presentation: presentation,
            font: CourseActivityType.compactValue,
            showsHours: false
        )
    }
}

/// 最小化形态：只留剩余时间；已下课时显示「已结束」而不是一直停在 0:00。
struct CourseActivityMinimalView: View {

    let presentation: CourseActivityPresentation

    var body: some View {
        CourseActivityCountdown(
            presentation: presentation,
            font: CourseActivityType.minimalValue,
            showsHours: false
        )
    }
}

// MARK: - 灵动岛 · 展开

// 展开态的三种区域都按 `CourseActivityMetrics.expandedScale`（90%）收一档字号与间距，
// 额外留白由 `CourseLiveActivity` 给每个区域加的内边距提供。

/// 展开态左侧：课程名。上方区域窄而矮，最多两行，更长的课名先缩放再截断。
struct CourseActivityExpandedLeadingView: View {

    let presentation: CourseActivityPresentation

    var body: some View {
        Text(presentation.courseName)
            .font(CourseActivityType.expandedTitle)
            .foregroundStyle(CourseActivityPalette.primary)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .truncationMode(.tail)
    }
}

/// 展开态右侧：起止时刻，下面一行是上课地点；地点缺失时只剩时刻。
struct CourseActivityExpandedTrailingView: View {

    let presentation: CourseActivityPresentation

    var body: some View {
        VStack(alignment: .trailing, spacing: CourseActivityMetrics.tightGap) {
            Text(presentation.timeRangeText)
                .font(CourseActivityType.expandedValue)
                .foregroundStyle(CourseActivityPalette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if let location = presentation.location {
                Text(location)
                    .font(CourseActivityType.expandedCaption)
                    .foregroundStyle(CourseActivityPalette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .multilineTextAlignment(.trailing)
    }
}

/// 展开态底部：本节课进度与下一节课。活动过期（已下课）时不再画进度条。
struct CourseActivityExpandedBottomView: View {

    let presentation: CourseActivityPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: CourseActivityMetrics.expandedGap) {
            if presentation.isStale {
                Text("本节课已结束")
                    .font(CourseActivityType.expandedCaption)
                    .foregroundStyle(CourseActivityPalette.secondary)
            } else {
                CourseActivityProgress(range: presentation.timeRange)
            }

            CourseActivityNextCourseRow(nextCourse: presentation.nextCourse, style: .expanded)
        }
        .padding(.top, CourseActivityMetrics.tightGap)
    }
}

// MARK: - 锁屏

/// 锁屏卡片：课程名与剩余时间为主，其次起止时刻与上课地点，最后是进度与下一节课。
///
/// 背景与系统操作按钮的前景色由 `CourseLiveActivity` 里的 `activityBackgroundTint` /
/// `activitySystemActionForegroundColor` 统一指定，这里只负责排版。
struct CourseActivityLockScreenContent: View {

    let presentation: CourseActivityPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: CourseActivityMetrics.lockGap) {
            header
            scheduleLine

            if !presentation.isStale {
                CourseActivityProgress(range: presentation.timeRange)
            }

            Rectangle()
                .fill(CourseActivityPalette.divider)
                .frame(height: CourseActivityMetrics.hairline)
                .padding(.vertical, CourseActivityMetrics.dividerGap)

            CourseActivityNextCourseRow(nextCourse: presentation.nextCourse)
        }
        .padding(.horizontal, CourseActivityMetrics.lockPaddingH)
        .padding(.vertical, CourseActivityMetrics.lockPaddingV)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// 第一行：课程名在左，剩余时间固定在右侧。
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(presentation.courseName)
                .font(CourseActivityType.lockTitle)
                .foregroundStyle(CourseActivityPalette.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            if presentation.isStale {
                Text("已结束")
                    .font(CourseActivityType.label)
                    .foregroundStyle(CourseActivityPalette.secondary)
                    .fixedSize()
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("剩余")
                        .font(CourseActivityType.label)
                        .foregroundStyle(CourseActivityPalette.secondary)
                        .fixedSize()

                    CourseActivityCountdown(
                        presentation: presentation,
                        font: CourseActivityType.lockValue,
                        showsHours: true
                    )
                }
                .fixedSize()
            }
        }
    }

    /// 第二行：上课时段与地点；没有地点时只剩时段，不留孤零零的分隔点。
    private var scheduleLine: some View {
        HStack(spacing: CourseActivityMetrics.rowGap) {
            Text(presentation.timeRangeText)
                .font(CourseActivityType.metaValue)
                .foregroundStyle(CourseActivityPalette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .fixedSize()

            if let location = presentation.location {
                Text("·")
                    .font(CourseActivityType.meta)
                    .foregroundStyle(CourseActivityPalette.tertiary)
                    .fixedSize()

                Text(location)
                    .font(CourseActivityType.meta)
                    .foregroundStyle(CourseActivityPalette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
    }
}
