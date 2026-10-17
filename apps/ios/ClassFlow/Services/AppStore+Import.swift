import Foundation

// MARK: - 查询

extension AppStore {

    var importDrafts: [ImportDraft] {
        data.importDrafts.sorted { $0.createdAt > $1.createdAt }
    }

    func importDrafts(in semesterId: UUID) -> [ImportDraft] {
        data.importDrafts(in: semesterId)
    }

    func importDraft(id: UUID) -> ImportDraft? {
        data.importDraft(id: id)
    }

    /// 查询提交结果；只读，不得通过重复提交来查询结果。
    func importCommitResult(draftId: UUID) -> ImportCommitResult? {
        guard let draft = data.importDraft(id: draftId) else { return nil }
        return Self.commitResult(for: draft)
    }
}

// MARK: - API-IMP-01 创建草稿

extension AppStore {

    @discardableResult
    func createImportDraft(
        semesterId: UUID,
        sourceKind: ImportSourceKind,
        sourceName: String? = nil
    ) throws -> ImportDraft {
        guard data.semester(id: semesterId) != nil else {
            throw AppError.notFound(entity: "学期")
        }

        let draft = ImportDraft(
            semesterId: semesterId,
            sourceKind: sourceKind,
            sourceName: sourceName?.normalizedOrNil
        )

        try commit { $0.importDrafts.append(draft) }

        return draft
    }

    /// 选择文件后直接创建草稿并解析（文件入口）。
    @discardableResult
    func createImportDraft(
        fromFileURL url: URL,
        semesterId: UUID,
        reader: TextFileImportReader? = nil
    ) throws -> ImportDraft {
        let reader = reader ?? TextFileImportReader()
        let text = try reader.readText(at: url)
        let draft = try createImportDraft(
            semesterId: semesterId,
            sourceKind: .file,
            sourceName: url.lastPathComponent
        )
        return try parseImportSource(draftId: draft.id, text: text)
    }
}

// MARK: - API-IMP-02 解析输入

extension AppStore {

    /// 解析文本输入并生成候选记录；识别成功不等于导入成功。
    @discardableResult
    func parseImportSource(
        draftId: UUID,
        text: String,
        parser: TimetableTextParser? = nil
    ) throws -> ImportDraft {
        let parser = parser ?? PlainTextTimetableParser()
        guard let draft = data.importDraft(id: draftId) else {
            throw AppError.notFound(entity: "导入草稿")
        }
        guard let semester = data.semester(id: draft.semesterId) else {
            throw AppError.notFound(entity: "学期")
        }
        guard !text.isBlank else {
            throw AppError.importParseFailed(reason: "内容为空")
        }

        let outcome = parser.parse(text, draftId: draftId, startingIndex: 0)
        guard !outcome.entries.isEmpty else {
            throw AppError.importParseFailed(
                reason: "没有识别到任何课程记录，请检查每行至少包含课程名称"
            )
        }

        let weekCount = semester.weekCount()
        let entries = outcome.entries.map { entry -> ImportDraftEntry in
            var copy = entry
            copy.revalidate(weekCount: weekCount)
            return copy
        }

        try commit { data in
            guard let index = data.importDrafts.firstIndex(where: { $0.id == draftId }) else { return }
            data.importDrafts[index].entries = entries
            data.importDrafts[index].sourceKind = draft.sourceKind
            data.importDrafts[index].status = Self.derivedDraftStatus(entries: entries, current: .notStarted)
            data.importDrafts[index].updatedAt = Date()
        }

        return try requireImportDraft(id: draftId)
    }

    /// 手动录入：新增一条空白记录，由界面填写后重新校验。
    @discardableResult
    func addManualImportEntry(draftId: UUID) throws -> ImportDraftEntry {
        guard let draft = data.importDraft(id: draftId) else {
            throw AppError.notFound(entity: "导入草稿")
        }
        guard let semester = data.semester(id: draft.semesterId) else {
            throw AppError.notFound(entity: "学期")
        }

        let nextIndex = (draft.entries.map(\.sourceIndex).max() ?? -1) + 1
        var entry = ImportDraftEntry(
            draftId: draftId,
            sourceIndex: nextIndex,
            startWeek: 1,
            endWeek: max(semester.weekCount(), 1),
            weekPattern: .everyWeek
        )
        entry.markParsed()
        entry.revalidate(weekCount: semester.weekCount())

        try mutateDraft(id: draftId) { draft in
            draft.entries.append(entry)
        }

        return entry
    }

    @discardableResult
    func removeImportEntry(draftId: UUID, entryId: UUID) throws -> ImportDraft {
        try mutateDraft(id: draftId) { draft in
            draft.removeEntry(id: entryId)
        }
    }
}

// MARK: - API-IMP-03 修改草稿记录

extension AppStore {

    @discardableResult
    func updateImportEntry(
        draftId: UUID,
        entryId: UUID,
        edit: ImportEntryEdit
    ) throws -> ImportDraftEntry {
        guard let semester = semester(forDraft: draftId) else {
            throw AppError.notFound(entity: "学期")
        }

        var updated: ImportDraftEntry?

        try mutateDraft(id: draftId) { draft in
            guard var entry = draft.entry(id: entryId) else { return }

            entry.courseName = edit.courseName
            entry.teacher = edit.teacher?.normalizedOrNil
            entry.location = edit.location?.normalizedOrNil
            entry.weekday = edit.weekday
            entry.startPeriod = edit.startPeriod
            entry.endPeriod = edit.endPeriod
            entry.startTime = edit.startTime
            entry.endTime = edit.endTime
            entry.weekRule = edit.weekRule.normalized()
            entry.errorCode = nil
            entry.errorMessage = nil
            entry.revalidate(weekCount: semester.weekCount())

            draft.replace(entry)
            updated = entry
        }

        guard let updated else {
            throw AppError.notFound(entity: "导入记录")
        }

        return updated
    }

    /// 直接修改任意字段，随后重新校验并写回。
    @discardableResult
    func updateImportEntry(
        draftId: UUID,
        entryId: UUID,
        mutate: (inout ImportDraftEntry) -> Void
    ) throws -> ImportDraftEntry {
        guard let semester = semester(forDraft: draftId) else {
            throw AppError.notFound(entity: "学期")
        }

        var updated: ImportDraftEntry?

        try mutateDraft(id: draftId) { draft in
            guard var entry = draft.entry(id: entryId) else { return }
            mutate(&entry)
            entry.revalidate(weekCount: semester.weekCount())
            draft.replace(entry)
            updated = entry
        }

        guard let updated else {
            throw AppError.notFound(entity: "导入记录")
        }

        return updated
    }
}

// MARK: - API-IMP-04 选择

extension AppStore {

    @discardableResult
    func setImportEntrySelection(
        draftId: UUID,
        entryId: UUID,
        isSelected: Bool
    ) throws -> ImportDraft {
        guard let semester = semester(forDraft: draftId) else {
            throw AppError.notFound(entity: "学期")
        }

        return try mutateDraft(id: draftId) { draft in
            guard var entry = draft.entry(id: entryId) else { return }
            entry.applySelection(isSelected, weekCount: semester.weekCount())
            draft.replace(entry)
        }
    }

    @discardableResult
    func setImportSelection(draftId: UUID, isSelected: Bool) throws -> ImportDraft {
        guard let semester = semester(forDraft: draftId) else {
            throw AppError.notFound(entity: "学期")
        }

        return try mutateDraft(id: draftId) { draft in
            for entryId in draft.entries.map(\.id) {
                guard var copy = draft.entry(id: entryId) else { continue }
                copy.applySelection(isSelected, weekCount: semester.weekCount())
                draft.replace(copy)
            }
        }
    }
}

// MARK: - API-IMP-05 校验

extension AppStore {

    /// 校验草稿，不写入任何正式数据。
    func validateImportDraft(draftId: UUID) throws -> ValidationResult {
        guard let draft = data.importDraft(id: draftId) else {
            throw AppError.notFound(entity: "导入草稿")
        }
        guard let semester = data.semester(id: draft.semesterId) else {
            throw AppError.notFound(entity: "学期")
        }

        let weekCount = semester.weekCount()
        var issues: [ValidationIssue] = []

        for entry in draft.entries where entry.isSelected {
            var copy = entry
            issues.append(contentsOf: copy.revalidate(weekCount: weekCount))
        }

        let hasCommittable = draft.entries.contains { entry in
            var copy = entry
            copy.revalidate(weekCount: weekCount)
            return copy.isSelected && copy.status == .ready
        }

        if draft.selectedEntries.isEmpty {
            issues.append(
                ValidationIssue(
                    code: "IMPORT_NO_SELECTION",
                    field: "选择",
                    message: "至少选择一条要导入的记录"
                )
            )
        }

        return ValidationResult(isValid: hasCommittable && issues.isEmpty, issues: issues)
    }
}

// MARK: - API-IMP-06 冲突检测（只读）

extension AppStore {

    func detectImportConflicts(draftId: UUID) throws -> [ImportConflict] {
        guard let draft = data.importDraft(id: draftId) else {
            throw AppError.notFound(entity: "导入草稿")
        }
        guard let semester = data.semester(id: draft.semesterId) else {
            throw AppError.notFound(entity: "学期")
        }

        return Self.detectConflicts(
            entries: draft.entries,
            draftId: draftId,
            semester: semester,
            courses: data.courses(in: semester.id),
            existingEntries: data.scheduleEntries,
            periods: data.effectivePeriodTimes(in: semester.id)
        )
    }
}

// MARK: - OPEN-13 课节钟点候选值

extension AppStore {

    /// 目标学期缺少对应课节配置时，返回草稿识别出的钟点作为学期课节配置的候选值。
    /// 由用户确认后写入学期，不写入 `ScheduleEntry`。
    func importedPeriodTimeCandidates(draftId: UUID) -> [ClassPeriodInput] {
        guard let draft = data.importDraft(id: draftId) else { return [] }

        // 基准是已保存的作息，不是 `effectivePeriodTimes`：内置默认作息不算用户配置过。
        let configured = Set(data.periodTimes(in: draft.semesterId).map(\.periodNumber))
        var seen = Set<Int>()
        var candidates: [ClassPeriodInput] = []

        for entry in draft.entries where entry.isSelected {
            guard let candidate = entry.candidatePeriodTime else { continue }
            guard !configured.contains(candidate.periodNumber) else { continue }
            guard candidate.startTime < candidate.endTime else { continue }
            guard seen.insert(candidate.periodNumber).inserted else { continue }
            candidates.append(candidate)
        }

        return candidates.sorted { $0.periodNumber < $1.periodNumber }
    }

    /// 用户确认后把候选钟点合并进学期课节配置；基准是已保存的作息，内置默认作息不写入学期数据。
    @discardableResult
    func applyImportedPeriodTimeCandidates(draftId: UUID) throws -> [ClassPeriodTime] {
        guard let draft = data.importDraft(id: draftId) else {
            throw AppError.notFound(entity: "导入草稿")
        }

        let candidates = importedPeriodTimeCandidates(draftId: draftId)
        guard !candidates.isEmpty else { return data.periodTimes(in: draft.semesterId) }

        var merged = data.periodTimes(in: draft.semesterId).map {
            ClassPeriodInput(periodNumber: $0.periodNumber, startTime: $0.startTime, endTime: $0.endTime)
        }
        for candidate in candidates where !merged.contains(where: { $0.periodNumber == candidate.periodNumber }) {
            merged.append(candidate)
        }

        try setPeriodTimes(merged.sorted { $0.periodNumber < $1.periodNumber }, for: draft.semesterId)

        return data.periodTimes(in: draft.semesterId)
    }
}

// MARK: - API-IMP-07 提交

extension AppStore {

    /// 提交选中的记录：仅 `ready` 记录可提交，时间冲突需用户确认。
    /// 课程、安排与草稿终态在同一事务内写入，失败时不留下半提交状态。
    @discardableResult
    func commitImportDraft(
        draftId: UUID,
        userConfirmed: Bool,
        conflictStrategy: ImportConflictStrategy = .keepAll
    ) throws -> ImportCommitResult {
        guard let draft = data.importDraft(id: draftId) else {
            throw AppError.notFound(entity: "导入草稿")
        }
        guard let semester = data.semester(id: draft.semesterId) else {
            throw AppError.notFound(entity: "学期")
        }
        guard draft.status != .succeeded else {
            throw AppError.invalidStateTransition(reason: "该导入草稿已经提交过，不能重复提交")
        }
        guard userConfirmed else {
            throw AppError.confirmationRequired(operation: "导入课表")
        }

        let weekCount = semester.weekCount()

        var entries = draft.entries.map { entry -> ImportDraftEntry in
            var copy = entry
            if copy.isSelected {
                copy.revalidate(weekCount: weekCount)
                copy.errorCode = nil
                copy.errorMessage = nil
            }
            return copy
        }

        let conflicts = Self.detectConflicts(
            entries: entries,
            draftId: draftId,
            semester: semester,
            courses: data.courses(in: semester.id),
            existingEntries: data.scheduleEntries,
            periods: data.effectivePeriodTimes(in: semester.id)
        )

        var conflictIds: [UUID: [UUID]] = [:]
        for conflict in conflicts where conflict.kind.isTimeOverlap {
            conflictIds[conflict.firstEntryId, default: []].append(conflict.id)
            if let second = conflict.secondEntryId, entries.contains(where: { $0.id == second }) {
                conflictIds[second, default: []].append(conflict.id)
            }
        }
        for index in entries.indices {
            entries[index].conflictIds = conflictIds[entries[index].id] ?? []
        }

        // 跳过冲突记录时保留草稿中靠前的一条。
        if conflictStrategy == .skipConflicting {
            var skippedIds = Set<UUID>()

            for conflict in conflicts where conflict.kind.isTimeOverlap {
                switch conflict.kind {
                case .existingSchedule:
                    skippedIds.insert(conflict.firstEntryId)

                case .withinDraft:
                    guard let secondId = conflict.secondEntryId else { break }
                    if skippedIds.contains(conflict.firstEntryId) {
                        skippedIds.insert(secondId)
                    } else if skippedIds.contains(secondId) {
                        skippedIds.insert(conflict.firstEntryId)
                    } else {
                        let firstIndex = entries.firstIndex { $0.id == conflict.firstEntryId } ?? 0
                        let secondIndex = entries.firstIndex { $0.id == secondId } ?? 0
                        skippedIds.insert(firstIndex <= secondIndex ? secondId : conflict.firstEntryId)
                    }

                case .sameNameCourse:
                    break
                }
            }

            for index in entries.indices where entries[index].isSelected && skippedIds.contains(entries[index].id) {
                entries[index].isSelected = false
                if entries[index].canTransition(to: .skipped) {
                    entries[index].status = .skipped
                }
            }
        }

        // 任一被选记录未就绪则整次失败，不写入任何正式数据。
        let blocked = entries.filter { $0.isSelected && $0.status != .ready }
        if !blocked.isEmpty || !entries.contains(where: { $0.isSelected && $0.status == .ready }) {
            for index in entries.indices where entries[index].isSelected && entries[index].status != .ready {
                let issue = entries[index].issues.first
                entries[index].errorCode = issue?.code ?? "IMPORT_ENTRY_NOT_READY"
                entries[index].errorMessage = issue?.message ?? "该记录尚未通过校验"
            }

            try persistDraftEntries(draftId: draftId, entries: entries, status: .failed)

            let result = Self.commitResult(for: try requireImportDraft(id: draftId))
            return result
        }

        // 同一学期内课程名相同即同一门课；不同课次挂在同一门课下，已存在的同名课程直接并入。
        let existingCourses = data.courses(in: semester.id)
        var groups: [ImportCourseGroup] = []
        for entry in entries where entry.isSelected && entry.status == .ready {
            let name = Self.courseNameKey(entry.courseName)

            if let index = groups.firstIndex(where: { $0.name == name }) {
                groups[index].append(entry)
            } else {
                groups.append(ImportCourseGroup(entry: entry, name: name))
            }
        }

        var newCourses: [Course] = []
        var mergedCourses: [Course] = []
        var newScheduleEntries: [ScheduleEntry] = []
        var courseIdForEntry: [UUID: UUID] = [:]
        var mergedCourseIds = Set<UUID>()

        for group in groups {
            let existing = existingCourses.first { Self.courseNameKey($0.name) == group.name }
            var course: Course
            var isMerged = false

            if let existing {
                course = existing
                isMerged = true
                mergedCourseIds.insert(existing.id)

                let teacher = Self.mergedDetail(existing.teacher, group.teachers)
                let location = Self.mergedDetail(existing.location, group.locations)
                if teacher != course.teacher || location != course.location {
                    course.teacher = teacher
                    course.location = location
                    course.updatedAt = Date()
                }
            } else {
                course = Course(
                    semesterId: semester.id,
                    name: group.name,
                    teacher: Self.mergedDetail(nil, group.teachers),
                    location: Self.mergedDetail(nil, group.locations),
                    color: CourseColor.allCases[newCourses.count % CourseColor.allCases.count]
                )
            }

            do {
                try course.appValidated()
            } catch {
                throw AppError.importCommitFailed(reason: error.userMessage)
            }

            if isMerged {
                mergedCourses.append(course)
            } else {
                newCourses.append(course)
            }

            // 只用课程下已有安排去重；草稿内部的重复记录仍按用户的选择写入。
            let existingSiblings = data.scheduleEntries.filter { $0.courseId == course.id }

            for entryId in group.entryIds {
                guard let source = entries.first(where: { $0.id == entryId }),
                      let weekday = source.weekday,
                      let time = source.resolvedClassTime
                else { continue }

                // 教室写在安排上：同一门课的不同课次可能在不同教室。
                var scheduleEntry = ScheduleEntry(
                    courseId: course.id,
                    weekday: weekday,
                    time: time,
                    location: source.location?.normalizedOrNil
                )
                scheduleEntry.weekRule = source.weekRule
                scheduleEntry.normalize()

                do {
                    try scheduleEntry.appValidated()
                } catch {
                    throw AppError.importCommitFailed(reason: error.userMessage)
                }

                courseIdForEntry[entryId] = course.id

                if Self.hasEquivalentEntry(scheduleEntry, in: existingSiblings) { continue }

                newScheduleEntries.append(scheduleEntry)
            }
        }

        for index in entries.indices {
            guard let courseId = courseIdForEntry[entries[index].id] else { continue }
            if mergedCourseIds.contains(courseId) {
                entries[index].matchedCourseId = courseId
            }
            do {
                try entries[index].markCommitted(courseId: courseId)
            } catch {
                throw AppError.invalidStateTransition(reason: "导入记录状态异常，已中止提交")
            }
        }

        try commit { data in
            data.courses.append(contentsOf: newCourses)
            for course in mergedCourses {
                guard let index = data.courses.firstIndex(where: { $0.id == course.id }) else { continue }
                data.courses[index] = course
            }
            data.scheduleEntries.append(contentsOf: newScheduleEntries)

            guard let index = data.importDrafts.firstIndex(where: { $0.id == draftId }) else { return }
            data.importDrafts[index].entries = entries
            data.importDrafts[index].status = .succeeded
            data.importDrafts[index].updatedAt = Date()
        }

        return Self.commitResult(for: try requireImportDraft(id: draftId))
    }

    /// 取消导入，不写入任何正式数据；已提交的草稿不可取消。
    @discardableResult
    func cancelImportDraft(draftId: UUID) throws -> ImportDraft {
        try mutateDraft(id: draftId) { draft in
            guard draft.status != .succeeded else { return }
            draft.status = .cancelled
        }
    }

    func deleteImportDraft(id: UUID) throws {
        guard data.importDraft(id: id) != nil else {
            throw AppError.notFound(entity: "导入草稿")
        }

        try commit { $0.importDrafts.removeAll { $0.id == id } }
    }
}

// MARK: - 内部工具

extension AppStore {

    private func requireImportDraft(id: UUID) throws -> ImportDraft {
        guard let draft = data.importDraft(id: id) else {
            throw AppError.notFound(entity: "导入草稿")
        }
        return draft
    }

    private func semester(forDraft draftId: UUID) -> Semester? {
        guard let draft = data.importDraft(id: draftId) else { return nil }
        return data.semester(id: draft.semesterId)
    }

    /// 课程身份键：首尾去空白后的课程名，不做大小写或全半角折叠。
    static func courseNameKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 合并课程级的教师 / 地点：去重后按首次出现顺序用「/」连接。
    /// 每次上课的真实教室写在 `ScheduleEntry.location` 上。
    static func mergedDetail(_ existing: String?, _ imported: [String]) -> String? {
        var parts: [String] = []

        for value in [existing].compactMap({ $0 }) + imported {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !parts.contains(trimmed) else { continue }
            parts.append(trimmed)
        }

        return parts.isEmpty ? nil : parts.joined(separator: "/")
    }

    /// 课程下是否已有完全相同的安排（星期 + 时间 + 周次规则）。
    static func hasEquivalentEntry(_ candidate: ScheduleEntry, in entries: [ScheduleEntry]) -> Bool {
        entries.contains {
            $0.courseId == candidate.courseId
                && $0.weekday == candidate.weekday
                && $0.time == candidate.time
                && $0.weekRule == candidate.weekRule
        }
    }

    @discardableResult
    private func mutateDraft(
        id: UUID,
        _ mutate: (inout ImportDraft) -> Void
    ) throws -> ImportDraft {
        guard var draft = data.importDraft(id: id) else {
            throw AppError.notFound(entity: "导入草稿")
        }

        mutate(&draft)
        draft.status = Self.derivedDraftStatus(entries: draft.entries, current: draft.status)
        draft.updatedAt = Date()

        try commit { data in
            guard let index = data.importDrafts.firstIndex(where: { $0.id == id }) else { return }
            data.importDrafts[index] = draft
        }

        return draft
    }

    private func persistDraftEntries(
        draftId: UUID,
        entries: [ImportDraftEntry],
        status: ImportCommitStatus
    ) throws {
        try commit { data in
            guard let index = data.importDrafts.firstIndex(where: { $0.id == draftId }) else { return }
            data.importDrafts[index].entries = entries
            data.importDrafts[index].status = status
            data.importDrafts[index].updatedAt = Date()
        }
    }

    private static func derivedDraftStatus(
        entries: [ImportDraftEntry],
        current: ImportCommitStatus
    ) -> ImportCommitStatus {
        // 终态不被后续编辑覆盖：已提交、已取消的草稿保留原状态
        if current == .succeeded || current == .committing || current == .cancelled { return current }
        if entries.isEmpty { return .notStarted }

        let hasCommittable = entries.contains { $0.isSelected && $0.status == .ready }
        return hasCommittable ? .readyToCommit : .failed
    }

    private static func commitResult(for draft: ImportDraft) -> ImportCommitResult {
        var courseIds: [UUID] = []
        for entry in draft.entries {
            guard let courseId = entry.createdCourseId, !courseIds.contains(courseId) else { continue }
            courseIds.append(courseId)
        }

        return ImportCommitResult(
            draftId: draft.id,
            status: draft.status,
            committedCourseIds: courseIds,
            committedEntryIds: draft.entries.filter { $0.status == .committed }.map(\.id),
            skippedEntryIds: draft.entries.filter { $0.status == .skipped }.map(\.id),
            failedEntryIds: draft.entries.filter { $0.errorCode != nil }.map(\.id),
            issues: draft.entries.compactMap { entry in
                guard let code = entry.errorCode else { return nil }
                return ImportCommitFailure(entryId: entry.id, code: code, message: entry.errorMessage ?? "")
            }
        )
    }
}

// MARK: - 冲突检测

extension AppStore {

    /// 纯函数冲突检测；时间重叠判定复用 `ScheduleConflictDetector`，与日/周视图规则一致。
    static func detectConflicts(
        entries: [ImportDraftEntry],
        draftId: UUID,
        semester: Semester,
        courses: [Course],
        existingEntries: [ScheduleEntry],
        periods: [ClassPeriodTime]
    ) -> [ImportConflict] {
        let weekCount = max(semester.weekCount(), 1)

        var candidates: [ScheduleSlot] = []
        for entry in entries where entry.isSelected {
            guard let weekday = entry.weekday,
                  let classTime = entry.resolvedClassTime,
                  let time = ScheduleSlot.resolve(classTime, periods: periods)
            else { continue }

            candidates.append(
                ScheduleSlot(
                    entryId: entry.id,
                    courseName: entry.displayName,
                    weekday: weekday,
                    weeks: Set(entry.weekRule.resolvedWeeks(upTo: weekCount)),
                    time: time
                )
            )
        }

        let coursesById = Dictionary(courses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var conflicts: [ImportConflict] = []

        for firstIndex in candidates.indices {
            for secondIndex in candidates.indices where secondIndex > firstIndex {
                let first = candidates[firstIndex]
                let second = candidates[secondIndex]
                guard let firstId = first.entryId,
                      let secondId = second.entryId,
                      let overlap = ScheduleConflictDetector.overlap(first, second)
                else { continue }

                conflicts.append(
                    ImportConflict(
                        draftId: draftId,
                        kind: .withinDraft,
                        firstEntryId: firstId,
                        secondEntryId: secondId,
                        firstLabel: first.courseName,
                        secondLabel: second.courseName,
                        weekday: first.weekday,
                        overlapDescription: overlap.description,
                        weeksDescription: overlap.weeksDescription
                    )
                )
            }
        }

        for candidate in candidates {
            guard let candidateId = candidate.entryId else { continue }

            for existing in existingEntries {
                guard let course = coursesById[existing.courseId],
                      let slot = ScheduleSlot.make(
                        entry: existing,
                        course: course,
                        periods: periods,
                        weekCount: weekCount
                      ),
                      let overlap = ScheduleConflictDetector.overlap(candidate, slot)
                else { continue }

                conflicts.append(
                    ImportConflict(
                        draftId: draftId,
                        kind: .existingSchedule,
                        firstEntryId: candidateId,
                        secondEntryId: nil,
                        secondCourseId: course.id,
                        firstLabel: candidate.courseName,
                        secondLabel: course.name,
                        weekday: candidate.weekday,
                        overlapDescription: overlap.description,
                        weeksDescription: overlap.weeksDescription
                    )
                )
            }
        }

        // 同名课程只做提示，不修改数据；提交时会并入已有课程。
        for candidate in candidates {
            guard let candidateId = candidate.entryId,
                  let entry = entries.first(where: { $0.id == candidateId })
            else { continue }

            let name = Self.courseNameKey(entry.courseName)
            guard !name.isEmpty,
                  let match = courses.first(where: { Self.courseNameKey($0.name) == name })
            else { continue }

            conflicts.append(
                ImportConflict(
                    draftId: draftId,
                    kind: .sameNameCourse,
                    firstEntryId: candidateId,
                    secondCourseId: match.id,
                    firstLabel: candidate.courseName,
                    secondLabel: match.name,
                    weekday: candidate.weekday,
                    overlapDescription: "该学期已存在同名课程，导入会把新安排并入这门课程",
                    weeksDescription: ""
                )
            )
        }

        return conflicts
    }
}

// MARK: - 课程编辑时的冲突检查

extension AppStore {

    /// 检查候选安排与学期内已有安排的时间冲突；只读，不修改数据。
    func detectScheduleConflicts(
        semesterId: UUID,
        candidateEntries: [ScheduleEntryInput],
        courseName: String,
        excludingCourseId: UUID? = nil
    ) -> [ScheduleConflict] {
        guard let semester = data.semester(id: semesterId) else { return [] }

        let weekCount = max(semester.weekCount(), 1)
        let periods = data.effectivePeriodTimes(in: semesterId)

        let candidates = candidateEntries.compactMap { input in
            ScheduleSlot.make(
                input: input,
                courseName: courseName.normalizedOrNil ?? "本课程",
                periods: periods,
                weekCount: weekCount
            )
        }

        let coursesById = Dictionary(
            data.courses(in: semesterId).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let existing = data.scheduleEntries
            .filter { $0.courseId != excludingCourseId }
            .compactMap { entry in
                ScheduleSlot.make(
                    entry: entry,
                    course: coursesById[entry.courseId],
                    periods: periods,
                    weekCount: weekCount
                )
            }

        var conflicts = ScheduleConflictDetector.conflicts(among: candidates)

        for candidate in candidates {
            for slot in existing {
                guard let overlap = ScheduleConflictDetector.overlap(candidate, slot) else { continue }

                conflicts.append(
                    ScheduleConflict(
                        firstEntryId: candidate.entryId,
                        secondEntryId: slot.entryId,
                        firstCourseName: candidate.courseName,
                        secondCourseName: slot.courseName,
                        dateDescription: "\(candidate.weekday.shortName) \(overlap.weeksDescription)",
                        overlapDescription: overlap.description
                    )
                )
            }
        }

        return conflicts
    }
}

// MARK: - 内部数据结构

/// 提交时按课程名归并的一组记录。
private struct ImportCourseGroup {

    /// 首尾去空白后的课程名，同时也是这门课的身份键。
    let name: String
    var entryIds: [UUID]
    /// 组内出现过的教师 / 地点，去重后用于课程级字段。
    var teachers: [String]
    var locations: [String]

    init(entry: ImportDraftEntry, name: String) {
        self.name = name
        self.entryIds = []
        self.teachers = []
        self.locations = []
        append(entry)
    }

    mutating func append(_ entry: ImportDraftEntry) {
        entryIds.append(entry.id)

        if let teacher = entry.teacher?.normalizedOrNil, !teachers.contains(teacher) {
            teachers.append(teacher)
        }
        if let location = entry.location?.normalizedOrNil, !locations.contains(location) {
            locations.append(location)
        }
    }
}
