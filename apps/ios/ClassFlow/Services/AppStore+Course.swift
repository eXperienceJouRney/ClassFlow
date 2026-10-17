import Foundation

extension AppStore {

    func courses(in semesterId: UUID) -> [Course] {
        data.courses(in: semesterId).sorted { $0.name < $1.name }
    }

    func course(id: UUID) -> Course? {
        data.course(id: id)
    }

    func scheduleEntries(for courseId: UUID) -> [ScheduleEntry] {
        data.scheduleEntries(for: courseId).sorted {
            if $0.weekday != $1.weekday { return $0.weekday.rawValue < $1.weekday.rawValue }
            return $0.time.displayText < $1.time.displayText
        }
    }

    @discardableResult
    func createCourse(
        semesterId: UUID,
        name: String,
        teacher: String? = nil,
        location: String? = nil,
        color: CourseColor? = nil,
        scheduleEntries: [ScheduleEntryInput] = []
    ) throws -> Course {
        guard data.semester(id: semesterId) != nil else {
            throw AppError.notFound(entity: "学期")
        }

        var course = Course(
            semesterId: semesterId,
            name: name,
            teacher: teacher,
            location: location,
            color: color
        )
        course.normalize()
        try course.appValidated()

        let entries = try makeEntries(scheduleEntries, courseId: course.id)

        try commit { data in
            data.courses.append(course)
            data.scheduleEntries.append(contentsOf: entries)
        }

        return course
    }

    /// 更新课程；`semesterId` 非空时把课程挪到该学期。
    func updateCourse(
        id: UUID,
        name: String,
        teacher: String?,
        location: String?,
        color: CourseColor?,
        scheduleEntries: [ScheduleEntryInput],
        semesterId: UUID? = nil
    ) throws {
        guard var course = data.course(id: id) else {
            throw AppError.notFound(entity: "课程")
        }

        if let semesterId {
            guard data.semester(id: semesterId) != nil else {
                throw AppError.notFound(entity: "学期")
            }
            course.semesterId = semesterId
        }

        course.name = name
        course.teacher = teacher
        course.location = location
        course.color = color
        course.normalize()
        course.updatedAt = Date()
        try course.appValidated()

        let entries = try makeEntries(scheduleEntries, courseId: id)

        try commit { data in
            guard let index = data.courses.firstIndex(where: { $0.id == id }) else { return }
            data.courses[index] = course
            data.scheduleEntries.removeAll { $0.courseId == id }
            data.scheduleEntries.append(contentsOf: entries)
        }
    }

    func courseDeletionPreview(id: UUID) -> CourseDeletionPreview? {
        guard let course = data.course(id: id) else { return nil }

        return CourseDeletionPreview(
            courseId: id,
            courseName: course.name,
            scheduleEntryCount: data.scheduleEntries(for: id).count,
            affectedTaskCount: data.tasks(for: id).count,
            affectedMemoCount: data.memos(for: id).count
        )
    }

    func deleteCourse(id: UUID, strategy: DeletionStrategy) throws {
        guard data.course(id: id) != nil else {
            throw AppError.notFound(entity: "课程")
        }

        try commit { data in
            data.courses.removeAll { $0.id == id }
            data.scheduleEntries.removeAll { $0.courseId == id }
            data.memos.removeAll { $0.courseId == id }

            switch strategy {
            case .deleteRelated:
                data.tasks.removeAll { $0.courseId == id }
            case .detachRelated:
                for index in data.tasks.indices where data.tasks[index].courseId == id {
                    data.tasks[index].courseId = nil
                }
            }
        }
    }

    private func makeEntries(_ inputs: [ScheduleEntryInput], courseId: UUID) throws -> [ScheduleEntry] {
        var entries: [ScheduleEntry] = []

        for input in inputs {
            var entry = input.makeEntry(courseId: courseId)
            entry.normalize()
            try entry.appValidated()
            entries.append(entry)
        }

        return entries
    }
}
