import Foundation

enum CourseColor: String, Codable, CaseIterable, Hashable, Sendable {
    case blue
    case green
    case orange
    case purple
    case pink
    case teal
    case red
    case gray
}

struct Course: Identifiable, Hashable, Codable, Sendable, Validatable {

    let id: UUID
    var semesterId: UUID
    var name: String
    var teacher: String?
    var location: String?
    var color: CourseColor?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        semesterId: UUID,
        name: String,
        teacher: String? = nil,
        location: String? = nil,
        color: CourseColor? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.semesterId = semesterId
        self.name = name
        self.teacher = teacher
        self.location = location
        self.color = color
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Course {

    var validationErrors: [ValidationError] {
        var errors: [ValidationError] = []

        if name.isBlank {
            errors.append(.requiredFieldEmpty(field: "课程名称"))
        }

        return errors
    }
}

extension Course {

    mutating func normalize() {
        teacher = teacher?.normalizedOrNil
        location = location?.normalizedOrNil
    }
}

extension Course {

    static func == (lhs: Course, rhs: Course) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
