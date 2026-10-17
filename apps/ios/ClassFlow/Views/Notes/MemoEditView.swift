import SwiftUI

/// 新建 / 编辑笔记：课程选择器 + 正文输入区，标题取自正文第一行。
struct MemoEditView: View {

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let memo: Memo?

    @State private var courseId: UUID?
    @State private var content: String
    @State private var errorMessage: String?

    init(courseId: UUID, memo: Memo? = nil) {
        self.memo = memo
        _courseId = State(initialValue: memo?.courseId ?? courseId)
        _content = State(initialValue: memo?.content ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("课程", selection: $courseId) {
                        ForEach(availableCourses) { course in
                            Text(course.name).tag(UUID?.some(course.id))
                        }
                    }
                } footer: {
                    Text("自动关联至当前课程")
                }

                Section("正文") {
                    TextEditor(text: $content)
                        .frame(minHeight: 220)
                        .overlay(alignment: .topLeading) {
                            if content.isBlank {
                                Text("写点什么⋯")
                                    .font(DesignTokens.Typography.body)
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }
            .navigationTitle(memo == nil ? "添加笔记" : "编辑笔记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(content.isBlank || courseId == nil)
                }
            }
            .errorAlert($errorMessage)
        }
    }
}

extension MemoEditView {

    private var availableCourses: [Course] {
        if let semesterId = store.currentSemester?.id {
            let courses = store.courses(in: semesterId)
            if !courses.isEmpty { return courses }
        }
        return store.data.courses.sorted { $0.name < $1.name }
    }

    private func save() {
        guard let courseId else { return }

        do {
            if let memo {
                try store.updateMemo(
                    id: memo.id,
                    title: memo.title,
                    content: content,
                    courseId: courseId
                )
            } else {
                try store.createMemo(courseId: courseId, content: content)
            }
            dismiss()
        } catch {
            errorMessage = error.userMessage
        }
    }
}

#Preview("新建笔记") {
    let seed = PreviewSupport.seed

    MemoEditView(courseId: seed.math.id)
        .environment(seed.store)
}

#Preview("编辑笔记") {
    let seed = PreviewSupport.seed

    MemoEditView(courseId: seed.math.id, memo: seed.memo)
        .environment(seed.store)
}
