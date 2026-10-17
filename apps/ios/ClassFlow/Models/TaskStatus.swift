import Foundation

enum TaskStatus: String, Codable, CaseIterable, Hashable, Sendable {

    case todo
    case inProgress
    case completed
    case cancelled
}

extension TaskStatus {

    var allowedNextStates: Set<TaskStatus> {
        switch self {
        case .todo: [.inProgress, .completed, .cancelled]
        case .inProgress: [.completed, .cancelled]
        case .completed, .cancelled: []
        }
    }

    func canTransition(to next: TaskStatus) -> Bool {
        allowedNextStates.contains(next)
    }

    func transitioned(to next: TaskStatus) throws -> TaskStatus {
        guard canTransition(to: next) else {
            throw ValidationError.illegalStatusTransition(from: self, to: next)
        }
        return next
    }

    var isTerminal: Bool { allowedNextStates.isEmpty }

    var isOpen: Bool { self == .todo || self == .inProgress }

    var reopened: TaskStatus { .todo }

    var displayName: String {
        switch self {
        case .todo: "待办"
        case .inProgress: "进行中"
        case .completed: "已完成"
        case .cancelled: "已取消"
        }
    }
}
