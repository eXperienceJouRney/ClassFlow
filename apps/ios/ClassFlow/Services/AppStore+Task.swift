import Foundation

extension AppStore {

    var allTasks: [CourseTask] {
        data.tasks.sorted(by: Self.taskOrder)
    }

    func task(id: UUID) -> CourseTask? {
        data.tasks.first { $0.id == id }
    }

    func tasks(forCourseId courseId: UUID) -> [CourseTask] {
        data.tasks(for: courseId).sorted(by: Self.taskOrder)
    }

    func tasks(inSemesterId semesterId: UUID) -> [CourseTask] {
        let courseIds = Set(data.courses(in: semesterId).map(\.id))
        return data.tasks
            .filter { $0.courseId.map(courseIds.contains) ?? true }
            .sorted(by: Self.taskOrder)
    }

    func unassignedTasks() -> [CourseTask] {
        data.tasks.filter { $0.courseId == nil }.sorted(by: Self.taskOrder)
    }

    @discardableResult
    func createTask(
        title: String,
        courseId: UUID? = nil,
        dueDate: CalendarDate? = nil,
        dueTime: TimeOfDay? = nil,
        note: String? = nil
    ) throws -> CourseTask {
        if let courseId, data.course(id: courseId) == nil {
            throw AppError.notFound(entity: "课程")
        }

        var task = CourseTask(
            title: title,
            courseId: courseId,
            dueDate: dueDate,
            dueTime: dueTime,
            note: note
        )
        task.normalize()
        try task.appValidated()

        try commit { $0.tasks.append(task) }

        return task
    }

    func updateTask(
        id: UUID,
        title: String,
        courseId: UUID?,
        dueDate: CalendarDate?,
        dueTime: TimeOfDay?,
        note: String? = nil
    ) throws {
        guard var task = self.task(id: id) else {
            throw AppError.notFound(entity: "任务")
        }
        if let courseId, data.course(id: courseId) == nil {
            throw AppError.notFound(entity: "课程")
        }

        task.title = title
        task.courseId = courseId
        task.dueDate = dueDate
        task.dueTime = dueTime
        task.note = note
        task.normalize()
        task.updatedAt = Date()
        try task.appValidated()

        try commit { data in
            guard let index = data.tasks.firstIndex(where: { $0.id == id }) else { return }
            data.tasks[index] = task
        }
    }

    func setTaskStatus(id: UUID, to status: TaskStatus) throws {
        guard var task = self.task(id: id) else {
            throw AppError.notFound(entity: "任务")
        }

        do {
            try task.transition(to: status)
        } catch let error as ValidationError {
            throw AppError.validation(error)
        }

        task.updatedAt = Date()

        try commit { data in
            guard let index = data.tasks.firstIndex(where: { $0.id == id }) else { return }
            data.tasks[index] = task
        }
    }

    func reopenTask(id: UUID) throws {
        guard var task = self.task(id: id) else {
            throw AppError.notFound(entity: "任务")
        }

        task.reopen()
        task.updatedAt = Date()

        try commit { data in
            guard let index = data.tasks.firstIndex(where: { $0.id == id }) else { return }
            data.tasks[index] = task
        }
    }

    func deleteTask(id: UUID) throws {
        guard task(id: id) != nil else {
            throw AppError.notFound(entity: "任务")
        }

        try commit { $0.tasks.removeAll { $0.id == id } }
    }

    private static func taskOrder(_ lhs: CourseTask, _ rhs: CourseTask) -> Bool {
        switch (lhs.dueDate, rhs.dueDate) {
        case let (left?, right?):
            if left != right { return left < right }

            let leftMinutes = lhs.dueTime?.minutesFromMidnight ?? Int.max
            let rightMinutes = rhs.dueTime?.minutesFromMidnight ?? Int.max
            if leftMinutes != rightMinutes { return leftMinutes < rightMinutes }

            return lhs.title < rhs.title

        case (nil, _?):
            return false

        case (_?, nil):
            return true

        case (nil, nil):
            return lhs.title < rhs.title
        }
    }
}
