import SwiftUI

struct SemesterDeletionView: View {

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let semesterId: UUID
    private let onDeleted: (() -> Void)?

    @State private var strategy: DeletionStrategy = .deleteRelated
    @State private var errorMessage: String?

    init(semester: Semester, onDeleted: (() -> Void)? = nil) {
        self.semesterId = semester.id
        self.onDeleted = onDeleted
    }

    init(semesterId: UUID, onDeleted: (() -> Void)? = nil) {
        self.semesterId = semesterId
        self.onDeleted = onDeleted
    }

    var body: some View {
        NavigationStack {
            List {
                if let preview = store.semesterDeletionPreview(id: semesterId) {
                    Section("将删除") {
                        ForEach(preview.summaryLines, id: \.self) { line in
                            Label(line, systemImage: "exclamationmark.circle")
                                .font(.callout)
                        }
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
                        } footer: {
                            Text("笔记必须属于一门课程，因此无论选择哪种方式，受影响的笔记都会被删除。")
                        }
                    }
                }

                Section {
                    Label("该操作不可撤销", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("删除学期")
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
            try store.deleteSemester(id: semesterId, strategy: strategy)
            dismiss()
            onDeleted?()
        } catch {
            errorMessage = error.userMessage
        }
    }
}

#Preview("删除学期") {
    let seed = PreviewSupport.seed

    SemesterDeletionView(semester: seed.semester)
        .environment(seed.store)
}
