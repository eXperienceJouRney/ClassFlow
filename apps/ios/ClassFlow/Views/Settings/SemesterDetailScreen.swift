import SwiftUI

/// 学期详情页：学期信息、课程列表与设为当前学期 / 删除入口。
struct SemesterDetailScreen: View {

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let semesterId: UUID

    @State private var showsNewCourse = false
    @State private var editingCourse: Course?
    @State private var showsDeletion = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let semester = store.data.semester(id: semesterId) {
                content(semester)
            } else {
                EmptyStateView(
                    icon: "questionmark.folder",
                    title: "学期不存在",
                    message: "它可能已经被删除了。"
                )
            }
        }
        .navigationTitle(store.data.semester(id: semesterId)?.name ?? "学期")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let semester = store.data.semester(id: semesterId) {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SemesterEditView(semester: semester)
                    } label: {
                        Text("编辑")
                    }
                }
            }
        }
        .sheet(isPresented: $showsNewCourse) {
            CourseEditView(semesterId: semesterId, course: nil)
        }
        .sheet(item: $editingCourse) { course in
            CourseEditView(semesterId: semesterId, course: course)
        }
        .sheet(isPresented: $showsDeletion) {
            SemesterDeletionView(semesterId: semesterId) { dismiss() }
        }
        .errorAlert($errorMessage)
    }
}

extension SemesterDetailScreen {

    private func content(_ semester: Semester) -> some View {
        let courses = store.courses(in: semester.id)
        let isCurrent = store.currentSemester?.id == semester.id

        return List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(semester.dateRangeText)
                        .font(DesignTokens.Typography.secondary)
                        .foregroundStyle(.secondary)

                    Text(isCurrent ? "V当前学期" : "历史学期")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
                }
                .padding(.vertical, 2)
            }

            Section("课程") {
                if courses.isEmpty {
                    Text("这个学期还没有课程").foregroundStyle(.secondary)
                } else {
                    ForEach(courses) { course in
                        Button {
                            editingCourse = course
                        } label: {
                            courseRow(course, semester: semester)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button("添加课程", systemImage: "plus") { showsNewCourse = true }
            }

            Section {
                Button("设为当前学期") { setCurrent(semester) }
                    .disabled(isCurrent)

                Button("删除学期", systemImage: "trash", role: .destructive) {
                    showsDeletion = true
                }
            }
        }
    }

    @ViewBuilder
    private func courseRow(_ course: Course, semester: Semester) -> some View {
        let entries = store.scheduleEntries(for: course.id)
        let summary = entries.summary(
            periods: store.effectivePeriodTimes(in: semester.id),
            timeFormat: store.preferences.timeFormat
        )

        VStack(alignment: .leading, spacing: 3) {
            Text(course.name)
                .font(DesignTokens.Typography.rowTitle)
                .foregroundStyle(.primary)

            if let summary {
                Text(summary.displayText)
                    .font(DesignTokens.Typography.secondary)
                    .foregroundStyle(.secondary)
            }

            if let location = course.location, !location.isBlank {
                Text("教室\(location)")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func setCurrent(_ semester: Semester) {
        do {
            try store.setCurrentSemester(id: semester.id)
        } catch {
            errorMessage = error.userMessage
        }
    }
}

#Preview("学期详情 · 当前学期") {
    let seed = PreviewSupport.seed

    NavigationStack {
        SemesterDetailScreen(semesterId: seed.semester.id)
    }
    .environment(seed.store)
}

#Preview("学期详情 · 学期不存在") {
    NavigationStack {
        SemesterDetailScreen(semesterId: UUID())
    }
    .environment(PreviewSupport.blankStore)
}
