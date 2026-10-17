import Foundation

struct CourseTask: Identifiable, Hashable, Codable, Sendable, Validatable {

    let id: UUID
    var title: String
    var courseId: UUID?
    var dueDate: CalendarDate?
    var dueTime: TimeOfDay?
    /// 备注，选填。
    var note: String?
    var status: TaskStatus
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        courseId: UUID? = nil,
        dueDate: CalendarDate? = nil,
        dueTime: TimeOfDay? = nil,
        note: String? = nil,
        status: TaskStatus = .todo,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.courseId = courseId
        self.dueDate = dueDate
        self.dueTime = dueTime
        self.note = note
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension CourseTask {

    var validationErrors: [ValidationError] {
        var errors: [ValidationError] = []

        if title.isBlank {
            errors.append(.requiredFieldEmpty(field: "任务标题"))
        }
        if dueTime != nil && dueDate == nil {
            errors.append(.dueTimeWithoutDate)
        }

        return errors
    }
}

extension CourseTask {

    mutating func normalize() {
        note = note?.normalizedOrNil
    }

    mutating func setDueDate(_ date: CalendarDate?) {
        dueDate = date
        if date == nil { dueTime = nil }
    }

    mutating func setDueTime(_ time: TimeOfDay?) throws {
        if time != nil && dueDate == nil {
            throw ValidationError.dueTimeWithoutDate
        }
        dueTime = time
    }

    mutating func transition(to next: TaskStatus) throws {
        status = try status.transitioned(to: next)
    }

    mutating func reopen() {
        status = status.reopened
    }

    func dueInstant(calendar: Calendar = .current) -> Date? {
        guard let dueDate else { return nil }

        if let dueTime {
            return dueDate.instant(at: dueTime, in: calendar)
        }

        guard let dayStart = dueDate.startOfDay(in: calendar) else { return nil }
        return calendar.date(byAdding: .day, value: 1, to: dayStart)
    }

    func isOverdue(at now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard status.isOpen, let deadline = dueInstant(calendar: calendar) else { return false }
        return now > deadline
    }
}

extension CourseTask {

    static func == (lhs: CourseTask, rhs: CourseTask) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
