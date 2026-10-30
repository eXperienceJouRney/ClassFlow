import Foundation

enum AIImportResponseError: Error { case invalid }

/// AI 服务的版本化契约，不直接反序列化为可提交的业务实体。
struct TimetableAIResult: Decodable, Sendable {
    struct ClassOption: Decodable, Sendable {
        let id: String
        let name: String
    }
    struct Course: Decodable, Sendable {
        enum Scope: String, Decodable, Sendable { case personal, allClasses, classes, unresolved }
        let name: String
        let teacher: String?
        let location: String?
        let weekday: Int?
        let startPeriod: Int?
        let endPeriod: Int?
        let startTime: String?
        let endTime: String?
        /// 已展开的实际周数，单双周、间隔、排除周均由模型明确给出；null 表示未知。
        let weeks: [Int]?
        let isCurrentWeek: Bool?
        let scope: Scope
        let classIDs: [String]
        let classGroup: String?
        let requiresReview: Bool
        let notes: [String]
        let sourceText: String
    }

    let schemaVersion: Int
    let classes: [ClassOption]
    let displayedWeek: Int?
    let courses: [Course]
    let warnings: [String]

    func validate() throws {
        guard schemaVersion == 1, classes.count <= 100, courses.count <= 512, warnings.count <= 20,
              Set(classes.map(\.id)).count == classes.count,
              Set(classes.map(\.name)).count == classes.count,
              classes.allSatisfy({ !$0.id.isBlank && !$0.name.isBlank && $0.id.count <= 100 && $0.name.count <= 100 }),
              displayedWeek.map({ (1...100).contains($0) }) ?? true else { throw AIImportResponseError.invalid }
        for course in courses {
            guard !course.name.isBlank, course.name.count <= 300, course.sourceText.count <= 6000,
                  course.classIDs.count <= 100, course.notes.count <= 20,
                  course.weeks.map({ $0.count <= 100 && $0.allSatisfy { (1...100).contains($0) } }) ?? true,
                  course.weekday.map({ (1...7).contains($0) }) ?? true,
                  course.startPeriod.map({ (1...30).contains($0) }) ?? true,
                  course.endPeriod.map({ (1...30).contains($0) }) ?? true,
                  course.startTime.map({ TimeOfDay($0) != nil }) ?? true,
                  course.endTime.map({ TimeOfDay($0) != nil }) ?? true else { throw AIImportResponseError.invalid }
        }
    }

    func entries(selectedClassID: String?, draftId: UUID) throws -> [ImportDraftEntry] {
        try validate()
        let selected = classes.first { $0.id == selectedClassID }
        if !classes.isEmpty && selected == nil { throw AIImportResponseError.invalid }
        let knownIDs = Set(classes.map(\.id))
        var result: [ImportDraftEntry] = []
        for course in courses {
            let validClassIDs = !course.classIDs.isEmpty && Set(course.classIDs).isSubset(of: knownIDs)
            if course.scope == .classes && validClassIDs,
               let selectedClassID, !course.classIDs.contains(selectedClassID) { continue }
            let ambiguousClass = course.scope == .unresolved
                || (course.scope == .classes && (!validClassIDs || selected == nil))
                || (course.scope == .personal && !classes.isEmpty)
                || (course.scope == .allClasses && classes.isEmpty)
            var entry = ImportDraftEntry(draftId: draftId, sourceIndex: result.count, rawPayload: course.sourceText)
            entry.courseName = course.name.trimmingCharacters(in: .whitespacesAndNewlines)
            entry.teacher = course.teacher?.normalizedOrNil
            entry.location = course.location?.normalizedOrNil
            entry.weekday = course.weekday.flatMap(Weekday.init(rawValue:))
            entry.startPeriod = course.startPeriod
            entry.endPeriod = course.endPeriod
            entry.startTime = course.startTime.flatMap(TimeOfDay.init)
            entry.endTime = course.endTime.flatMap(TimeOfDay.init)
            var notes = Array(warnings.prefix(5)) + course.notes
            var requiresWeeks = false
            if let weeks = course.weeks {
                entry.weekRule = WeekRule(pattern: .customWeeks, customWeeks: Array(Set(weeks)).sorted())
            } else if let displayedWeek, course.isCurrentWeek == true {
                entry.weekRule = WeekRule(startWeek: displayedWeek, endWeek: displayedWeek)
                notes.append("已按图片默认选择第\(displayedWeek)周，仅导入这一周；需要时可修改周次。")
            } else {
                requiresWeeks = true
                notes.append("未识别到明确周次，请补充并核对上课周次。")
            }
            if course.isCurrentWeek == false { notes.append("原图标记「非本周」，已默认取消勾选。") }
            if course.requiresReview { notes.append("AI 未能确定部分内容，已默认取消勾选，请核对原图。") }
            if ambiguousClass { notes.append(ImportImageReview.classReviewMessage) }
            entry.imageReview = ImportImageReview(notes: notes, requiresWeekConfirmation: requiresWeeks,
                selectedClassName: selected?.name, classGroup: course.classGroup,
                requiresClassReview: ambiguousClass)
            entry.isSelected = !ambiguousClass && !course.requiresReview && course.isCurrentWeek != false
            entry.status = entry.isSelected ? .parsed : .skipped
            result.append(entry)
        }
        return result
    }
}
