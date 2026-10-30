import Foundation

/// 导入记录状态；仅 `ready` 允许提交，`committed` 不允许重复创建课程。
enum ImportEntryStatus: String, Codable, CaseIterable, Hashable, Sendable {

    case pending
    case parsed
    case needsCorrection
    case invalid
    case ready
    case committed
    case skipped
}

extension ImportEntryStatus {

    var displayName: String {
        switch self {
        case .pending: "待解析"
        case .parsed: "已解析"
        case .needsCorrection: "待修正"
        case .invalid: "不合法"
        case .ready: "可提交"
        case .committed: "已提交"
        case .skipped: "已跳过"
        }
    }

    /// 是否允许提交：仅 `ready` 为 true。
    var allowsCommit: Bool { self == .ready }

    var isTerminal: Bool { self == .committed }

    /// 允许的状态转换目标集合。
    var allowedNextStates: Set<ImportEntryStatus> {
        switch self {
        case .pending: [.parsed, .invalid, .skipped]
        case .parsed: [.needsCorrection, .ready, .invalid, .skipped]
        case .needsCorrection: [.ready, .invalid, .skipped]
        case .invalid: [.needsCorrection, .skipped]
        case .ready: [.skipped, .committed]
        case .committed: []
        case .skipped: [.needsCorrection]
        }
    }

    func canTransition(to next: ImportEntryStatus) -> Bool {
        allowedNextStates.contains(next)
    }
}

/// 导入状态转换错误。
enum ImportStateError: Error, Equatable, Sendable {

    case illegalTransition(from: ImportEntryStatus, to: ImportEntryStatus)

    var message: String {
        switch self {
        case let .illegalTransition(from, to):
            "导入记录状态不能从「\(from.displayName)」直接变为「\(to.displayName)」"
        }
    }
}

/// 结构化校验问题。
struct ValidationIssue: Hashable, Codable, Sendable {

    let code: String
    let field: String?
    let message: String

    init(code: String, field: String? = nil, message: String) {
        self.code = code
        self.field = field
        self.message = message
    }

    /// 仅缺少可补充信息时为 true；违反数据约束为 false。
    var isMissingInformation: Bool {
        ImportIssueCode(rawValue: code)?.isMissingInformation ?? false
    }
}

enum ImportIssueCode: String, Codable, CaseIterable, Hashable, Sendable {

    case blankCourseName = "IMPORT_BLANK_COURSE_NAME"
    case missingWeekday = "IMPORT_MISSING_WEEKDAY"
    case missingTime = "IMPORT_MISSING_TIME"
    case incompletePeriod = "IMPORT_INCOMPLETE_PERIOD"
    case incompleteTime = "IMPORT_INCOMPLETE_TIME"
    case invalidPeriodOrder = "IMPORT_INVALID_PERIOD_ORDER"
    case invalidTimeOrder = "IMPORT_INVALID_TIME_ORDER"
    case invalidWeekRule = "IMPORT_INVALID_WEEK_RULE"
    case weekOutOfSemesterRange = "IMPORT_WEEK_OUT_OF_SEMESTER_RANGE"
    case imageWeeksUnconfirmed = "IMPORT_IMAGE_WEEKS_UNCONFIRMED"

    var isMissingInformation: Bool {
        switch self {
        case .missingWeekday, .missingTime, .imageWeeksUnconfirmed:
            true
        case .blankCourseName, .incompletePeriod, .incompleteTime,
             .invalidPeriodOrder, .invalidTimeOrder,
             .invalidWeekRule, .weekOutOfSemesterRange:
            false
        }
    }
}

/// 导入记录的时间权威来源。
enum ImportTimeAuthority: String, Codable, Hashable, Sendable {

    case period
    case custom
}

/// 图片识别的核对提示；可选字段保证旧草稿无需迁移即可读取。
struct ImportImageReview: Hashable, Codable, Sendable {
    var notes: [String]
    var requiresWeekConfirmation: Bool
    var selectedClassName: String? = nil
    var classGroup: String? = nil
    var requiresClassReview: Bool? = nil

    static let classReviewMessage = "部分课程无法对应到班级，默认不导入，请核对原图后按需勾选、修改。"
}

extension ImportDraftEntry {
    /// 兼容旧版图片草稿：当时已识别的表头周数只保存在固定格式的核对提示中。
    /// 仅迁移尚未填写周规则的普通课程，保留用户设置与非本周记录。
    @discardableResult
    mutating func applyLegacyDisplayedWeekDefault() -> Bool {
        guard status != .committed, weekRule == WeekRule(),
              let review = imageReview, review.requiresWeekConfirmation,
              rawPayload?.contains("非本周") != true,
              let regex = try? NSRegularExpression(pattern: #"^截图显示第([0-9]{1,2})周，完整上课周次未知，请在修改记录中选择并确认。$"#) else { return false }
        let weeks = review.notes.compactMap { note -> Int? in
            guard let match = regex.firstMatch(in: note, range: NSRange(note.startIndex..., in: note)),
                  let range = Range(match.range(at: 1), in: note) else { return nil }
            return Int(note[range])
        }
        guard Set(weeks).count == 1, let week = weeks.first, week >= 1 else { return false }
        weekRule = WeekRule(startWeek: week, endWeek: week)
        imageReview?.requiresWeekConfirmation = false
        imageReview?.notes = review.notes.map { note in
            regex.firstMatch(in: note, range: NSRange(note.startIndex..., in: note)) != nil
                ? "已按图片默认选择第\(week)周，仅导入这一周；需要时可修改周次。" : note
        }
        if errorCode == ImportIssueCode.imageWeeksUnconfirmed.rawValue {
            errorCode = nil
            errorMessage = nil
        }
        return true
    }
}

/// 导入流程中的单条候选记录，不是正式课程实体。
struct ImportDraftEntry: Identifiable, Hashable, Codable, Sendable {

    let id: UUID
    var draftId: UUID
    var sourceIndex: Int
    var rawPayload: String?
    var courseName: String
    var teacher: String?
    var location: String?
    var weekday: Weekday?
    var startPeriod: Int?
    var endPeriod: Int?
    var startTime: TimeOfDay?
    var endTime: TimeOfDay?
    var startWeek: Int?
    var endWeek: Int?
    var weekPattern: WeekPattern
    var customWeeks: [Int]
    var excludedWeeks: [Int]
    var isSelected: Bool
    var status: ImportEntryStatus
    var issues: [ValidationIssue]
    var conflictIds: [UUID]
    var matchedCourseId: UUID?
    var createdCourseId: UUID?
    var errorCode: String?
    var errorMessage: String?
    var imageReview: ImportImageReview?

    init(
        id: UUID = UUID(),
        draftId: UUID,
        sourceIndex: Int,
        rawPayload: String? = nil,
        courseName: String = "",
        teacher: String? = nil,
        location: String? = nil,
        weekday: Weekday? = nil,
        startPeriod: Int? = nil,
        endPeriod: Int? = nil,
        startTime: TimeOfDay? = nil,
        endTime: TimeOfDay? = nil,
        startWeek: Int? = nil,
        endWeek: Int? = nil,
        weekPattern: WeekPattern = .everyWeek,
        customWeeks: [Int] = [],
        excludedWeeks: [Int] = [],
        isSelected: Bool = true,
        status: ImportEntryStatus = .pending,
        issues: [ValidationIssue] = [],
        conflictIds: [UUID] = [],
        matchedCourseId: UUID? = nil,
        createdCourseId: UUID? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil,
        imageReview: ImportImageReview? = nil
    ) {
        self.id = id
        self.draftId = draftId
        self.sourceIndex = sourceIndex
        self.rawPayload = rawPayload
        self.courseName = courseName
        self.teacher = teacher
        self.location = location
        self.weekday = weekday
        self.startPeriod = startPeriod
        self.endPeriod = endPeriod
        self.startTime = startTime
        self.endTime = endTime
        self.startWeek = startWeek
        self.endWeek = endWeek
        self.weekPattern = weekPattern
        self.customWeeks = customWeeks
        self.excludedWeeks = excludedWeeks
        self.isSelected = isSelected
        self.status = status
        self.issues = issues
        self.conflictIds = conflictIds
        self.matchedCourseId = matchedCourseId
        self.createdCourseId = createdCourseId
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.imageReview = imageReview
    }
}

// MARK: - 派生字段

extension ImportDraftEntry {

    var weekRule: WeekRule {
        get {
            WeekRule(
                startWeek: startWeek,
                endWeek: endWeek,
                pattern: weekPattern,
                customWeeks: customWeeks,
                excludedWeeks: excludedWeeks
            )
        }
        set {
            startWeek = newValue.startWeek
            endWeek = newValue.endWeek
            weekPattern = newValue.pattern
            customWeeks = newValue.customWeeks
            excludedWeeks = newValue.excludedWeeks
        }
    }

    var periodPair: (start: Int, end: Int)? {
        guard let startPeriod, let endPeriod else { return nil }
        return (startPeriod, endPeriod)
    }

    var customPair: (start: TimeOfDay, end: TimeOfDay)? {
        guard let startTime, let endTime else { return nil }
        return (startTime, endTime)
    }

    var hasPeriodInformation: Bool { startPeriod != nil || endPeriod != nil }

    var hasCustomTimeInformation: Bool { startTime != nil || endTime != nil }

    /// 权威时间来源：两组同时存在时以课节为准。
    var timeAuthority: ImportTimeAuthority? {
        if periodPair != nil { return .period }
        if customPair != nil { return .custom }
        return nil
    }

    /// 提交时将写入的正式时间。
    var resolvedClassTime: ClassTime? {
        switch timeAuthority {
        case .period:
            guard let pair = periodPair else { return nil }
            return ClassTime.period(start: pair.start, end: pair.end)
        case .custom:
            guard let pair = customPair else { return nil }
            return ClassTime.custom(start: pair.start, end: pair.end)
        case nil:
            return nil
        }
    }

    /// 学期未配置课节时间时，由识别出的钟点推导的课节配置候选值；无则 nil。
    var candidatePeriodTime: ClassPeriodInput? {
        guard timeAuthority == .period,
              let pair = periodPair,
              let times = customPair
        else { return nil }

        return ClassPeriodInput(
            periodNumber: pair.start,
            startTime: times.start,
            endTime: times.end
        )
    }

    var displayName: String {
        let trimmed = courseName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "（未命名记录）" : trimmed
    }

    var timeDescription: String {
        switch timeAuthority {
        case .period:
            guard let pair = periodPair else { return "未填写时间" }
            let text = pair.start == pair.end ? "第\(pair.start)节" : "第\(pair.start)-\(pair.end)节"
            if let times = customPair {
                return "\(text)（\(times.start.displayText)-\(times.end.displayText)）"
            }
            return text
        case .custom:
            guard let pair = customPair else { return "未填写时间" }
            return "\(pair.start.displayText)-\(pair.end.displayText)"
        case nil:
            return "未填写时间"
        }
    }
}

// MARK: - 校验与状态

extension ImportDraftEntry {

    /// 依据当前字段重新判定校验问题与状态，返回本次问题列表。
    @discardableResult
    mutating func revalidate(weekCount: Int) -> [ValidationIssue] {
        var problems: [ValidationIssue] = []
        let semesterWeekCount = max(weekCount, 0)

        if courseName.isBlank {
            problems.append(
                ValidationIssue(
                    code: ImportIssueCode.blankCourseName.rawValue,
                    field: "课程名称",
                    message: "「课程名称」不能为空"
                )
            )
        }

        if weekday == nil {
            problems.append(
                ValidationIssue(
                    code: ImportIssueCode.missingWeekday.rawValue,
                    field: "星期",
                    message: "缺少星期，无法确定课程安排在哪一天"
                )
            )
        }

        problems.append(contentsOf: timeIssues())
        problems.append(contentsOf: weekIssues(semesterWeekCount: semesterWeekCount))

        issues = problems

        if status != .committed && status != .skipped {
            if problems.isEmpty {
                status = .ready
            } else if problems.allSatisfy(\.isMissingInformation) {
                status = .needsCorrection
            } else {
                status = .invalid
            }
        }

        return problems
    }

    private func timeIssues() -> [ValidationIssue] {
        var problems: [ValidationIssue] = []

        if hasPeriodInformation && periodPair == nil {
            problems.append(
                ValidationIssue(
                    code: ImportIssueCode.incompletePeriod.rawValue,
                    field: "课节",
                    message: "课节必须同时给出起始节和结束节"
                )
            )
        }

        if hasCustomTimeInformation && customPair == nil {
            problems.append(
                ValidationIssue(
                    code: ImportIssueCode.incompleteTime.rawValue,
                    field: "钟点",
                    message: "自定时间必须同时给出开始和结束时刻"
                )
            )
        }

        if let pair = periodPair {
            if pair.start < 1 || pair.end < 1 {
                problems.append(
                    ValidationIssue(
                        code: ImportIssueCode.invalidPeriodOrder.rawValue,
                        field: "课节",
                        message: "课节编号必须大于 0"
                    )
                )
            } else if pair.start > pair.end {
                problems.append(
                    ValidationIssue(
                        code: ImportIssueCode.invalidPeriodOrder.rawValue,
                        field: "课节",
                        message: "起始课节 \(pair.start) 不能晚于结束课节 \(pair.end)"
                    )
                )
            }
        }

        if let pair = customPair, pair.start >= pair.end {
            problems.append(
                ValidationIssue(
                    code: ImportIssueCode.invalidTimeOrder.rawValue,
                    field: "钟点",
                    message: "开始时间必须早于结束时间"
                )
            )
        }

        if !hasPeriodInformation && !hasCustomTimeInformation {
            problems.append(
                ValidationIssue(
                    code: ImportIssueCode.missingTime.rawValue,
                    field: "时间",
                    message: "缺少上课时间，请填写课节或自定时间"
                )
            )
        }

        return problems
    }

    private func weekIssues(semesterWeekCount: Int) -> [ValidationIssue] {
        let rule = weekRule

        var problems = rule.validationErrors.map { error in
            ValidationIssue(
                code: ImportIssueCode.invalidWeekRule.rawValue,
                field: "周次",
                message: error.message
            )
        }

        if imageReview?.requiresWeekConfirmation == true {
            problems.append(ValidationIssue(
                code: ImportIssueCode.imageWeeksUnconfirmed.rawValue,
                field: "周次",
                message: "截图未显示完整上课周次，请修改记录并确认周次后再提交"
            ))
        }

        guard semesterWeekCount >= 1, problems.isEmpty else { return problems }

        let outOfRange = (rule.customWeeks + rule.excludedWeeks).filter { $0 > semesterWeekCount }
        if let week = outOfRange.min() {
            problems.append(
                ValidationIssue(
                    code: ImportIssueCode.weekOutOfSemesterRange.rawValue,
                    field: "周次",
                    message: "第 \(week) 周超出该学期的 \(semesterWeekCount) 周"
                )
            )
        } else if let endWeek = rule.endWeek, endWeek > semesterWeekCount {
            problems.append(
                ValidationIssue(
                    code: ImportIssueCode.weekOutOfSemesterRange.rawValue,
                    field: "周次",
                    message: "结束周 \(endWeek) 超出该学期的 \(semesterWeekCount) 周"
                )
            )
        }

        return problems
    }
}

// MARK: - 状态转换

extension ImportDraftEntry {

    func canTransition(to next: ImportEntryStatus) -> Bool {
        status.canTransition(to: next)
    }

    mutating func transition(to next: ImportEntryStatus) throws {
        guard canTransition(to: next) else {
            throw ImportStateError.illegalTransition(from: status, to: next)
        }
        status = next
    }

    /// 解析成功后由 `pending` 进入 `parsed`；其他状态保持不变。
    mutating func markParsed() {
        guard status == .pending else { return }
        status = .parsed
    }

    /// 设置勾选状态；取消勾选时尽量转为 `skipped`，重新勾选后重新校验。
    mutating func applySelection(_ selected: Bool, weekCount: Int) {
        isSelected = selected

        if !selected {
            if canTransition(to: .skipped) {
                status = .skipped
            }
            return
        }

        if status == .skipped {
            status = .needsCorrection
        }
        revalidate(weekCount: weekCount)
    }

    /// 提交成功：由 `ready` 进入 `committed` 并记录课程 id。
    mutating func markCommitted(courseId: UUID) throws {
        try transition(to: .committed)
        createdCourseId = courseId
        errorCode = nil
        errorMessage = nil
    }
}
