import SwiftUI

struct CourseDeletionView: View {

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let courseId: UUID
    var onDeleted: () -> Void

    @State private var strategy: DeletionStrategy = .deleteRelated
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let preview = store.courseDeletionPreview(id: courseId) {
                    Section("将删除") {
                        Label("\(preview.scheduleEntryCount) 条上课安排", systemImage: "clock")
                        Label("\(preview.affectedMemoCount) 条笔记", systemImage: "note.text")
                        Label(
                            preview.affectedTaskCount > 0
                                ? "影响 \(preview.affectedTaskCount) 个任务"
                                : "没有关联任务",
                            systemImage: "checklist"
                        )
                    }

                    if preview.strategies.count > 1 {
                        Section {
                            Picker("关联任务处理", selection: $strategy) {
                                ForEach(preview.strategies, id: \.self) { item in
                                    Text(item.displayName).tag(item)
                                }
                            }
                            .pickerStyle(.inline)
                            .labelsHidden()
                        } header: {
                            Text("关联任务")
                        }
                    }
                }

                Section {
                    Label("该操作不可撤销", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("删除课程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("删除", role: .destructive) { confirm() }
                }
            }
            .errorAlert($errorMessage)
        }
    }

    private func confirm() {
        do {
            try store.deleteCourse(id: courseId, strategy: strategy)
            dismiss()
            onDeleted()
        } catch {
            errorMessage = error.userMessage
        }
    }
}

#Preview("删除课程") {
    let seed = PreviewSupport.seed

    CourseDeletionView(courseId: seed.math.id) {}
        .environment(seed.store)
}
