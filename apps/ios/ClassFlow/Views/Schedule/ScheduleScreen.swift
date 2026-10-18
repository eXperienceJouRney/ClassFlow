import SwiftUI

/// 课程表主界面：自绘头部（标题、学期副标题、日/周/月切换与一周日期条）加日/周/月三种视图。
struct ScheduleScreen: View {

    @Environment(AppStore.self) private var store
    /// 桌面组件的深链路由；为 nil 时不处理深链。
    @Environment(AppRouter.self) private var router: AppRouter?

    @State private var mode: ScheduleMode = .week
    @State private var weekNumber = 1
    @State private var selectedDate = CalendarDate.today()
    @State private var monthAnchor = CalendarDate.today()
    @State private var showsSemesterSheet = false
    @State private var showsNewCourse = false
    @State private var showsSettings = false
    /// 是否显示节次时间设置页（由 `classflow://settings/period-times` 深链置位）
    @State private var showsPeriodTimes = false
    /// 课程详情底部面板
    @State private var selectedCourse: Course?
    /// 月视图里点到的到期待办
    @State private var selectedTask: CourseTask?
    /// 默认视图仅在首次出现时应用，之后不再覆盖。
    @State private var hasAppliedDefaultMode = false

    var body: some View {
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
                .sheet(item: $selectedCourse) { course in
                    CourseDetailView(courseId: course.id)
                }
                .sheet(item: $selectedTask) { task in
                    TaskEditView(task: task)
                }
                .navigationDestination(isPresented: $showsSettings) {
                    SettingsScreen()
                }
                .navigationDestination(isPresented: $showsPeriodTimes) {
                    PeriodTimesScreen()
                }
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button("今天", systemImage: "arrow.uturn.backward") {
                            jumpToToday()
                        }
                        .labelStyle(.iconOnly)

                        Button("设置", systemImage: "gearshape") {
                            showsSettings = true
                        }
                        .labelStyle(.iconOnly)
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button("添加课程", systemImage: "plus") {
                            showsNewCourse = true
                        }
                    }
                }
                .sheet(isPresented: $showsSemesterSheet) {
                    SemesterEditView()
                }
                .sheet(isPresented: $showsNewCourse) {
                    if let semester = store.currentSemester {
                        CourseEditView(semesterId: semester.id, course: nil)
                    }
                }
        }
        // 桌面组件的 URL 与 App Intent 两条入口都汇总到 `router.pending`。
        .onAppear { handleWidgetRoute(router?.pending) }
        .onChange(of: router?.pending) { _, destination in
            handleWidgetRoute(destination)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let semester = store.currentSemester,
           let timetable = store.timetable(for: semester.id) {
            VStack(spacing: 0) {
                ScheduleHeaderView(
                    semester: semester,
                    title: headerTitle(timetable: timetable),
                    mode: mode,
                    weekDates: weekDates(timetable: timetable),
                    selectedDate: selectedDate,
                    onSelectMode: { newMode in
                        mode = newMode
                        if newMode == .month {
                            monthAnchor = selectedDate
                            if let week = semester.weekIndex(of: selectedDate) {
                                weekNumber = week
                            }
                        }
                    },
                    onSelectDate: { date in
                        selectedDate = date
                        if let week = semester.weekIndex(of: date) { weekNumber = week }
                    }
                )

                Divider()

                scheduleBody(for: timetable, semester: semester)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .onAppear {
                applyDefaultModeIfNeeded()
                syncToToday(semester: semester)
            }
        } else {
            EmptyStateView(
                icon: "graduationcap",
                title: "还没有学期",
                message: "先创建一个学期，然后就可以添加课程了。课节作息有内置默认值，随时可以在设置里改。",
                actionTitle: "创建学期"
            ) {
                showsSemesterSheet = true
            }
        }
    }

    @ViewBuilder
    private func scheduleBody(for timetable: Timetable, semester: Semester) -> some View {
        let onSwipePage: (Int) -> Void = { delta in
            step(delta, semester: semester, timetable: timetable)
        }

        switch mode {
        case .week:
            WeekScheduleView(
                timetable: timetable,
                week: weekNumber,
                timeFormat: store.preferences.timeFormat,
                firstWeekday: store.preferences.firstWeekday,
                showsTeacherInCourseBlock: store.preferences.showsTeacherInWeekGrid,
                onSelectDay: { date in
                    selectedDate = date
                    weekNumber = semester.weekIndex(of: date) ?? weekNumber
                    mode = .day
                },
                onSelectCourse: { selectedCourse = $0 },
                onSwipePage: onSwipePage
            )

        case .day:
            DayScheduleView(
                timetable: timetable,
                date: selectedDate,
                timeFormat: store.preferences.timeFormat,
                onSelectCourse: { selectedCourse = $0 },
                onSwipePage: onSwipePage
            )

        case .month:
            MonthScheduleView(
                timetable: timetable,
                anchor: monthAnchor,
                selectedDate: $selectedDate,
                onSelectCourse: { selectedCourse = $0 },
                onSelectTask: { selectedTask = $0 },
                timeFormat: store.preferences.timeFormat,
                firstWeekday: store.preferences.firstWeekday,
                onSwipePage: onSwipePage
            )
        }
    }
}

extension ScheduleScreen {

    private func headerTitle(timetable: Timetable) -> String {
        switch mode {
        case .week:
            guard let dates = weekDates(timetable: timetable).first,
                  let last = weekDates(timetable: timetable).last
            else { return "第 \(weekNumber) 周" }

            if dates.month == last.month {
                return "\(dates.month)月\(dates.day)-\(last.day)日"
            }
            return "\(dates.month)月\(dates.day)日-\(last.month)月\(last.day)日"

        case .day:
            let weekday = selectedDate.weekday()?.shortName ?? ""
            return "\(selectedDate.month)月\(selectedDate.day)日\(weekday)"

        case .month:
            return "\(monthAnchor.year)年\(monthAnchor.month)月"
        }
    }

    private func weekDates(timetable: Timetable) -> [CalendarDate] {
        let total = max(timetable.semester.weekCount(), 1)
        let week = min(max(weekNumber, 1), total)
        let dates = timetable.dates(inWeek: week)
        let resolved = dates.isEmpty ? timetable.dates(inWeek: 1) : dates
        return resolved.ordered(from: store.preferences.firstWeekday)
    }

    /// 首次出现时按偏好设置设定默认视图。
    private func applyDefaultModeIfNeeded() {
        guard !hasAppliedDefaultMode else { return }
        hasAppliedDefaultMode = true
        mode = store.preferences.defaultScheduleMode
    }

    private func jumpToToday() {
        guard let semester = store.currentSemester else { return }
        syncToToday(semester: semester)
    }

    private func syncToToday(semester: Semester) {
        let today = CalendarDate.today()
        if let week = semester.weekIndex(of: today) {
            weekNumber = week
            selectedDate = today
            monthAnchor = today
        } else {
            weekNumber = 1
            selectedDate = semester.startDate
            monthAnchor = semester.startDate
        }
    }

    private func canStep(_ delta: Int, semester: Semester, timetable: Timetable) -> Bool {
        switch mode {
        case .week:
            let total = max(semester.weekCount(), 1)
            return (1...total).contains(weekNumber + delta)
        case .day:
            guard let next = selectedDate.adding(days: delta) else { return false }
            return semester.contains(next)
        case .month:
            guard let next = monthAnchor.addingMonths(delta)?.startOfMonth else { return false }
            return next <= semester.endDate && next.endOfMonth >= semester.startDate
        }
    }

    /// 翻页：`delta` 为 +1 时往后翻；越界时不做任何操作。
    private func step(_ delta: Int, semester: Semester, timetable: Timetable) {
        guard canStep(delta, semester: semester, timetable: timetable) else { return }

        switch mode {
        case .week:
            let total = max(semester.weekCount(), 1)
            weekNumber = min(max(weekNumber + delta, 1), total)
            if let first = timetable.dates(inWeek: weekNumber).first {
                selectedDate = first
            }
        case .day:
            guard let next = selectedDate.adding(days: delta), semester.contains(next) else { return }
            selectedDate = next
            weekNumber = semester.weekIndex(of: next) ?? weekNumber
        case .month:
            guard let next = monthAnchor.addingMonths(delta)?.startOfMonth else { return }
            monthAnchor = next
        }
    }
}

// MARK: - 桌面组件跳转

extension ScheduleScreen {

    /// 处理来自桌面组件的深链；待办 / 笔记类目标由 `AppRouter` 切 Tab，此处忽略。
    private func handleWidgetRoute(_ destination: WidgetDeepLink.Destination?) {
        guard let destination else { return }
        defer { router?.finish(destination) }

        switch destination {
        case let .course(id):
            selectedCourse = store.course(id: id)

        case .scheduleToday:
            jumpToToday()

        case let .scheduleWeek(offset):
            guard let semester = store.currentSemester else { return }
            syncToToday(semester: semester)

            let total = max(semester.weekCount(), 1)
            weekNumber = min(max(weekNumber + offset, 1), total)
            mode = .week

        case .periodTimes:
            showsPeriodTimes = true

        case .tasks, .task, .notes, .memo, .newMemo:
            break
        }
    }
}

#Preview("课程表 · 有课") {
    ScheduleScreen()
        .environment(PreviewSupport.store)
        .environment(AppRouter())
}

#Preview("课程表 · 学期里还没有课") {
    ScheduleScreen()
        .environment(PreviewSupport.emptyStore)
        .environment(AppRouter())
}

#Preview("课程表 · 还没有学期") {
    ScheduleScreen()
        .environment(PreviewSupport.blankStore)
        .environment(AppRouter())
}
