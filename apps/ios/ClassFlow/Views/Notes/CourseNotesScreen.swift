import SwiftUI

/// 某门课程的笔记列表：导航标题为课程名，行内显示时间、标题与摘要。
struct CourseNotesScreen: View {

    @Environment(AppStore.self) private var store

    let courseId: UUID

    @State private var editingMemo: Memo?
    @State private var showsNewNote = false

    var body: some View {
        List {
            if let course = store.course(id: courseId) {
                Section {
                    ForEach(memos) { memo in
                        noteRow(memo)
                    }
                } header: {
                    Text("\(memos.count)篇笔记")
                } footer: {
                    if memos.isEmpty {
                        Text("还没有为《\(course.name)》记录任何笔记。")
                    }
                }

                Section {
                    Button("新建笔记", systemImage: "plus") { showsNewNote = true }
                }
            } else {
                Section {
                    Text("课程不存在").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(store.course(id: courseId)?.name ?? "课程笔记")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsNewNote) {
            MemoEditView(courseId: courseId)
        }
        .sheet(item: $editingMemo) { memo in
            MemoEditView(courseId: courseId, memo: memo)
        }
    }
}

extension CourseNotesScreen {

    private var memos: [Memo] {
        store.memos(forCourseId: courseId)
    }

    @ViewBuilder
    private func noteRow(_ memo: Memo) -> some View {
        Button {
            editingMemo = memo
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(memo.dateTimeText())
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondary)

                Text(memo.displayTitle)
                    .font(DesignTokens.Typography.sectionTitle)
                    .foregroundStyle(.primary)

                let preview = memo.bodyPreview
                if !preview.isEmpty {
                    Text(preview)
                        .font(DesignTokens.Typography.secondary)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 2)
        }
        .swipeActions(edge: .trailing) {
            Button("删除", role: .destructive) {
                try? store.deleteMemo(id: memo.id)
            }
        }
    }
}

#Preview("课程笔记 · 有内容") {
    let seed = PreviewSupport.seed

    NavigationStack {
        CourseNotesScreen(courseId: seed.math.id)
    }
    .environment(seed.store)
}

#Preview("课程笔记 · 空") {
    let seed = PreviewSupport.seed

    NavigationStack {
        CourseNotesScreen(courseId: seed.physicalEducation.id)
    }
    .environment(seed.store)
}
