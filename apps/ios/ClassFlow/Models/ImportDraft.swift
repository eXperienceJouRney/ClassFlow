import Foundation

/// 导入来源。
enum ImportSourceKind: String, Codable, CaseIterable, Hashable, Sendable {

    case manualEntry
    case pastedText
    case file
    case image

    var displayName: String {
        switch self {
        case .manualEntry: "手动录入"
        case .pastedText: "粘贴文本"
        case .file: "文件导入"
        case .image: "图片导入"
        }
    }

    var detail: String {
        switch self {
        case .manualEntry: "一条一条填写课程安排"
        case .pastedText: "粘贴一段课表文本，由应用解析成候选记录"
        case .file: "选择 txt / csv / md 文本课表文件"
        case .image: "选择课表截图（识别能力尚未接入，见 OPEN-02）"
        }
    }

    /// 首版不提供自动识别。
    var requiresRecognizer: Bool { self == .image }
}

/// 草稿级提交结果。
enum ImportCommitStatus: String, Codable, CaseIterable, Hashable, Sendable {

    case notStarted
    case validating
    case readyToCommit
    case committing
    case succeeded
    case partiallySucceeded
    case failed
    case cancelled

    var displayName: String {
        switch self {
        case .notStarted: "尚未提交"
        case .validating: "正在校验"
        case .readyToCommit: "可以提交"
        case .committing: "正在提交"
        case .succeeded: "提交成功"
        case .partiallySucceeded: "部分成功"
        case .failed: "提交失败"
        case .cancelled: "已取消"
        }
    }

    var isFinished: Bool {
        switch self {
        case .succeeded, .partiallySucceeded, .failed, .cancelled: true
        case .notStarted, .validating, .readyToCommit, .committing: false
        }
    }
}

/// 导入草稿：不是正式课程数据，提交成功后才创建或关联正式业务数据。
struct ImportDraft: Identifiable, Hashable, Codable, Sendable {

    let id: UUID
    var semesterId: UUID
    var sourceKind: ImportSourceKind
    var sourceName: String?
    var status: ImportCommitStatus
    var entries: [ImportDraftEntry]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        semesterId: UUID,
        sourceKind: ImportSourceKind,
        sourceName: String? = nil,
        status: ImportCommitStatus = .notStarted,
        entries: [ImportDraftEntry] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.semesterId = semesterId
        self.sourceKind = sourceKind
        self.sourceName = sourceName
        self.status = status
        self.entries = entries
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension ImportDraft {

    var selectedEntries: [ImportDraftEntry] {
        entries.filter(\.isSelected)
    }

    var selectedCount: Int { selectedEntries.count }

    var readyCount: Int {
        entries.filter { $0.isSelected && $0.status == .ready }.count
    }

    var invalidCount: Int {
        entries.filter { $0.isSelected && $0.status == .invalid }.count
    }

    var needsCorrectionCount: Int {
        entries.filter { $0.isSelected && $0.status == .needsCorrection }.count
    }

    var committedCount: Int {
        entries.filter { $0.status == .committed }.count
    }

    var conflictEntryIds: Set<UUID> {
        Set(entries.flatMap(\.conflictIds))
    }

    var hasConflicts: Bool { !conflictEntryIds.isEmpty }

    /// 是否存在被勾选但尚不具备提交条件的记录。
    var hasUnsubmittableSelection: Bool {
        let blocked = entries.filter { $0.isSelected && !$0.status.allowsCommit && $0.status != .committed }
        return !blocked.isEmpty
    }

    func entry(id: UUID) -> ImportDraftEntry? {
        entries.first { $0.id == id }
    }

    mutating func replace(_ entry: ImportDraftEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
        updatedAt = Date()
    }

    mutating func removeEntry(id: UUID) {
        entries.removeAll { $0.id == id }
        updatedAt = Date()
    }

    var summaryText: String {
        var parts: [String] = ["共 \(entries.count) 条"]
        if selectedCount > 0 { parts.append("已选 \(selectedCount) 条") }
        if readyCount > 0 { parts.append("可提交 \(readyCount) 条") }
        if needsCorrectionCount > 0 { parts.append("待修正 \(needsCorrectionCount) 条") }
        if invalidCount > 0 { parts.append("不合法 \(invalidCount) 条") }
        if hasConflicts { parts.append("存在时间冲突") }
        return parts.joined(separator: " · ")
    }
}
