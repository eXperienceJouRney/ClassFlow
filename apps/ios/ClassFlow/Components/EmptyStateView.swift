import SwiftUI

struct EmptyStateView: View {

    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

#Preview("带操作按钮") {
    EmptyStateView(
        icon: "graduationcap",
        title: "还没有学期",
        message: "先创建一个学期并设置课节时间，然后就可以添加课程了。",
        actionTitle: "创建学期"
    ) {}
}

#Preview("纯说明") {
    EmptyStateView(
        icon: "calendar.badge.exclamationmark",
        title: "第 17 周没有课",
        message: "检查一下课程的上课周次设置。"
    )
}
