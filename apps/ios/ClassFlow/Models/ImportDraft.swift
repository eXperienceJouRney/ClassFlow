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
        case .image: "从相册或文件选择课表，默认使用 OCR，也可选择 AI 识别"
        }
    }

    /// 图片来源需要先运行所选的图片识别器。
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

/// 预览中的一门课程及其多条安排；仅为展示分组，不改变草稿记录或周次规则。
struct ImportDraftCourseGroup: Identifiable, Sendable {
    let id: UUID
    let courseName: String
    var entries: [ImportDraftEntry]

    var displayName: String { courseName.isEmpty ? "待填写课程名" : courseName }

    var classResolvedEntries: [ImportDraftEntry] {
        entries.filter { $0.imageReview?.requiresClassReview != true }
    }

    /// 课堂编号只在本课程内关联，不能跨课程把同号课堂视为同一组学生。
    var unresolvedClassGroups: [ImportDraftClassGroup] {
        var groups: [ImportDraftClassGroup] = []
        var indexes: [String: Int] = [:]
        for entry in entries where entry.imageReview?.requiresClassReview == true {
            let label = entry.imageReview?.classGroup?.normalizedOrNil
            let name = label == "课堂分组" ? nil : label
            if let name, let index = indexes[name] {
                groups[index].entries.append(entry)
            } else {
                if let name { indexes[name] = groups.count }
                groups.append(ImportDraftClassGroup(id: entry.id, name: name, entries: [entry]))
            }
        }
        // 课堂1、2、…、10按编号排序；缺少课堂信息的记录各自保留，不补猜所属课堂。
        return groups.sorted {
            if $0.name == nil, $1.name != nil { return false }
            if $0.name != nil, $1.name == nil { return true }
            let order = $0.displayName.localizedStandardCompare($1.displayName)
            return order == .orderedAscending || (order == .orderedSame
                && ($0.entries.first?.sourceIndex ?? 0) < ($1.entries.first?.sourceIndex ?? 0))
        }
    }
}

struct ImportDraftClassGroup: Identifiable, Sendable {
    let id: UUID
    let name: String?
    var entries: [ImportDraftEntry]

    var displayName: String { name ?? "课堂待核对" }
    var selectedCount: Int { entries.filter(\.isSelected).count }
    var isFullySelected: Bool { !entries.isEmpty && selectedCount == entries.count }
    var isPartiallySelected: Bool { selectedCount > 0 && !isFullySelected }
}

extension ImportDraft {

    /// 与提交时一致：仅按去除首尾空白的课程名分组，保留首次出现顺序。
    /// 尚未命名的记录分别展示，不能把多条未知课程默认视为同一门课。
    var courseGroups: [ImportDraftCourseGroup] {
        var groups: [ImportDraftCourseGroup] = []
        var indexes: [String: Int] = [:]
        for entry in entries {
            let name = entry.courseName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, let index = indexes[name] {
                groups[index].entries.append(entry)
            } else {
                if !name.isEmpty { indexes[name] = groups.count }
                groups.append(ImportDraftCourseGroup(id: entry.id, courseName: name, entries: [entry]))
            }
        }
        return groups
    }

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
        var parts: [String] = ["共 \(courseGroups.count) 门课程", "\(entries.count) 条安排"]
        if selectedCount > 0 { parts.append("已选 \(selectedCount) 条") }
        if readyCount > 0 { parts.append("可提交 \(readyCount) 条") }
        if needsCorrectionCount > 0 { parts.append("待修正 \(needsCorrectionCount) 条") }
        if invalidCount > 0 { parts.append("不合法 \(invalidCount) 条") }
        if hasConflicts { parts.append("存在时间冲突") }
        return parts.joined(separator: " · ")
    }
}
