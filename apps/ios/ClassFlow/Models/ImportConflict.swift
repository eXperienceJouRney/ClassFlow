import Foundation

/// 导入冲突类型。
enum ImportConflictKind: String, Codable, CaseIterable, Hashable, Sendable {

    /// 与目标学期已有的上课安排时间重叠。
    case existingSchedule
    /// 与同一草稿中的另一条候选记录时间重叠。
    case withinDraft
    /// 目标学期内已存在同名课程，同名即同一门课。
    case sameNameCourse

    var displayName: String {
        switch self {
        case .existingSchedule: "与已有课程时间重叠"
        case .withinDraft: "草稿内部时间重叠"
        case .sameNameCourse: "已存在同名课程"
        }
    }

    /// 是否属于需要用户确认的时间冲突（同名课程只是提示，不计算为时间冲突）。
    var isTimeOverlap: Bool { self != .sameNameCourse }
}

/// 导入冲突：只被展示，由用户决定继续导入或跳过相关记录。
struct ImportConflict: Identifiable, Hashable, Codable, Sendable {

    let id: UUID
    var draftId: UUID
    var kind: ImportConflictKind
    var firstEntryId: UUID
    var secondEntryId: UUID?
    var secondCourseId: UUID?
    var firstLabel: String
    var secondLabel: String
    var weekday: Weekday?
    var overlapDescription: String
    var weeksDescription: String

    init(
        id: UUID = UUID(),
        draftId: UUID,
        kind: ImportConflictKind,
        firstEntryId: UUID,
        secondEntryId: UUID? = nil,
        secondCourseId: UUID? = nil,
        firstLabel: String,
        secondLabel: String,
        weekday: Weekday? = nil,
        overlapDescription: String,
        weeksDescription: String = ""
    ) {
        self.id = id
        self.draftId = draftId
        self.kind = kind
        self.firstEntryId = firstEntryId
        self.secondEntryId = secondEntryId
        self.secondCourseId = secondCourseId
        self.firstLabel = firstLabel
        self.secondLabel = secondLabel
        self.weekday = weekday
        self.overlapDescription = overlapDescription
        self.weeksDescription = weeksDescription
    }
}

extension ImportConflict {

    var summary: String {
        let day = weekday?.shortName ?? ""
        let weeks = weeksDescription.isEmpty ? "" : "（\(weeksDescription)）"
        return "\(day)\(weeks) \(firstLabel) ↔ \(secondLabel)：\(overlapDescription)"
    }
}

/// 冲突处理选择。
enum ImportConflictStrategy: String, Codable, CaseIterable, Hashable, Sendable {

    /// 保留全部选中记录（冲突仅提示，不丢弃内容）。
    case keepAll
    /// 跳过存在时间冲突的记录，只导入其余记录。
    case skipConflicting

    var displayName: String {
        switch self {
        case .keepAll: "全部导入（冲突仅提示）"
        case .skipConflicting: "跳过冲突记录"
        }
    }
}

/// 导入提交结果。
struct ImportCommitResult: Hashable, Codable, Sendable {

    let draftId: UUID
    let status: ImportCommitStatus
    /// 本次导入涉及的课程：既有新建的课程，也有被并入的学期内已有同名课程。
    let committedCourseIds: [UUID]
    let committedEntryIds: [UUID]
    let skippedEntryIds: [UUID]
    let failedEntryIds: [UUID]
    let issues: [ImportCommitFailure]

    var succeeded: Bool { status == .succeeded }

    var summaryText: String {
        switch status {
        case .succeeded:
            "已导入 \(committedEntryIds.count) 条记录，涉及 \(committedCourseIds.count) 门课程"
        case .partiallySucceeded:
            "部分导入：成功 \(committedEntryIds.count) 条，失败 \(failedEntryIds.count) 条"
        case .failed:
            "导入失败，未写入任何课程"
        case .cancelled:
            "已取消导入，未写入任何课程"
        case .notStarted, .validating, .readyToCommit, .committing:
            status.displayName
        }
    }
}

/// 提交阶段失败的单条记录说明。
struct ImportCommitFailure: Hashable, Codable, Sendable {

    let entryId: UUID
    let code: String
    let message: String
}
