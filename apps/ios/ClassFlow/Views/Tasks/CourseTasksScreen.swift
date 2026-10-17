import SwiftUI

/// 某门课程的全部待办列表。
struct CourseTasksScreen: View {

    @Environment(AppStore.self) private var store

    let courseId: UUID

    @State private var editingTask: CourseTask?
    @State private var showsNewTask = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if tasks.isEmpty {
                Section {
                    Text("这门课还没有待办")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(tasks) { task in
                        TaskRowView(task: task, showsCourse: false) {
                            editingTask = task
                        }
                        .swipeActions(edge: .trailing) {
                            Button("删除", role: .destructive) { delete(task) }
                        }
                    }
                } header: {
                    Text("\(tasks.count) 项待办")
                }
            }

            Section {
                Button("新建待办", systemImage: "plus") { showsNewTask = true }
            }
        }
        .navigationTitle(store.course(id: courseId)?.name ?? "课程待办")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsNewTask) {
            TaskEditView(task: nil, presetCourseId: courseId)
        }
        .sheet(item: $editingTask) { task in
            TaskEditView(task: task)
        }
        .errorAlert($errorMessage)
    }
}

extension CourseTasksScreen {

    private var tasks: [CourseTask] {
        store.tasks(forCourseId: courseId)
    }

    private func delete(_ task: CourseTask) {
        do {
            try store.deleteTask(id: task.id)
        } catch {
            errorMessage = error.userMessage
        }
    }
}

#Preview("课程待办 · 有内容") {
    let seed = PreviewSupport.seed

    NavigationStack {
        CourseTasksScreen(courseId: seed.math.id)
    }
    .environment(seed.store)
}

#Preview("课程待办 · 空") {
    let seed = PreviewSupport.seed

    NavigationStack {
        CourseTasksScreen(courseId: seed.physicalEducation.id)
    }
    .environment(seed.store)
}
