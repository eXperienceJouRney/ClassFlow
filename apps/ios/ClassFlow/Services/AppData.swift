import Foundation

struct AppData: Codable, Hashable, Sendable {

    /// 快照格式版本；读取旧版本文件时缺省字段由宽容解码补齐。
    static let currentSchemaVersion = 3

    var schemaVersion: Int
    var currentSemesterId: UUID?
    var semesters: [Semester]
    var courses: [Course]
    var scheduleEntries: [ScheduleEntry]
    var periodTimes: [ClassPeriodTime]
    var tasks: [CourseTask]
    var memos: [Memo]
    var importDrafts: [ImportDraft]
    var preferences: AppPreferences

    init(
        schemaVersion: Int = AppData.currentSchemaVersion,
        currentSemesterId: UUID? = nil,
        semesters: [Semester] = [],
        courses: [Course] = [],
        scheduleEntries: [ScheduleEntry] = [],
        periodTimes: [ClassPeriodTime] = [],
        tasks: [CourseTask] = [],
        memos: [Memo] = [],
        importDrafts: [ImportDraft] = [],
        preferences: AppPreferences = .default
    ) {
        self.schemaVersion = schemaVersion
        self.currentSemesterId = currentSemesterId
        self.semesters = semesters
        self.courses = courses
        self.scheduleEntries = scheduleEntries
        self.periodTimes = periodTimes
        self.tasks = tasks
        self.memos = memos
        self.importDrafts = importDrafts
        self.preferences = preferences
    }

    static let empty = AppData()
}

extension AppData {

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case currentSemesterId
        case semesters
        case courses
        case scheduleEntries
        case periodTimes
        case tasks
        case memos
        case importDrafts
        case preferences
    }

    /// 宽容解码：缺少的集合字段按空集合补齐。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? AppData.currentSchemaVersion
        currentSemesterId = try container.decodeIfPresent(UUID.self, forKey: .currentSemesterId)
        semesters = try container.decodeIfPresent([Semester].self, forKey: .semesters) ?? []
        courses = try container.decodeIfPresent([Course].self, forKey: .courses) ?? []
        scheduleEntries = try container.decodeIfPresent([ScheduleEntry].self, forKey: .scheduleEntries) ?? []
        periodTimes = try container.decodeIfPresent([ClassPeriodTime].self, forKey: .periodTimes) ?? []
        tasks = try container.decodeIfPresent([CourseTask].self, forKey: .tasks) ?? []
        memos = try container.decodeIfPresent([Memo].self, forKey: .memos) ?? []
        importDrafts = try container.decodeIfPresent([ImportDraft].self, forKey: .importDrafts) ?? []
        preferences = try container.decodeIfPresent(AppPreferences.self, forKey: .preferences) ?? .default
    }
}

extension AppData {

    /// 把快照升级到当前 schema 版本；旧数据里纯空白的 `location` / `note` 归一成 nil。
    func migrated() -> AppData {
        var copy = self

        if copy.schemaVersion < 3 {
            for index in copy.scheduleEntries.indices {
                copy.scheduleEntries[index].normalize()
            }
            for index in copy.tasks.indices {
                copy.tasks[index].normalize()
            }
        }

        for index in copy.importDrafts.indices {
            var draft = copy.importDrafts[index]
            guard draft.sourceKind == .image,
                  [.notStarted, .readyToCommit, .failed].contains(draft.status),
                  let semester = copy.semester(id: draft.semesterId) else { continue }
            var changed = false
            for entryIndex in draft.entries.indices {
                if draft.entries[entryIndex].applyLegacyDisplayedWeekDefault() {
                    draft.entries[entryIndex].revalidate(weekCount: semester.weekCount())
                    changed = true
                }
            }
            if changed {
                let selected = draft.selectedEntries
                draft.status = !selected.isEmpty && selected.allSatisfy { $0.status == .ready } ? .readyToCommit : .notStarted
                copy.importDrafts[index] = draft
            }
        }

        copy.schemaVersion = AppData.currentSchemaVersion
        return copy
    }
}

extension AppData {

    var currentSemester: Semester? {
        guard let currentSemesterId else { return nil }
        return semester(id: currentSemesterId)
    }

    func semester(id: UUID) -> Semester? {
        semesters.first { $0.id == id }
    }

    func course(id: UUID) -> Course? {
        courses.first { $0.id == id }
    }

    func courses(in semesterId: UUID) -> [Course] {
        courses.filter { $0.semesterId == semesterId }
    }

    func scheduleEntries(for courseId: UUID) -> [ScheduleEntry] {
        scheduleEntries.filter { $0.courseId == courseId }
    }

    func periodTimes(in semesterId: UUID) -> [ClassPeriodTime] {
        periodTimes
            .filter { $0.semesterId == semesterId }
            .sorted { $0.periodNumber < $1.periodNumber }
    }

    /// 学期实际生效的作息时间：保存过就用保存的，没保存过用内置默认作息。
    /// 需要区分用户显式配置与默认值时改用 `periodTimes(in:)`。
    func effectivePeriodTimes(in semesterId: UUID) -> [ClassPeriodTime] {
        let stored = periodTimes(in: semesterId)
        return stored.isEmpty ? ClassPeriodTime.defaults(for: semesterId) : stored
    }

    func tasks(for courseId: UUID) -> [CourseTask] {
        tasks.filter { $0.courseId == courseId }
    }

    func memos(for courseId: UUID) -> [Memo] {
        memos.filter { $0.courseId == courseId }
    }

    func timetable(for semesterId: UUID) -> Timetable? {
        guard let semester = semester(id: semesterId) else { return nil }
        return Timetable(
            semester: semester,
            courses: courses(in: semesterId),
            entries: scheduleEntries,
            periods: effectivePeriodTimes(in: semesterId)
        )
    }

    func importDraft(id: UUID) -> ImportDraft? {
        importDrafts.first { $0.id == id }
    }

    func importDrafts(in semesterId: UUID) -> [ImportDraft] {
        importDrafts
            .filter { $0.semesterId == semesterId }
            .sorted { $0.createdAt > $1.createdAt }
    }
}
