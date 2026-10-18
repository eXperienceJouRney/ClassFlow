import Foundation
import Observation

// MARK: - 状态
@MainActor
@Observable
final class AppStore {

    private let store: AppDataStore

    /// 被观察存储的包装；该类型不得实现 `Equatable`，否则仅改字段的写入不会触发观察通知。
    private struct Snapshot {
        var value: AppData
    }

    private var snapshot: Snapshot

    var data: AppData { snapshot.value }

    private(set) var loadErrorMessage: String?

    /// 数据版本号：每次成功写入或重新加载后 +1。
    /// 供「数据一变就要重算」的观察者使用（课程时间修改、课程取消等字段级改动
    /// 不会改变 `AppData` 的相等性，不能只靠 `onChange(of: data)`）。
    private(set) var revision = 0

    init(store: AppDataStore? = nil) {
        let store = store ?? InMemoryDataStore()
        self.store = store

        do {
            self.snapshot = Snapshot(value: try store.load())
            self.loadErrorMessage = nil
        } catch {
            self.snapshot = Snapshot(value: .empty)
            self.loadErrorMessage = String(describing: error)
        }

        store.repairWidgetSnapshotIfNeeded(self.snapshot.value)
    }
}

// MARK: - 写入
extension AppStore {

    func commit(_ mutate: (inout AppData) -> Void) throws {
        var next = snapshot.value
        mutate(&next)

        do {
            try store.save(next)
        } catch {
            throw AppError.persistenceFailed(reason: String(describing: error))
        }

        snapshot = Snapshot(value: next)
        revision += 1
    }

    /// 重新从磁盘加载最新数据；主 App 回前台时须调用，以免覆盖其他进程的写入。
    func reload() {
        do {
            snapshot = Snapshot(value: try store.load())
            loadErrorMessage = nil
            revision += 1
        } catch {
            loadErrorMessage = String(describing: error)
        }
    }
}

// MARK: - 学期查询
extension AppStore {

    var semesters: [Semester] {
        data.semesters.sorted { $0.startDate > $1.startDate }
    }

    var currentSemester: Semester? {
        data.currentSemester
    }

    @discardableResult
    func createSemester(
        name: String,
        startDate: CalendarDate,
        endDate: CalendarDate
    ) throws -> Semester {
        let semester = Semester(name: name, startDate: startDate, endDate: endDate)
        try semester.appValidated()

        try commit { data in
            data.semesters.append(semester)
            if data.currentSemesterId == nil {
                data.currentSemesterId = semester.id
            }
        }

        return semester
    }

    func updateSemester(
        id: UUID,
        name: String,
        startDate: CalendarDate,
        endDate: CalendarDate
    ) throws {
        guard var semester = data.semester(id: id) else {
            throw AppError.notFound(entity: "学期")
        }

        semester.name = name
        semester.startDate = startDate
        semester.endDate = endDate
        semester.updatedAt = Date()
        try semester.appValidated()

        try commit { data in
            guard let index = data.semesters.firstIndex(where: { $0.id == id }) else { return }
            data.semesters[index] = semester
        }
    }

    func setCurrentSemester(id: UUID) throws {
        guard data.semester(id: id) != nil else {
            throw AppError.notFound(entity: "学期")
        }
        try commit { $0.currentSemesterId = id }
    }

    func semesterDeletionPreview(id: UUID) -> SemesterDeletionPreview? {
        guard let semester = data.semester(id: id) else { return nil }

        let courseIds = Set(data.courses(in: id).map(\.id))

        return SemesterDeletionPreview(
            semesterId: id,
            semesterName: semester.name,
            courseCount: courseIds.count,
            scheduleEntryCount: data.scheduleEntries.filter { courseIds.contains($0.courseId) }.count,
            affectedTaskCount: data.tasks.filter { $0.courseId.map(courseIds.contains) ?? false }.count,
            affectedMemoCount: data.memos.filter { courseIds.contains($0.courseId) }.count
        )
    }

    func deleteSemester(id: UUID, strategy: DeletionStrategy) throws {
        guard data.semester(id: id) != nil else {
            throw AppError.notFound(entity: "学期")
        }

        try commit { data in
            let courseIds = Set(data.courses(in: id).map(\.id))

            data.courses.removeAll { courseIds.contains($0.id) }
            data.scheduleEntries.removeAll { courseIds.contains($0.courseId) }
            data.periodTimes.removeAll { $0.semesterId == id }
            data.memos.removeAll { courseIds.contains($0.courseId) }

            switch strategy {
            case .deleteRelated:
                data.tasks.removeAll { $0.courseId.map(courseIds.contains) ?? false }
            case .detachRelated:
                for index in data.tasks.indices {
                    guard let courseId = data.tasks[index].courseId, courseIds.contains(courseId) else { continue }
                    data.tasks[index].courseId = nil
                }
            }

            data.semesters.removeAll { $0.id == id }

            if data.currentSemesterId == id {
                data.currentSemesterId = data.semesters.first?.id
            }
        }
    }
}

// MARK: - 作息时间
extension AppStore {

    func periodTimes(in semesterId: UUID) -> [ClassPeriodTime] {
        data.periodTimes(in: semesterId)
    }

    /// 学期实际生效的作息时间（没保存过就是内置默认作息）。
    func effectivePeriodTimes(in semesterId: UUID) -> [ClassPeriodTime] {
        data.effectivePeriodTimes(in: semesterId)
    }

    func setPeriodTimes(_ inputs: [ClassPeriodInput], for semesterId: UUID) throws {
        guard data.semester(id: semesterId) != nil else {
            throw AppError.notFound(entity: "学期")
        }

        var seen = Set<Int>()
        for input in inputs where !seen.insert(input.periodNumber).inserted {
            throw AppError.validation(.duplicatePeriodNumber(periodNumber: input.periodNumber))
        }

        let periods = inputs.map { input in
            ClassPeriodTime(
                semesterId: semesterId,
                periodNumber: input.periodNumber,
                startTime: input.startTime,
                endTime: input.endTime
            )
        }

        for period in periods {
            try period.appValidated()
        }

        try commit { data in
            data.periodTimes.removeAll { $0.semesterId == semesterId }
            data.periodTimes.append(contentsOf: periods)
        }
    }
}

// MARK: - 课表查询
extension AppStore {

    func timetable(for semesterId: UUID) -> Timetable? {
        data.timetable(for: semesterId)
    }

    func currentTimetable() -> Timetable? {
        guard let semesterId = data.currentSemesterId else { return nil }
        return data.timetable(for: semesterId)
    }

    func classes(
        on date: CalendarDate,
        in semesterId: UUID,
        calendar: Calendar = .current
    ) -> [ClassOccurrence] {
        data.timetable(for: semesterId)?.classes(on: date, calendar: calendar) ?? []
    }

    /// 当前正在上的课；没有正在上的课（或作息没配好）时为 nil。
    func currentClassSession(
        at moment: Date = Date(),
        calendar: Calendar = .current
    ) -> ClassSession? {
        currentTimetable()?.currentSession(at: moment, calendar: calendar)
    }

    /// 这一节课之后的那一节；可以跨天，学期内没有后续课程时为 nil。
    func nextClassSession(
        after session: ClassSession,
        calendar: Calendar = .current
    ) -> ClassSession? {
        currentTimetable()?.nextSession(after: session, calendar: calendar)
    }
}
