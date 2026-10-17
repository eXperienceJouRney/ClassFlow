import SwiftUI

/// 课程详情底部面板：课程信息、待办与笔记预览，可进入编辑。
struct CourseDetailView: View {

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let courseId: UUID

    @State private var showsNewTask = false
    @State private var showsNewMemo = false
    @State private var editingMemo: Memo?
    @State private var showsEdit = false
    @State private var showsDeletion = false

    /// 每组默认展示几条，多出来的走「查看全部」。
    private let previewLimit = 2

    var body: some View {
        NavigationStack {
            Group {
                if let course = store.course(id: courseId) {
                    content(course)
                } else {
                    EmptyStateView(
                        icon: "questionmark.folder",
                        title: "课程不存在",
                        message: "它可能已经被删除了。"
                    )
                }
            }
            .navigationTitle(store.course(id: courseId)?.name ?? "课程详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
            }
            .navigationDestination(for: CourseNotesRoute.self) { route in
                CourseNotesScreen(courseId: route.courseId)
            }
            .navigationDestination(for: CourseTasksRoute.self) { route in
                CourseTasksScreen(courseId: route.courseId)
            }
            .sheet(isPresented: $showsEdit) {
                if let course = store.course(id: courseId) {
                    CourseEditView(semesterId: course.semesterId, course: course)
                }
            }
            .sheet(isPresented: $showsDeletion) {
                CourseDeletionView(courseId: courseId) { dismiss() }
            }
            .sheet(isPresented: $showsNewTask) {
                TaskEditView(task: nil, presetCourseId: courseId)
            }
            .sheet(isPresented: $showsNewMemo) {
                MemoEditView(courseId: courseId)
            }
            .sheet(item: $editingMemo) { memo in
                MemoEditView(courseId: courseId, memo: memo)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// 面板内跳转的路由值。
struct CourseNotesRoute: Hashable {
    let courseId: UUID
}

struct CourseTasksRoute: Hashable {
    let courseId: UUID
}

extension CourseDetailView {

    private func content(_ course: Course) -> some View {
        let tasks = store.tasks(forCourseId: course.id)
        let memos = store.memos(forCourseId: course.id)

        return ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                header(course)
                quickActions

                if !tasks.isEmpty {
                    taskSection(tasks)
                }

                if !memos.isEmpty {
                    memoSection(memos)
                }

                editButton
                deleteButton
            }
            .padding(DesignTokens.Spacing.page)
        }
    }

    // MARK: - 头部

    @ViewBuilder
    private func header(_ course: Course) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(course.name)
                .font(DesignTokens.Typography.pageTitle)

            if let detail = scheduleDetailText(course) {
                Text(detail)
                    .font(DesignTokens.Typography.secondary)
                    .foregroundStyle(.secondary)
            }

            if let teacher = course.teacher, !teacher.isBlank {
                Text(teacher)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// 首条安排的时间与地点文案；无安排时返回 nil，不得推测。
    private func scheduleDetailText(_ course: Course) -> String? {
        let entries = store.scheduleEntries(for: course.id)
        guard let first = entries.first else { return nil }

        var parts = [first.time.displayText]
        if let location = first.location ?? course.location, !location.isBlank {
            parts.append("教室 \(location)")
        }
        return parts.joined(separator: "・")
    }

    // MARK: - 快捷操作

    @ViewBuilder
    private var quickActions: some View {
        HStack(spacing: DesignTokens.Spacing.item) {
            Button {
                showsNewMemo = true
            } label: {
                Text("+ 添加笔记")
            }
            .buttonStyle(SecondaryActionButtonStyle())

            Button {
                showsNewTask = true
            } label: {
                Text("＋添加待办")
            }
            .buttonStyle(SecondaryActionButtonStyle())
        }
    }

    // MARK: - 分组

    @ViewBuilder
    private func taskSection(_ tasks: [CourseTask]) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.tight) {
            sectionTitle("待办")

            ForEach(tasks.prefix(previewLimit)) { task in
                HStack(spacing: 8) {
                    Image(systemName: task.status.isTerminal ? "checkmark.circle.fill" : "circle")
                        .font(.footnote)
                        .foregroundStyle(task.status.isTerminal ? Color.accentColor : Color.secondary)

                    Text(task.title)
                        .font(DesignTokens.Typography.rowTitle)
                        .strikethrough(task.status.isTerminal)
                        .foregroundStyle(task.status.isTerminal ? Color.secondary : Color.primary)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
            }

            if tasks.count > previewLimit {
                NavigationLink(value: CourseTasksRoute(courseId: courseId)) {
                    Text("查看全部 \(tasks.count) 项待办")
                        .font(DesignTokens.Typography.secondary)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func memoSection(_ memos: [Memo]) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.tight) {
            sectionTitle("笔记")

            ForEach(memos.prefix(previewLimit)) { memo in
                Button {
                    editingMemo = memo
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "note.text")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(memo.displayTitle)
                                .font(DesignTokens.Typography.rowTitle)
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            if !memo.bodyPreview.isEmpty {
                                Text(memo.bodyPreview)
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if memos.count > previewLimit {
                NavigationLink(value: CourseNotesRoute(courseId: courseId)) {
                    Text("查看全部 \(memos.count) 篇笔记")
                        .font(DesignTokens.Typography.secondary)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.Typography.sectionTitle)
    }

    // MARK: - 底部

    @ViewBuilder
    private var editButton: some View {
        Button {
            showsEdit = true
        } label: {
            Text("编辑课程")
        }
        .buttonStyle(PrimaryActionButtonStyle())
    }

    @ViewBuilder
    private var deleteButton: some View {
        Button("删除课程", systemImage: "trash", role: .destructive) {
            showsDeletion = true
        }
        .font(DesignTokens.Typography.caption)
        .frame(maxWidth: .infinity)
    }
}

#Preview("课程详情 · 有任务和笔记") {
    let seed = PreviewSupport.seed

    Color(uiColor: .systemGroupedBackground)
        .sheet(isPresented: .constant(true)) {
            CourseDetailView(courseId: seed.math.id)
        }
        .environment(seed.store)
}

#Preview("课程详情 · 只有安排") {
    let seed = PreviewSupport.seed

    Color(uiColor: .systemGroupedBackground)
        .sheet(isPresented: .constant(true)) {
            CourseDetailView(courseId: seed.linearAlgebra.id)
        }
        .environment(seed.store)
}

#Preview("课程详情 · 课程已不存在") {
    Color(uiColor: .systemGroupedBackground)
        .sheet(isPresented: .constant(true)) {
            CourseDetailView(courseId: UUID())
        }
        .environment(PreviewSupport.store)
}
