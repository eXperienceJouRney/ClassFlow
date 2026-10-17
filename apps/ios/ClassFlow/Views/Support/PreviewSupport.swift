import Foundation

/// SwiftUI 预览（`#Preview`）共用的种子数据；每次取用都新建内存态 `AppStore`，不写磁盘。
@MainActor
enum PreviewSupport {

    static let semesterName = "2026 秋季学期"
    static let semesterStart = CalendarDate("2026-09-07")!
    static let semesterEnd = CalendarDate("2026-12-27")!

    // MARK: - 主数据集

    /// 内容比较全的一套预览数据：一个学期、5 门课、2 条任务、1 条笔记和对应课表。
    struct Seed {

        let store: AppStore
        let semester: Semester
        let math: Course
        let english: Course
        let dataStructures: Course
        let linearAlgebra: Course
        let physicalEducation: Course
        let task: CourseTask
        let standaloneTask: CourseTask
        let overdueTask: CourseTask
        let undatedTask: CourseTask
        let completedTask: CourseTask
        let memo: Memo
        let timetable: Timetable
        let importDraftId: UUID?

        /// 种子里全部任务，顺序与「按时间」分组的展示顺序一致。
        var tasks: [CourseTask] {
            [overdueTask, task, standaloneTask, undatedTask, completedTask]
        }

        /// 第 1 周的周一；日视图和课程卡片预览都落在这一天。
        var monday: CalendarDate {
            timetable.dates(inWeek: 1).first ?? semester.startDate
        }

        var mondayClasses: [ClassOccurrence] {
            timetable.classes(on: monday)
        }

        /// 周一的第一节课；缺课时退回可渲染的占位课程。
        var firstClass: ClassOccurrence {
            mondayClasses.first ?? ClassOccurrence(
                course: math,
                entry: ScheduleEntry(
                    courseId: math.id,
                    weekday: .monday,
                    time: .period(start: 1, end: 2),
                    startWeek: 1,
                    endWeek: 16
                ),
                date: monday,
                week: 1,
                clockTime: nil
            )
        }
    }

    /// 主数据集；`PreviewSupport.store` 就是它的 `store`。
    static var seed: Seed {
        let store = AppStore(store: InMemoryDataStore())

        let semester = makeSemester(in: store)

        let math = (try? store.createCourse(
            semesterId: semester.id,
            name: "高等数学",
            teacher: "王老师",
            location: "教三 201",
            color: .blue,
            scheduleEntries: [
                ScheduleEntryInput(
                    weekday: .monday,
                    time: .period(start: 1, end: 2),
                    weekRule: WeekRule(startWeek: 1, endWeek: 16)
                ),
                ScheduleEntryInput(
                    weekday: .wednesday,
                    time: .period(start: 3, end: 4),
                    weekRule: WeekRule(startWeek: 1, endWeek: 16)
                ),
            ]
        )) ?? Course(
            semesterId: semester.id,
            name: "高等数学",
            teacher: "王老师",
            location: "教三 201",
            color: .blue
        )

        let english = (try? store.createCourse(
            semesterId: semester.id,
            name: "大学英语",
            teacher: "李老师",
            location: "外语楼 305",
            color: .green,
            scheduleEntries: [
                ScheduleEntryInput(
                    weekday: .tuesday,
                    time: .period(start: 3, end: 4),
                    weekRule: WeekRule(startWeek: 1, endWeek: 16)
                ),
                ScheduleEntryInput(
                    weekday: .thursday,
                    time: .period(start: 1, end: 2),
                    weekRule: WeekRule(startWeek: 1, endWeek: 16)
                ),
            ]
        )) ?? Course(
            semesterId: semester.id,
            name: "大学英语",
            teacher: "李老师",
            location: "外语楼 305",
            color: .green
        )

        let dataStructures = (try? store.createCourse(
            semesterId: semester.id,
            name: "数据结构",
            teacher: "陈老师",
            location: "计算机楼 402",
            color: .orange,
            scheduleEntries: [
                ScheduleEntryInput(
                    weekday: .tuesday,
                    time: .period(start: 5, end: 6),
                    weekRule: WeekRule(startWeek: 1, endWeek: 16)
                ),
                ScheduleEntryInput(
                    weekday: .thursday,
                    time: .period(start: 5, end: 6),
                    weekRule: WeekRule(startWeek: 1, endWeek: 16)
                ),
            ]
        )) ?? Course(
            semesterId: semester.id,
            name: "数据结构",
            teacher: "陈老师",
            location: "计算机楼 402",
            color: .orange
        )

        let linearAlgebra = (try? store.createCourse(
            semesterId: semester.id,
            name: "线性代数",
            teacher: "张老师",
            location: "教三 108",
            color: .purple,
            scheduleEntries: [
                ScheduleEntryInput(
                    weekday: .friday,
                    time: .period(start: 1, end: 2),
                    weekRule: WeekRule(startWeek: 1, endWeek: 16)
                )
            ]
        )) ?? Course(
            semesterId: semester.id,
            name: "线性代数",
            teacher: "张老师",
            location: "教三 108",
            color: .purple
        )

        let physicalEducation = (try? store.createCourse(
            semesterId: semester.id,
            name: "体育",
            location: "体育馆",
            color: .teal,
            scheduleEntries: [
                ScheduleEntryInput(
                    weekday: .wednesday,
                    time: .custom(
                        start: TimeOfDay(hour: 16, minute: 0)!,
                        end: TimeOfDay(hour: 17, minute: 30)!
                    ),
                    weekRule: WeekRule(startWeek: 1, endWeek: 16, pattern: .oddWeeks)
                )
            ]
        )) ?? Course(
            semesterId: semester.id,
            name: "体育",
            location: "体育馆",
            color: .teal
        )

        let task = (try? store.createTask(
            title: "高数作业：第三章习题",
            courseId: math.id,
            dueDate: CalendarDate("2026-10-20"),
            dueTime: TimeOfDay(hour: 22, minute: 0)
        )) ?? CourseTask(
            title: "高数作业：第三章习题",
            courseId: math.id,
            dueDate: CalendarDate("2026-10-20"),
            dueTime: TimeOfDay(hour: 22, minute: 0)
        )

        let standaloneTask = (try? store.createTask(
            title: "买教材",
            dueDate: CalendarDate("2026-10-16")
        )) ?? CourseTask(title: "买教材", dueDate: CalendarDate("2026-10-16"))

        let overdueTask = (try? store.createTask(
            title: "实验报告：二叉树遍历",
            courseId: dataStructures.id,
            dueDate: CalendarDate("2020-03-01")
        )) ?? CourseTask(
            title: "实验报告：二叉树遍历",
            courseId: dataStructures.id,
            dueDate: CalendarDate("2020-03-01")
        )

        let undatedTask = (try? store.createTask(title: "读完《数据结构》第 4 章"))
            ?? CourseTask(title: "读完《数据结构》第 4 章")

        var completedTask = (try? store.createTask(
            title: "整理线性代数笔记",
            courseId: linearAlgebra.id,
            dueDate: CalendarDate("2026-10-10")
        )) ?? CourseTask(
            title: "整理线性代数笔记",
            courseId: linearAlgebra.id,
            dueDate: CalendarDate("2026-10-10")
        )

        try? store.setTaskStatus(id: completedTask.id, to: .completed)
        completedTask = store.task(id: completedTask.id) ?? completedTask

        _ = try? store.createTask(
            title: "英语作文：My Campus Life",
            courseId: english.id,
            dueDate: CalendarDate("2026-10-25")
        )

        let memo = (try? store.createMemo(
            courseId: math.id,
            title: "极限的定义",
            content: "ε-δ 语言：对任意 ε>0，存在 δ>0，使得 0<|x-a|<δ 时 |f(x)-L|<ε。"
        )) ?? Memo(
            courseId: math.id,
            title: "极限的定义",
            content: "ε-δ 语言：对任意 ε>0，存在 δ>0，使得 0<|x-a|<δ 时 |f(x)-L|<ε。"
        )

        return Seed(
            store: store,
            semester: semester,
            math: math,
            english: english,
            dataStructures: dataStructures,
            linearAlgebra: linearAlgebra,
            physicalEducation: physicalEducation,
            task: task,
            standaloneTask: standaloneTask,
            overdueTask: overdueTask,
            undatedTask: undatedTask,
            completedTask: completedTask,
            memo: memo,
            timetable: timetable(in: store, semester: semester),
            importDraftId: makeImportDraftId(in: store, semesterId: semester.id)
        )
    }

    /// 只关心 `AppStore` 的预览用这个。
    static var store: AppStore { seed.store }

    // MARK: - 特定场景

    /// 两门课排在同一个时段（周一 1-2 节）的冲突场景。
    struct ConflictScenario {

        let store: AppStore
        let semester: Semester
        let math: Course
        let physics: Course
        let timetable: Timetable
    }

    static var conflictScenario: ConflictScenario {
        let store = AppStore(store: InMemoryDataStore())
        let semester = makeSemester(in: store)

        let math = (try? store.createCourse(
            semesterId: semester.id,
            name: "高等数学",
            teacher: "王老师",
            location: "教三 201",
            color: .blue,
            scheduleEntries: [
                ScheduleEntryInput(
                    weekday: .monday,
                    time: .period(start: 1, end: 2),
                    weekRule: WeekRule(startWeek: 1, endWeek: 16)
                ),
                ScheduleEntryInput(
                    weekday: .wednesday,
                    time: .period(start: 3, end: 4),
                    weekRule: WeekRule(startWeek: 1, endWeek: 16)
                ),
            ]
        )) ?? Course(
            semesterId: semester.id,
            name: "高等数学",
            teacher: "王老师",
            location: "教三 201",
            color: .blue
        )

        let physics = (try? store.createCourse(
            semesterId: semester.id,
            name: "大学物理",
            teacher: "赵老师",
            location: "理科楼 101",
            color: .red,
            scheduleEntries: [
                ScheduleEntryInput(
                    weekday: .monday,
                    time: .period(start: 1, end: 2),
                    weekRule: WeekRule(startWeek: 1, endWeek: 16)
                )
            ]
        )) ?? Course(
            semesterId: semester.id,
            name: "大学物理",
            teacher: "赵老师",
            location: "理科楼 101",
            color: .red
        )

        return ConflictScenario(
            store: store,
            semester: semester,
            math: math,
            physics: physics,
            timetable: timetable(in: store, semester: semester)
        )
    }

    /// 有学期、但还没有课程的 store，用来预览空态（作息走内置默认作息）。
    static var emptyStore: AppStore {
        let store = AppStore(store: InMemoryDataStore())
        _ = makeSemester(in: store)
        return store
    }

    /// 全新空 store（连学期都没有），用来预览首次启动的引导页。
    static var blankStore: AppStore {
        AppStore(store: InMemoryDataStore())
    }

    // MARK: - 共享素材

    /// 一套写进学期里的作息（等价于内置默认作息，用来预览「用户改过作息」的样子）。
    static var defaultPeriods: [ClassPeriodInput] {
        ClassPeriodTime.defaultSlots.compactMap { slot in
            guard let start = TimeOfDay(slot.start), let end = TimeOfDay(slot.end) else { return nil }
            return ClassPeriodInput(periodNumber: slot.periodNumber, startTime: start, endTime: end)
        }
    }

    /// 一条用于预览「待修正」状态的导入记录。
    static func importEntry(
        draftId: UUID = UUID(),
        sourceIndex: Int = 0,
        courseName: String = "高等数学",
        teacher: String? = "王老师",
        location: String? = "教三201",
        weekday: Weekday? = .monday,
        startPeriod: Int? = 1,
        endPeriod: Int? = 2,
        startTime: TimeOfDay? = nil,
        endTime: TimeOfDay? = nil,
        rawPayload: String? = nil,
        status: ImportEntryStatus = .ready,
        issues: [ValidationIssue] = []
    ) -> ImportDraftEntry {
        ImportDraftEntry(
            draftId: draftId,
            sourceIndex: sourceIndex,
            rawPayload: rawPayload,
            courseName: courseName,
            teacher: teacher,
            location: location,
            weekday: weekday,
            startPeriod: startPeriod,
            endPeriod: endPeriod,
            startTime: startTime,
            endTime: endTime,
            startWeek: 1,
            endWeek: 16,
            status: status,
            issues: issues
        )
    }
}

// MARK: - 构造辅助

extension PreviewSupport {

    private static func makeSemester(in store: AppStore) -> Semester {
        (try? store.createSemester(
            name: semesterName,
            startDate: semesterStart,
            endDate: semesterEnd
        )) ?? Semester(name: semesterName, startDate: semesterStart, endDate: semesterEnd)
    }

    private static func timetable(in store: AppStore, semester: Semester) -> Timetable {
        store.timetable(for: semester.id)
            ?? Timetable(semester: semester, courses: [], entries: [])
    }

    /// 已解析完、等待确认的导入草稿。
    private static func makeImportDraftId(in store: AppStore, semesterId: UUID) -> UUID? {
        guard let draft = try? store.createImportDraft(
            semesterId: semesterId,
            sourceKind: .pastedText,
            sourceName: "从教务系统粘贴"
        ) else { return nil }

        _ = try? store.parseImportSource(
            draftId: draft.id,
            text: """
            高等数学,周一,第1-2节,1-16周,教三201,王老师
            大学英语,周二,第3-4节,1-16周,外语楼305,李老师
            数据结构,周二,第5-6节,1-16周,计算机楼402,陈老师
            普通物理,周五,第3-4节,1-8周,理科楼101,赵老师
            """
        )

        return draft.id
    }
}
