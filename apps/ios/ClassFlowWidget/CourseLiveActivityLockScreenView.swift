import ActivityKit
import SwiftUI
import WidgetKit

/// 锁屏展示：把 ActivityKit 的上下文转成展示数据，排版交给 `CourseActivityLockScreenContent`。
///
/// 背景与系统操作按钮的前景色由 `CourseLiveActivity` 里的 `activityBackgroundTint` /
/// `activitySystemActionForegroundColor` 统一指定，这里只做上下文适配。
struct CourseActivityLockScreenView: View {

    let context: ActivityViewContext<CourseActivityAttributes>

    var body: some View {
        CourseActivityLockScreenContent(presentation: CourseActivityPresentation(context: context))
    }
}
