import Foundation

enum DeletionStrategy: String, Codable, CaseIterable, Hashable, Sendable {

    case deleteRelated
    case detachRelated

    var displayName: String {
        switch self {
        case .deleteRelated: "同时删除关联记录"
        case .detachRelated: "解除关联（笔记只能删除）"
        }
    }
}

struct SemesterDeletionPreview: Hashable, Sendable {

    let semesterId: UUID
    let semesterName: String
    let courseCount: Int
    let scheduleEntryCount: Int
    let affectedTaskCount: Int
    let affectedMemoCount: Int

    var strategies: [DeletionStrategy] {
        affectedTaskCount > 0 ? [.deleteRelated, .detachRelated] : [.deleteRelated]
    }

    var summaryLines: [String] {
        [
            "将删除 \(courseCount) 门课程",
            "将删除 \(scheduleEntryCount) 条上课安排",
            affectedTaskCount > 0 ? "影响 \(affectedTaskCount) 个任务" : "没有受影响的任务",
            affectedMemoCount > 0 ? "将删除 \(affectedMemoCount) 条笔记" : "没有受影响的笔记",
        ]
    }
}

struct CourseDeletionPreview: Hashable, Sendable {

    let courseId: UUID
    let courseName: String
    let scheduleEntryCount: Int
    let affectedTaskCount: Int
    let affectedMemoCount: Int

    var strategies: [DeletionStrategy] {
        affectedTaskCount > 0 ? [.deleteRelated, .detachRelated] : [.deleteRelated]
    }
}
