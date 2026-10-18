import ActivityKit
import SwiftUI
import WidgetKit

/// 课程实时活动：锁屏卡片，以及 Dynamic Island 的展开 / 紧凑 / 最小化三种形态。
///
/// 版面只用文字、进度条与分割线，不使用课程图标；配色固定为黑底白字。
/// 数据来自共享的 `CourseActivityAttributes`；活动由主 App 的
/// `CourseLiveActivityController` 启动 / 结束，这里只负责展示。
///
/// 具体排版在 `CourseLiveActivityComponents.swift`：那层只认
/// `CourseActivityPresentation`，不依赖 ActivityKit，方便离屏渲染自检。
struct CourseLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CourseActivityAttributes.self) { context in
            CourseActivityLockScreenView(context: context)
                .activityBackgroundTint(CourseActivityPalette.background)
                .activitySystemActionForegroundColor(CourseActivityPalette.primary)
        } dynamicIsland: { context in
            let presentation = CourseActivityPresentation(context: context)

            return DynamicIsland {
                // 内容按 `CourseActivityMetrics.expandedScale`（90%）排版，
                // 再给每个区域让出一点额外内边距：四周留白更宽，文字不贴边。
                DynamicIslandExpandedRegion(.leading) {
                    CourseActivityExpandedLeadingView(presentation: presentation)
                        .padding(.leading, CourseActivityMetrics.expandedInsetHorizontal)
                        .padding(.top, CourseActivityMetrics.expandedInsetVertical)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    CourseActivityExpandedTrailingView(presentation: presentation)
                        .padding(.trailing, CourseActivityMetrics.expandedInsetHorizontal)
                        .padding(.top, CourseActivityMetrics.expandedInsetVertical)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    CourseActivityExpandedBottomView(presentation: presentation)
                        .padding(.horizontal, CourseActivityMetrics.expandedInsetHorizontal)
                        .padding(.bottom, CourseActivityMetrics.expandedInsetVertical)
                }
            } compactLeading: {
                CourseActivityCompactLeadingView(presentation: presentation)
            } compactTrailing: {
                CourseActivityCompactTrailingView(presentation: presentation)
            } minimal: {
                CourseActivityMinimalView(presentation: presentation)
            }
        }
    }
}

// MARK: - ActivityKit → 展示数据

extension CourseActivityPresentation {

    /// 从 ActivityKit 的上下文取一次数据；界面层不再碰 `ActivityViewContext`。
    init(context: ActivityViewContext<CourseActivityAttributes>) {
        self.init(
            courseName: context.attributes.courseName,
            startTime: context.attributes.startTime,
            endTime: context.attributes.endTime,
            location: context.attributes.location,
            nextCourse: context.state.nextCourse.map {
                NextCourse(name: $0.name, startTime: $0.startTime, location: $0.location)
            },
            isStale: context.isStale
        )
    }
}

// MARK: - 预览

#if DEBUG
extension CourseActivityAttributes {

    /// 预览用的一节课，已经开始 18 分钟。
    static var preview: CourseActivityAttributes {
        CourseActivityAttributes(
            courseName: "数据结构与算法",
            startTime: .now.addingTimeInterval(-18 * 60),
            endTime: .now.addingTimeInterval(72 * 60),
            location: "教三-201"
        )
    }

    /// 长课名、没有地点：检查窄区域里的缩放与省略。
    static var previewLong: CourseActivityAttributes {
        CourseActivityAttributes(
            courseName: "马克思主义基本原理概论（2026 秋季学期）",
            startTime: .now.addingTimeInterval(-18 * 60),
            endTime: .now.addingTimeInterval(72 * 60),
            location: ""
        )
    }
}

extension CourseActivityAttributes.ContentState {

    /// 预览用的下一节课。
    static var preview: CourseActivityAttributes.ContentState {
        CourseActivityAttributes.ContentState(
            nextCourse: CourseActivityAttributes.NextCourse(
                name: "高等数学（A）",
                startTime: .now.addingTimeInterval(102 * 60),
                location: "教一-105"
            )
        )
    }

    /// 预览用的「今天没有更多课程」。
    static var previewWithoutNext: CourseActivityAttributes.ContentState {
        CourseActivityAttributes.ContentState(nextCourse: nil)
    }
}

#Preview("锁屏", as: .content, using: CourseActivityAttributes.preview) {
    CourseLiveActivity()
} contentStates: {
    CourseActivityAttributes.ContentState.preview
}

#Preview("锁屏 · 长课名 / 无地点", as: .content, using: CourseActivityAttributes.previewLong) {
    CourseLiveActivity()
} contentStates: {
    CourseActivityAttributes.ContentState.previewWithoutNext
}

#Preview("灵动岛 · 展开", as: .dynamicIsland(.expanded), using: CourseActivityAttributes.preview) {
    CourseLiveActivity()
} contentStates: {
    CourseActivityAttributes.ContentState.preview
}

#Preview("灵动岛 · 展开 · 长课名 / 无地点", as: .dynamicIsland(.expanded), using: CourseActivityAttributes.previewLong) {
    CourseLiveActivity()
} contentStates: {
    CourseActivityAttributes.ContentState.previewWithoutNext
}

#Preview("灵动岛 · 紧凑", as: .dynamicIsland(.compact), using: CourseActivityAttributes.preview) {
    CourseLiveActivity()
} contentStates: {
    CourseActivityAttributes.ContentState.preview
}

#Preview("灵动岛 · 紧凑 · 长课名", as: .dynamicIsland(.compact), using: CourseActivityAttributes.previewLong) {
    CourseLiveActivity()
} contentStates: {
    CourseActivityAttributes.ContentState.preview
}

#Preview("灵动岛 · 最小化", as: .dynamicIsland(.minimal), using: CourseActivityAttributes.preview) {
    CourseLiveActivity()
} contentStates: {
    CourseActivityAttributes.ContentState.preview
}
#endif
