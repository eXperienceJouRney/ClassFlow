import SwiftUI

enum TaskGrouping: String, CaseIterable, Identifiable {

    case byTime
    case byCourse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .byTime: "按时间"
        case .byCourse: "按课程"
        }
    }
}

/// 待办列表：按时间或课程分组。
struct TaskListScreen: View {

    @Environment(AppStore.self) private var store
    /// 桌面组件的深链路由；未注入时为 nil。
    @Environment(AppRouter.self) private var router: AppRouter?

    @State private var grouping: TaskGrouping
    @State private var showsNewTask = false
    @State private var editingTask: CourseTask?

    /// 初始分组方式，默认为按时间。
    init(grouping: TaskGrouping = .byTime) {
        _grouping = State(initialValue: grouping)
    }

    var body: some View {
        NavigationStack {
            List {
                groupingPicker

                switch grouping {
                case .byTime:
                    byTimeSections
                case .byCourse:
                    byCourseSections
                }
            }
            .navigationTitle("待办")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("添加待办", systemImage: "plus") {
                        showsNewTask = true
                    }
                }
            }
            .sheet(isPresented: $showsNewTask) {
                TaskEditView(task: nil)
            }
            .sheet(item: $editingTask) { task in
                TaskEditView(task: task)
            }
            .overlay {
                if store.allTasks.isEmpty {
                    EmptyStateView(
                        icon: "checklist",
                        title: "还没有待办",
                        message: "点右上角加号创建第一条待办。"
                    )
                }
            }
        }
        .onAppear { handleWidgetRoute(router?.pending) }
        .onChange(of: router?.pending) { _, destination in
            handleWidgetRoute(destination)
        }
    }
}

// MARK: - 桌面组件跳转

extension TaskListScreen {

    private func handleWidgetRoute(_ destination: WidgetDeepLink.Destination?) {
        guard case let .task(id) = destination else { return }
        defer { router?.finish(.task(id)) }

        if let task = store.task(id: id) {
            editingTask = task
        }
    }
}

extension TaskListScreen {

    private var groupingPicker: some View {
        Section {
            Picker("分组方式", selection: $grouping) {
                ForEach(TaskGrouping.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder
    private var byTimeSections: some View {
        let now = Date()

        ForEach(TaskDueBucket.displayOrder, id: \.self) { bucket in
            let tasks = store.allTasks.filter {
                $0.dueText(now: now, format: store.preferences.timeFormat).bucket == bucket
            }

            if !tasks.isEmpty {
                Section(bucket.title) {
                    ForEach(ordered(tasks)) { task in taskRow(task) }
                }
            }
        }
    }

    @ViewBuilder
    private var byCourseSections: some View {
        ForEach(courseGroups) { group in
            Section(group.name) {
                ForEach(ordered(group.tasks)) { task in taskRow(task) }
            }
        }
    }

    /// 按课程分组的一个分组；`id` 必须是稳定标识（课程 id 或未关联课程的固定 key）。
    struct CourseTaskGroup: Identifiable {
        let id: String
        let name: String
        let tasks: [CourseTask]
    }

    /// 全部学期里的课程，按学期顺序（新的在前）再按课程名排列。
    private var orderedCourses: [Course] {
        store.semesters.flatMap { store.courses(in: $0.id) }
    }

    /// 按课程分组：有课的课程各一组，课程已删除或本来就未关联的归到 `未关联课程`。
    private var courseGroups: [CourseTaskGroup] {
        let courses = orderedCourses
        var groups: [CourseTaskGroup] = []

        for course in courses {
            let tasks = store.tasks(forCourseId: course.id)
            if !tasks.isEmpty {
                groups.append(
                    CourseTaskGroup(id: course.id.uuidString, name: course.name, tasks: tasks)
                )
            }
        }

        let knownIds = Set(courses.map(\.id))
        let unassigned = store.allTasks.filter { task in
            guard let courseId = task.courseId else { return true }
            return !knownIds.contains(courseId)
        }
        if !unassigned.isEmpty {
            groups.append(
                CourseTaskGroup(id: "unassigned", name: "未关联课程", tasks: unassigned)
            )
        }

        return groups
    }

    /// 未完成的排在前面，已完成 / 已取消的排在末尾。
    private func ordered(_ tasks: [CourseTask]) -> [CourseTask] {
        tasks.filter(\.status.isOpen) + tasks.filter(\.status.isTerminal)
    }

    private func taskRow(_ task: CourseTask) -> some View {
        TaskRowView(task: task, showsCourse: grouping == .byTime) {
            editingTask = task
        }
        .swipeActions(edge: .trailing) {
            Button("删除", role: .destructive) {
                try? store.deleteTask(id: task.id)
            }
        }
    }
}

#Preview("待办列表") {
    TaskListScreen()
        .environment(PreviewSupport.store)
}

#Preview("待办列表 · 按课程") {
    TaskListScreen(grouping: .byCourse)
        .environment(PreviewSupport.store)
}

#Preview("待办列表 · 还没有待办") {
    TaskListScreen()
        .environment(PreviewSupport.emptyStore)
}
