import AppIntents
import SwiftUI
import WidgetKit

// MARK: - 组件 04：课程待办 · 中尺寸

/// 待办列表（中尺寸）：按到期时刻排序，圆圈勾选写回完成状态，标题打开待办详情。
struct TodoEntryView: View {

    @Environment(\.colorScheme) private var colorScheme

    let entry: ClassFlowWidgetEntry

    private var style: WidgetStyle { .of(colorScheme) }
    /// 中尺寸排得下三行
    private let maximumRows = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetSectionHeader(
                title: "即将到期",
                trailing: "\(entry.snapshot.openTodoCount) 项待办",
                style: style
            )

            if rows.isEmpty {
                Spacer(minLength: 6)

                WidgetEmptyState(
                    title: "暂无待办",
                    message: "打开 ClassFlow 添加一条待办",
                    style: style,
                    titleSize: 14
                )

                Spacer(minLength: 6)
            } else {
                Spacer(minLength: 8)

                VStack(alignment: .leading, spacing: 9) {
                    ForEach(rows, id: \.id) { item in
                        row(item)
                    }
                }

                Spacer(minLength: 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(WidgetDeepLink.url(.tasks))
    }
}

extension TodoEntryView {

    private var rows: [WidgetTodoItem] {
        Array(entry.snapshot.todos.prefix(maximumRows))
    }

    private func row(_ item: WidgetTodoItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle(isOn: item.isCompleted, intent: ToggleTaskDoneIntent(taskId: item.id)) {
                EmptyView()
            }
            .toggleStyle(WidgetCheckToggleStyle(style: style))

            WidgetLink(url: taskURL(item)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 14, weight: item.isCompleted ? .regular : .medium))
                        .foregroundStyle(item.isCompleted ? style.secondaryText : style.primaryText)
                        .strikethrough(item.isCompleted, color: style.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(item.auxiliaryText(now: entry.date))
                        .font(.system(size: 11))
                        .foregroundStyle(style.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .invalidatableContent()
    }

    private func taskURL(_ item: WidgetTodoItem) -> URL {
        WidgetDeepLink.url(.task(item.id)) ?? fallbackURL
    }

    private var fallbackURL: URL {
        WidgetDeepLink.url(.tasks) ?? URL(string: "classflow://tasks")!
    }
}

// MARK: - 组件 05：快速笔记 · 小尺寸

/// 最近编辑的课程笔记卡片（小尺寸）：卡片打开该笔记，底部按钮新增笔记。
struct QuickMemoEntryView: View {

    @Environment(\.colorScheme) private var colorScheme

    let entry: ClassFlowWidgetEntry

    private var style: WidgetStyle { .of(colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("课程笔记")
                .font(.system(size: 11))
                .foregroundStyle(style.secondaryText)
                .lineLimit(1)

            Spacer(minLength: 6)

            if let memo = entry.snapshot.latestMemo {
                Text(memo.courseName)
                    .font(.system(size: 12))
                    .foregroundStyle(style.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(memo.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(style.primaryText)
                    .widgetTextFit(lines: 2, minimumScale: 0.7)
                    .padding(.top, 2)

                Text(WidgetText.relativeEditText(from: memo.updatedAt, now: entry.date))
                    .font(.system(size: 10))
                    .foregroundStyle(style.secondaryText)
                    .lineLimit(1)
                    .padding(.top, 3)
            } else {
                Text("还没有笔记")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(style.primaryText)
                    .widgetTextFit(lines: 2, minimumScale: 0.8)

                Text("把课堂要点记在这里")
                    .font(.system(size: 10))
                    .foregroundStyle(style.secondaryText)
                    .padding(.top, 3)
            }

            Spacer(minLength: 6)

            addNoteButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(memoURL)
    }
}

extension QuickMemoEntryView {

    /// 有笔记就打开它，没有就落到「新增笔记」。
    private var memoURL: URL {
        guard let memo = entry.snapshot.latestMemo else { return newMemoURL }
        return WidgetDeepLink.url(.memo(memo.id)) ?? newMemoURL
    }

    private var newMemoURL: URL {
        WidgetDeepLink.url(.newMemo(courseId: entry.snapshot.latestMemo?.courseId))
            ?? URL(string: "classflow://memo/new")!
    }

    private var addNoteButton: some View {
        Button(intent: OpenWidgetLinkIntent(destination: .newMemo(courseId: entry.snapshot.latestMemo?.courseId))) {
            Text("+ 添加笔记")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(WidgetPalette.cardDark)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 预览

#Preview("04 课程待办 · 中尺寸画布") {
    TodoEntryView(entry: .placeholder())
        .frame(width: 338, height: 158)
        .containerBackground(for: .widget) { WidgetPalette.cardLight }
}

#Preview("05 快速笔记 · 小尺寸画布") {
    QuickMemoEntryView(entry: .placeholder())
        .frame(width: 158, height: 158)
        .containerBackground(for: .widget) { WidgetPalette.cardLight }
}
