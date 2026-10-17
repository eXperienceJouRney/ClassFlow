import Foundation

extension AppStore {

    func memos(forCourseId courseId: UUID) -> [Memo] {
        data.memos(for: courseId).sorted { $0.updatedAt > $1.updatedAt }
    }

    func memo(id: UUID) -> Memo? {
        data.memos.first { $0.id == id }
    }

    @discardableResult
    func createMemo(
        courseId: UUID,
        title: String? = nil,
        content: String
    ) throws -> Memo {
        guard data.course(id: courseId) != nil else {
            throw AppError.notFound(entity: "课程")
        }

        var memo = Memo(courseId: courseId, title: title, content: content)
        memo.normalize()
        try memo.appValidated()

        try commit { $0.memos.append(memo) }

        return memo
    }

    func updateMemo(id: UUID, title: String?, content: String, courseId: UUID? = nil) throws {
        guard var memo = self.memo(id: id) else {
            throw AppError.notFound(entity: "笔记")
        }
        if let courseId, data.course(id: courseId) == nil {
            throw AppError.notFound(entity: "课程")
        }

        memo.title = title
        memo.content = content
        if let courseId { memo.courseId = courseId }
        memo.updatedAt = Date()
        memo.normalize()
        try memo.appValidated()

        try commit { data in
            guard let index = data.memos.firstIndex(where: { $0.id == id }) else { return }
            data.memos[index] = memo
        }
    }

    func deleteMemo(id: UUID) throws {
        guard memo(id: id) != nil else {
            throw AppError.notFound(entity: "笔记")
        }

        try commit { $0.memos.removeAll { $0.id == id } }
    }
}
