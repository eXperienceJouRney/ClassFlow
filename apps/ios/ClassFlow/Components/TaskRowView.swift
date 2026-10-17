import SwiftUI

/// 待办行：左侧状态圆点只切换完成状态，右侧标题区域进入编辑。
struct TaskRowView: View {

    @Environment(AppStore.self) private var store

    let task: CourseTask
    var showsCourse: Bool = true
    /// 点标题区域的动作（通常是打开编辑）；为 nil 时标题区域不可点。
    var onSelect: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            completionButton

            if let onSelect {
                Button(action: onSelect) {
                    contentBlock
                }
                .buttonStyle(.plain)
            } else {
                contentBlock
            }
        }
        .padding(.vertical, 2)
    }
}

extension TaskRowView {

    /// 完成 / 取消完成：两个分组视图共用同一按钮与同一条状态转换路径。
    private var completionButton: some View {
        Button {
            toggleCompletion()
        } label: {
            Image(systemName: statusIcon)
                .font(.title3)
                .foregroundStyle(statusColor)
                .frame(width: 32, height: 32, alignment: .topLeading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(task.status.isTerminal ? "标记为未完成" : "标记为已完成")
    }

    private var contentBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(task.title)
                .font(DesignTokens.Typography.rowTitle)
                .strikethrough(task.status.isTerminal)
                .foregroundStyle(task.status.isTerminal ? Color.secondary : Color.primary)

            Text(subtitleText)
                .font(DesignTokens.Typography.secondary)
                .strikethrough(task.status.isTerminal)
                .foregroundStyle(subtitleColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var dueText: TaskDueText {
        task.dueText(format: store.preferences.timeFormat)
    }

    /// 按时间分组的行内文案是「课程 + 时间」，按课程分组只用相对时间。
    private var subtitleText: String {
        showsCourse ? "\(courseName)・\(dueText.short)" : dueText.relative
    }

    private var subtitleColor: Color {
        if task.status.isTerminal { return .secondary }
        return task.isOverdue() ? .red : .secondary
    }

    private var statusIcon: String {
        switch task.status {
        case .todo: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .completed: "checkmark.circle.fill"
        case .cancelled: "xmark.circle"
        }
    }

    private var statusColor: Color {
        switch task.status {
        case .todo: .secondary
        case .inProgress: .accentColor
        case .completed: .green
        case .cancelled: .secondary
        }
    }

    private var courseName: String {
        guard let courseId = task.courseId, let course = store.course(id: courseId) else {
            return "未关联课程"
        }
        return course.name
    }

    private func toggleCompletion() {
        do {
            if task.status.isTerminal {
                try store.reopenTask(id: task.id)
            } else {
                try store.setTaskStatus(id: task.id, to: .completed)
            }
        } catch {
            // 待办/进行中 → 已完成 与 终态 → 待办 都是合法转换，实际不会失败
        }
    }
}

#Preview("任务行 · 各种状态") {
    let seed = PreviewSupport.seed

    List {
        TaskRowView(task: seed.task)
        TaskRowView(task: seed.overdueTask)
        TaskRowView(task: seed.undatedTask)
        TaskRowView(task: seed.completedTask)
        TaskRowView(task: seed.standaloneTask)
        TaskRowView(task: seed.task, showsCourse: false)
    }
    .environment(seed.store)
}
