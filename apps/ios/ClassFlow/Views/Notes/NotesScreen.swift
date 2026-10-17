import SwiftUI

/// 笔记 Tab：每门课一组，点课名进入该课程笔记列表，点某条笔记直接编辑。
struct NotesScreen: View {

    @Environment(AppStore.self) private var store
    /// 桌面组件深链路由；未注入时为 nil。
    @Environment(AppRouter.self) private var router: AppRouter?

    @State private var editingMemo: Memo?
    @State private var showsNewNote = false
    /// 非 nil 时覆盖新建笔记的默认课程。
    @State private var newNoteCourseOverride: UUID?

    var body: some View {
        NavigationStack {
            List {
                if groups.isEmpty {
                    Section {
                        Text("还没有笔记")
                            .font(DesignTokens.Typography.rowTitle)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 80)
                            .listRowBackground(Color.clear)
                    }
                } else {
                    ForEach(groups) { group in
                        Section {
                            courseHeader(group)

                            ForEach(group.previewMemos) { memo in
                                noteRow(memo)
                            }

                            if group.memos.count > group.previewMemos.count {
                                NavigationLink(value: group.course) {
                                    Text("查看全部 \(group.memos.count) 篇笔记")
                                        .font(DesignTokens.Typography.secondary)
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("笔记")
            .navigationDestination(for: Course.self) { course in
                CourseNotesScreen(courseId: course.id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("新建笔记", systemImage: "square.and.pencil") { showsNewNote = true }
                        .disabled(newNoteCourseId == nil)
                }
            }
            .sheet(isPresented: $showsNewNote) {
                if let courseId = newNoteCourseId {
                    MemoEditView(courseId: courseId)
                }
            }
            .sheet(item: $editingMemo) { memo in
                MemoEditView(courseId: memo.courseId, memo: memo)
            }
        }
    }
}

extension NotesScreen {

    /// 课程 + 该课程的笔记，按课程名排序。
    struct CourseNotesGroup: Identifiable {
        let course: Course
        let memos: [Memo]

        var id: UUID { course.id }

        /// 每组最多展示 3 条。
        var previewMemos: [Memo] { Array(memos.prefix(3)) }
    }

    var groups: [CourseNotesGroup] {
        store.data.courses
            .sorted { $0.name < $1.name }
            .compactMap { course in
                let memos = store.memos(forCourseId: course.id)
                guard !memos.isEmpty else { return nil }
                return CourseNotesGroup(course: course, memos: memos)
            }
    }

    /// 新建笔记时默认落在哪门课：当前学期第一门课，否则全部课程里的第一门。
    private var newNoteCourseId: UUID? {
        if let semesterId = store.currentSemester?.id,
           let course = store.courses(in: semesterId).first {
            return course.id
        }
        return store.data.courses.sorted { $0.name < $1.name }.first?.id
    }

    @ViewBuilder
    private func courseHeader(_ group: CourseNotesGroup) -> some View {
        NavigationLink(value: group.course) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.course.name)
                    .font(DesignTokens.Typography.sectionTitle)
                    .foregroundStyle(.primary)

                Text("\(group.memos.count)篇笔记")
                    .font(DesignTokens.Typography.secondary)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
            .padding(.bottom, 2)
        }
    }

    @ViewBuilder
    private func noteRow(_ memo: Memo) -> some View {
        Button {
            editingMemo = memo
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(memo.displayTitle)
                    .font(DesignTokens.Typography.rowTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(memo.dateText())
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview("笔记 · 有内容") {
    NotesScreen()
        .environment(PreviewSupport.store)
}

#Preview("笔记 · 还没有笔记") {
    NotesScreen()
        .environment(PreviewSupport.emptyStore)
}
