import Foundation

struct Memo: Identifiable, Hashable, Codable, Sendable, Validatable {

    let id: UUID
    var courseId: UUID
    var title: String?
    var content: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        courseId: UUID,
        title: String? = nil,
        content: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.courseId = courseId
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Memo {

    var validationErrors: [ValidationError] {
        var errors: [ValidationError] = []

        if content.isBlank {
            errors.append(.requiredFieldEmpty(field: "笔记内容"))
        }

        return errors
    }

    mutating func normalize() {
        title = title?.normalizedOrNil
    }
}

extension Memo {

    /// 笔记正文的第一行（跳过空行，去掉首尾空白）。
    var firstLine: String? {
        content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    /// 列表显示的标题：显式标题优先，否则取正文第一行，都没有时为「无标题」。
    var displayTitle: String {
        if let title, !title.isBlank { return title }
        return firstLine ?? "无标题"
    }

    /// 列表里的摘要：正文去掉被当作标题的那一行后的剩余内容。
    var bodyPreview: String {
        var lines = content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        if title == nil || title?.isBlank == true {
            lines.removeAll { $0.isEmpty }
            if !lines.isEmpty { lines.removeFirst() }
        }

        return lines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}

extension Memo {

    static func == (lhs: Memo, rhs: Memo) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
