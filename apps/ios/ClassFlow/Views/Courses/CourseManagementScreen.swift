import SwiftUI

/// 按学期分组管理课程：支持新增、点按编辑与左滑删除。
struct CourseManagementScreen: View {

    @Environment(AppStore.self) private var store

    @State private var showsNewCourse = false
    @State private var editingCourse: Course?
    @State private var deletingCourse: Course?

    var body: some View {
        List {
            if store.data.courses.isEmpty {
                Section {
                    Text("还没有课程")
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("先在学期里添加课程，之后可以安排上课时间和地点。")
                }
            }

            ForEach(store.semesters) { semester in
                let courses = store.courses(in: semester.id)
                if !courses.isEmpty {
                    Section(semester.name) {
                        ForEach(courses) { course in
                            courseRow(course, semester: semester)
                        }
                    }
                }
            }

            Section {
                Button("添加课程", systemImage: "plus") { showsNewCourse = true }
                    .disabled(newCourseSemesterId == nil)
            } footer: {
                if newCourseSemesterId == nil {
                    Text("还没有学期，先去设置里创建一个学期。")
                }
            }
        }
        .navigationTitle("管理课程")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsNewCourse) {
            if let semesterId = newCourseSemesterId {
                CourseEditView(semesterId: semesterId, course: nil)
            }
        }
        .sheet(item: $editingCourse) { course in
            CourseEditView(semesterId: course.semesterId, course: course)
        }
        .sheet(item: $deletingCourse) { course in
            CourseDeletionView(courseId: course.id) {}
        }
    }
}

extension CourseManagementScreen {

    /// 新课程落在当前学期；没有当前学期就退而用最新的一个。
    private var newCourseSemesterId: UUID? {
        store.currentSemester?.id ?? store.semesters.first?.id
    }

    @ViewBuilder
    private func courseRow(_ course: Course, semester: Semester) -> some View {
        let summary = store.scheduleEntries(for: course.id).summary(
            periods: store.effectivePeriodTimes(in: semester.id),
            timeFormat: store.preferences.timeFormat
        )

        Button {
            editingCourse = course
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill((course.color ?? .gray).color)
                    .frame(width: 10, height: 10)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 3) {
                    Text(course.name)
                        .font(DesignTokens.Typography.rowTitle)
                        .foregroundStyle(.primary)

                    if let summary {
                        Text(summary.displayText)
                            .font(DesignTokens.Typography.secondary)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("还没有上课安排")
                            .font(DesignTokens.Typography.secondary)
                            .foregroundStyle(.tertiary)
                    }

                    if let location = course.location, !location.isBlank {
                        Text(location)
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("删除", role: .destructive) { deletingCourse = course }
        }
    }
}

#Preview("管理课程") {
    NavigationStack {
        CourseManagementScreen()
    }
    .environment(PreviewSupport.store)
}

#Preview("管理课程 · 空") {
    NavigationStack {
        CourseManagementScreen()
    }
    .environment(PreviewSupport.blankStore)
}
