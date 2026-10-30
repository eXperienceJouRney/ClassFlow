import Foundation
import AppKit
import CoreGraphics
import ImageIO

/// 本地回归检查：布局还原与草稿写入使用生产代码，不需要启动模拟器。
@main
struct VerifyImageImport {
    @MainActor private static var report: [String] = []

    @MainActor
    static func main() async {
        do {
            try await run()
            try writeReport()
        } catch {
            print("FAIL \(error)")
            report.append("FAIL \(error)")
            try? writeReport()
            exit(1)
        }
    }

    @MainActor
    static func run() async throws {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else { throw CheckFailure(message: message) }
            count += 1
            print("PASS \(message)")
            report.append("PASS \(message)")
        }
        func block(_ text: String, _ x: Double, _ y: Double, _ width: Double = 0.18) -> TimetableOCRBlock {
            TimetableOCRBlock(text: text, bounds: CGRect(x: x, y: y, width: width, height: 0.025), confidence: 0.98)
        }
        let parser = TimetableImageLayoutParser()
        let draftId = UUID()
        let headers = [block("周一", 0.22, 0.06), block("周二", 0.49, 0.06), block("周三", 0.76, 0.06)]
        let anchors = [block("第1-2节", 0.01, 0.25, 0.1), block("第3-4节", 0.01, 0.60, 0.1)]
        let grid = headers + anchors + [
            block("高等数学", 0.22, 0.20), block("1-16周", 0.22, 0.24),
            block("教师:王老师", 0.22, 0.28), block("教室:教三201", 0.22, 0.32),
            block("大学物理", 0.49, 0.55), block("2-16周(双)", 0.49, 0.59),
            block("第5-6节", 0.49, 0.63),
            block("Data Structures", 0.76, 0.20), block("1-15周(单)", 0.76, 0.24),
        ]
        let entries = parser.parse(grid, draftId: draftId)
        try check(entries.count == 3, "网格课表提取三条课程，不把表头与课节当课程")
        let math = try require(entries.first { $0.courseName == "高等数学" })
        try check(math.weekday == .monday && math.startPeriod == 1 && math.endPeriod == 2, "依据星期列与左侧课节范围还原安排")
        try check(math.teacher == "王老师" && math.location == "教三201", "提取教师与教室")
        try check(math.startWeek == 1 && math.endWeek == 16, "提取周次范围")
        let physics = try require(entries.first { $0.courseName == "大学物理" })
        try check(physics.startPeriod == 5 && physics.endPeriod == 6, "课程内显式课节优先于左侧行标签")
        try check(physics.weekPattern == .evenWeeks && physics.weekday == .tuesday, "识别括号双周")
        let english = try require(entries.first { $0.courseName == "Data Structures" })
        try check(english.weekPattern == .oddWeeks, "保留完整英文课名并识别单周")

        let lines = parser.parse([block("计算机网络,周五,第3-4节,1-8周,教三203", 0.1, 0.2, 0.8)], draftId: draftId)
        try check(lines.count == 1 && lines[0].weekday == .friday && lines[0].startPeriod == 3, "没有网格时识别逐行课表文本")
        try check(parser.parse([block("欢迎使用课表", 0.1, 0.1), block("张三", 0.2, 0.3)], draftId: draftId).isEmpty, "普通文字图片不生成虚假课程")

        let incomplete = parser.parse(headers + [block("操作系统", 0.22, 0.2)], draftId: draftId)
        var partial = try require(incomplete.first)
        partial.revalidate(weekCount: 20)
        try check(partial.weekday == .monday && partial.startPeriod == nil && partial.status == .needsCorrection, "缺少时间时保留待修正记录，不猜课节")
        let missingColumn = parser.parse([headers[0], headers[2], block("不应归入周一或周三", 0.49, 0.2)], draftId: draftId)
        try check(missingColumn.isEmpty, "表头缺失的星期列不映射到相邻星期")
        let vertical = parser.parse([block("周一", 0.1, 0.1), block("周二", 0.1, 0.3), block("标题", 0.5, 0.4)], draftId: draftId)
        try check(vertical.isEmpty, "纵向星期列表不误识别为横向网格")
        let ranges = parser.parse(headers + [block("离散数学", 0.22, 0.2), block("1-4,9-12周(单)", 0.22, 0.24), block("第1-2节", 0.22, 0.28)], draftId: draftId)
        try check(ranges.first?.weekRule.resolvedWeeks(upTo: 20) == [1, 3, 9, 11], "多段周次保留间隔，并正确应用单双周")

        for token in ["1-8周、10-16周", "第1-8周，第10-16周", "1-8、10-16周"] {
            let courses = parser.parse([block("高等数学,周一,第1-2节,\(token),教室:教三201", 0.1, 0.2, 0.8)], draftId: draftId)
            var course = try require(courses.first)
            course.revalidate(weekCount: 20)
            try check(courses.count == 1 && course.weekRule.resolvedWeeks(upTo: 20) == Array(1...8) + Array(10...16)
                && course.status == .ready, "多段周次 \(token) 不漏掉后一段")
        }
        let excluded = parser.parse([block("高等数学,周一,第1-2节,1-16周（除4、8周）,教室:教三201", 0.1, 0.2, 0.8)], draftId: draftId)
        var excludedCourse = try require(excluded.first)
        excludedCourse.revalidate(weekCount: 20)
        try check(excluded.count == 1 && excludedCourse.weekRule.resolvedWeeks(upTo: 20) == (1...16).filter { ![4, 8].contains($0) }
            && excludedCourse.status == .ready, "排除周不覆盖正向周次，也不产生冲突周规则")
        let repeatedOdd = parser.parse([block("离散数学,周一,第1-2节,1-8周、10-16周(单)（除3、11周）,教室:教三201", 0.1, 0.2, 0.8)], draftId: draftId)
        try check(repeatedOdd.first?.weekRule.resolvedWeeks(upTo: 20) == [1, 5, 7, 13, 15],
            "每段带周单位时仍同时应用单双周与排除周")

        for token in ["単周", "單周", "单 周"] {
            let odd = parser.parse(headers + [block("单片机基础", 0.22, 0.2), block("1-10周（\(token)）", 0.22, 0.24)], draftId: draftId)
            try check(odd.first?.courseName == "单片机基础" && odd.first?.weekRule.resolvedWeeks(upTo: 20) == [1, 3, 5, 7, 9],
                "周规则归一化\(token)，保留课程名与单周限制")
        }
        let even = parser.parse(headers + [block("概率论", 0.22, 0.2), block("2-10周（雙周）", 0.22, 0.24)], draftId: draftId)
        try check(even.first?.weekRule.resolvedWeeks(upTo: 20) == [2, 4, 6, 8, 10], "兼容繁体双周")
        let agenda = [block("周一", 0.07, 0.15, 0.08), block("第3-4节", 0.07, 0.21, 0.13),
            block("Data Structures", 0.36, 0.15, 0.4), block("2-8周（双周）", 0.36, 0.21, 0.3), block("教室:实验楼A201", 0.36, 0.26, 0.4),
            block("周三", 0.07, 0.48, 0.08), block("线性代数", 0.36, 0.48, 0.3),
            block("教师:李老师", 0.36, 0.53, 0.3), block("第1-2节", 0.07, 0.56, 0.13),
            block("1-9周（単周）", 0.36, 0.58, 0.3), block("教室:理科楼B201", 0.36, 0.64, 0.4)]
        let agendaEntries = parser.parse(agenda.reversed(), draftId: draftId)
        try check(agendaEntries.count == 2 && agendaEntries[0].courseName == "Data Structures"
            && agendaEntries[0].weekday == .monday && agendaEntries[0].startPeriod == 3
            && agendaEntries[0].location == "实验楼A201", "日程卡片按空间关联左右字段，保持英文课名")
        try check(agendaEntries[1].courseName == "线性代数" && agendaEntries[1].weekday == .wednesday
            && agendaEntries[1].teacher == "李老师" && agendaEntries[1].startPeriod == 1
            && agendaEntries[1].weekRule.resolvedWeeks(upTo: 20) == [1, 3, 5, 7, 9], "卡片内部字段换行和顺序变化仍保留安排")
        let repeatedDay = agenda.map { b in b.text == "周三"
            ? block("周一", 0.07, 0.48, 0.08) : b }
        try check(parser.parse(repeatedDay, draftId: draftId).count == 2, "相同星期的多张卡片分别保留")
        let transposed = [block("第1-2节", 0.27, 0.08, 0.15), block("第3-4节", 0.65, 0.08, 0.15),
            block("周一", 0.03, 0.30, 0.09), block("周二", 0.03, 0.60, 0.09),
            block("高等数学", 0.27, 0.25, 0.17), block("1-8周", 0.27, 0.30, 0.17), block("教室:理科楼A101", 0.27, 0.35, 0.25),
            block("大学物理", 0.65, 0.55, 0.17), block("2-12周（雙周）", 0.65, 0.60, 0.23)]
        let transposedEntries = parser.parse(transposed.reversed(), draftId: draftId)
        try check(transposedEntries.count == 2 && transposedEntries[0].courseName == "高等数学"
            && transposedEntries[0].weekday == .monday && transposedEntries[0].startPeriod == 1
            && transposedEntries[0].location == "理科楼A101", "星期纵排课表由两个语义坐标轴还原课程")
        try check(transposedEntries[1].weekday == .tuesday && transposedEntries[1].startPeriod == 3
            && transposedEntries[1].endPeriod == 4 && transposedEntries[1].weekRule.resolvedWeeks(upTo: 20) == [2, 4, 6, 8, 10, 12],
            "纵排课表保留课节和双周限制")
        try check(parser.parse([block("1-10周（単周）", 0.3, 0.2, 0.3), block("第3-4节", 0.05, 0.2, 0.15)], draftId: draftId).isEmpty,
            "周规则和课节不会独自成为虚假课程")

        // 手机周视图：前三个单字星期可能被 OCR 漏掉，日期格仍完整。
        let calendarParser = TimetableImageCalendarParser()
        let dates = [26, 27, 28, 29, 30, 31, 1].enumerated().map {
            block(String($0.element), 0.14 + Double($0.offset) * 0.12, 0.08, 0.04)
        }
        let shortHeaders = [block("四", 0.50, 0.045, 0.04), block("五", 0.62, 0.045, 0.04)]
        let periodLabels = (1...8).map { block(String($0), 0.02, 0.2 + Double($0 - 1) * 0.08, 0.03) }
        let calendarBlocks = dates + shortHeaders + periodLabels
        let layout = try require(calendarParser.layout(in: calendarBlocks))
        try check(layout.columns.map(\.weekday) == Weekday.allCases, "日期格与两个单字星期标记共同恢复列序")
        try check(calendarParser.layout(in: dates + [shortHeaders[0]] + periodLabels) == nil, "单个星期证据不足时不补猜星期列")
        try check(calendarParser.layout(in: dates + [shortHeaders[0], shortHeaders[0]] + periodLabels) == nil, "重复的同列星期不算两个独立证据")
        try check(calendarParser.layout(in: calendarBlocks + [block("二", 0.38, 0.045, 0.04)]) == nil, "矛盾的星期标记不产生手机课表")
        var brokenDates = dates
        brokenDates[2] = block("8", 0.38, 0.08, 0.04)
        try check(calendarParser.layout(in: brokenDates + shortHeaders + periodLabels) == nil, "普通数字表格不误认为连续日期行")
        let mobileCards = [
            TimetableImageCard(bounds: CGRect(x: 0.105, y: 0.35, width: 0.11, height: 0.16), weekday: .monday, startPeriod: 3, endPeriod: 4),
            TimetableImageCard(bounds: CGRect(x: 0.345, y: 0.51, width: 0.11, height: 0.32), weekday: .wednesday, startPeriod: 5, endPeriod: 8),
        ]
        let mobileText = [
            block("操作", 0.13, 0.36, 0.06), block("系统", 0.13, 0.385, 0.06), block("原理", 0.13, 0.41, 0.06),
            block("@西", 0.13, 0.435, 0.06), block("十二", 0.13, 0.46, 0.06), block("楼S409", 0.12, 0.485, 0.08),
            block("操作", 0.37, 0.54, 0.06), block("系统", 0.37, 0.565, 0.06), block("原理", 0.37, 0.59, 0.06), block("实验", 0.37, 0.615, 0.06),
            block("@计算机", 0.36, 0.64, 0.08), block("大楼2048", 0.36, 0.665, 0.08), block("B", 0.39, 0.69, 0.02),
            block("非本周", 0.37, 0.78, 0.06),
        ]
        let mobileEntries = calendarParser.parse(mobileCards, blocks: mobileText, layout: layout, draftId: draftId)
        try check(mobileEntries.map(\.courseName) == ["操作系统原理", "操作系统原理实验"] && mobileEntries[0].location == "西十二楼S409", "窄列换行合并完整课名，并分离 @ 教室")
        try check(mobileEntries[1].endPeriod == 8 && !mobileEntries[1].isSelected && mobileEntries[1].location == "计算机大楼2048B", "跨四节卡片与非本周标记保留，默认不勾选")
        var mobileEntry = mobileEntries[0]
        mobileEntry.revalidate(weekCount: 20)
        try check(mobileEntry.status == .needsCorrection && mobileEntry.issues.contains { $0.code == ImportIssueCode.imageWeeksUnconfirmed.rawValue }, "未知周次不会默认扩展为每周可提交")
        let mobileSaved = try JSONDecoder().decode(ImportDraftEntry.self, from: JSONEncoder().encode(mobileEntry))
        try check(mobileSaved.imageReview?.requiresWeekConfirmation == true, "周次核对要求随草稿持久化")
        let mobileRanges = calendarParser.parse([mobileCards[0]],
            blocks: mobileText + [block("1-4,9-12周(单)", 0.12, 0.495, 0.08)], layout: layout, draftId: draftId)
        try check(mobileRanges.first?.weekRule.resolvedWeeks(upTo: 20) == [1, 3, 9, 11]
            && mobileRanges.first?.imageReview?.requiresWeekConfirmation == false, "手机卡片也完整保留显式多段周次")
        let titledLayout = try require(calendarParser.layout(in: calendarBlocks + [block("第9周 周四", 0.02, 0.005, 0.3)]))
        let defaultWeekEntries = calendarParser.parse(mobileCards, blocks: mobileText, layout: titledLayout, draftId: draftId)
        var defaultWeekEntry = defaultWeekEntries[0]
        defaultWeekEntry.revalidate(weekCount: 20)
        try check(defaultWeekEntry.weekRule.resolvedWeeks(upTo: 20) == [9]
            && defaultWeekEntry.status == .ready && defaultWeekEntry.imageReview?.requiresWeekConfirmation == false,
            "图片第9周自动填入正常课程，无需手动选周即可提交")
        try check(!defaultWeekEntries[1].isSelected && defaultWeekEntries[1].imageReview?.requiresWeekConfirmation == true
            && defaultWeekEntries[1].startWeek == nil, "非本周记录不会自动填成第9周")
        let explicitWeeks = calendarParser.parse([mobileCards[0]],
            blocks: mobileText + [block("1-4,9-12周(单)", 0.12, 0.495, 0.08)], layout: titledLayout, draftId: draftId)
        try check(explicitWeeks.first?.weekRule.resolvedWeeks(upTo: 20) == [1, 3, 9, 11], "课程显式周次优先，不被表头第9周覆盖")
        let otherLayout = try require(calendarParser.layout(in: calendarBlocks + [block("第12周", 0.02, 0.005, 0.3)]))
        let otherWeek = calendarParser.parse([mobileCards[0]], blocks: mobileText, layout: otherLayout, draftId: draftId)
        try check(otherWeek.first?.weekRule.resolvedWeeks(upTo: 20) == [12], "自动默认值使用实际图片周数，不固定为第9周")
        let chineseLayout = try require(calendarParser.layout(in: calendarBlocks + [block("第九周", 0.02, 0.005, 0.3)]))
        try check(chineseLayout.displayedWeek == 9, "识别中文数字第九周")
        let ambiguousLayout = try require(calendarParser.layout(in: calendarBlocks + [block("第9周 / 第10周", 0.02, 0.005, 0.3)]))
        try check(ambiguousLayout.displayedWeek == nil, "表头出现不同周数时不自动选周")
        let zeroLayout = try require(calendarParser.layout(in: calendarBlocks + [block("第0周", 0.02, 0.005, 0.3)]))
        try check(zeroLayout.displayedWeek == nil, "无效零周不作为默认值")
        var outsideSemester = defaultWeekEntries[0]
        outsideSemester.revalidate(weekCount: 8)
        try check(outsideSemester.issues.contains { $0.code == ImportIssueCode.weekOutOfSemesterRange.rawValue },
            "自动周次仍受目标学期周数校验")
        let cardImage = try makeCardFixture(mobileCards)
        let detectedCards = TimetableImageCardDetector().detect(in: cardImage, layout: layout)
        try check(detectedCards.count == 2 && detectedCards.contains { $0.weekday == .wednesday && $0.startPeriod == 5 && $0.endPeriod == 8 }, "彩色卡片边界正确还原跨多节安排")

        let classParser = TimetableImageClassTableParser()
        let reviewClass = TimetableImageClassOption(id: "计算机2401班", name: "计算机2401班", code: 2401, shortNumber: 1, prefix: "计算机")
        let reviewCell = TimetableImageClassTableLayout.Cell(bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            weekday: .monday, startPeriod: 1, endPeriod: 2)
        let reviewLayout = TimetableImageClassTableLayout(classes: [reviewClass], cellsByClass: [reviewClass.id: [reviewCell]])
        func classCourses(_ lines: [String]) -> [ImportDraftEntry] {
            let blocks = lines.enumerated().map { block($0.element, 0.2, 0.1 + Double($0.offset) * 0.06, 0.6) }
            return classParser.parse(blocks, layout: reviewLayout, selectedClassID: reviewClass.id, draftId: draftId)
        }
        let multilineWeeks = classCourses(["高等数学", "1-8周", "教三201"])
        var multilineCourse = try require(multilineWeeks.first)
        multilineCourse.revalidate(weekCount: 20)
        try check(multilineWeeks.count == 1 && multilineCourse.weekRule.resolvedWeeks(upTo: 20) == Array(1...8)
            && multilineCourse.status == .ready && multilineCourse.isSelected && multilineCourse.location == "教三201",
            "班级课表换行周次保持原范围，不扩展到全学期")
        let wrappedName = classCourses(["Data", "Structures", "1-8周", "教三201"])
        try check(wrappedName.count == 1 && wrappedName[0].weekRule.resolvedWeeks(upTo: 20) == Array(1...8),
            "课程名称自身换行时仍保留后续周规则")
        let classExclusions = classCourses(["高等数学1-16周（除4、8周）", "教三201"])
        var classExcludedCourse = try require(classExclusions.first)
        classExcludedCourse.revalidate(weekCount: 20)
        try check(classExclusions.count == 1 && classExcludedCourse.weekRule.resolvedWeeks(upTo: 20) == (1...16).filter { ![4, 8].contains($0) }
            && classExcludedCourse.status == .ready && classExcludedCourse.location == "教三201",
            "班级课表排除周归属原课程，不生成额外安排或混入教室")
        let classRanges = classCourses(["Data Structures1-8周、10-16周", "教三201"])
        try check(classRanges.count == 1 && classRanges[0].courseName == "Data Structures"
            && classRanges[0].weekRule.resolvedWeeks(upTo: 20) == Array(1...8) + Array(10...16),
            "班级课表重复周单位合为同一规则，保留英文课名")
        let classOdd = classCourses(["离散数学", "1-8周、10-16周", "(单)", "除3、11周", "教三201"])
        try check(classOdd.count == 1 && classOdd[0].weekRule.resolvedWeeks(upTo: 20) == [1, 5, 7, 13, 15]
            && classOdd[0].weekRule.validationErrors.isEmpty && classOdd[0].location == "教三201",
            "班级课表跨行周次、单双周与排除周共同生效且通过校验")
        let separateCourses = classCourses(["高等数学1-8周（除4、6周）", "教三201(计算机1班)", "大学物理10-16周", "教三202(计算机1班)"])
        try check(separateCourses.map(\.courseName) == ["高等数学", "大学物理"]
            && separateCourses[0].weekRule.resolvedWeeks(upTo: 20) == [1, 2, 3, 5, 7, 8]
            && separateCourses[1].weekRule.resolvedWeeks(upTo: 20) == Array(10...16)
            && separateCourses.map(\.location) == ["教三201", "教三202"], "排除周不影响同格的下一门课程与分班教室")
        let classFixture = try makeClassTableFixture()
        let classLayout = try require(classParser.layout(in: classFixture.blocks, image: classFixture.image))
        try check(classLayout.classes.map(\.name) == ["计算机111班", "计算机112班"], "从横向班级表头发现班级，保留专业前缀")
        let ocrPeriods = classFixture.blocks.map {
            TimetableOCRBlock(text: $0.text.replacingOccurrences(of: "1-2", with: "1ー2"),
                bounds: $0.bounds, confidence: $0.confidence)
        }
        let recoveredLayout = try require(classParser.layout(in: ocrPeriods, image: classFixture.image))
        let recoveredFirst = classParser.parse(ocrPeriods, layout: recoveredLayout,
            selectedClassID: recoveredLayout.classes[0].id, draftId: draftId)
        try check(recoveredFirst.contains { $0.startPeriod == 1 && $0.endPeriod == 2 && $0.location == "西十二楼S201" },
            "iOS把课节横线识别为长音符时仍还原第一节课程")
        try check(TimetableImageLayoutParser.normalize("DataーScience 4−7周 计8－9班") == "DataーScience 4-7周 计8-9班",
            "仅归一化数字范围，不改课程名称中的长音符")
        try check(TimetableImageClassTableParser.restoringRoomPrefixes(in: "十二楼S308(计5班)", from: ["西十二楼S308"]) == "西十二楼S308(计5班)",
            "局部重读漏字时从同格整图证据恢复完整教室名称")
        try check(TimetableImageClassTableParser.restoringRoomPrefixes(in: "十二楼S308", from: ["西十二楼S308", "东十二楼S308"]) == "十二楼S308"
            && TimetableImageClassTableParser.restoringRoomPrefixes(in: "十二楼S308", from: ["西十二楼S309"]) == "十二楼S308",
            "教室原词有歧义或没有证据时不猜缺失首字")
        let firstClass = classParser.parse(classFixture.blocks, layout: classLayout,
            selectedClassID: classLayout.classes[0].id, draftId: draftId)
        let secondClass = classParser.parse(classFixture.blocks, layout: classLayout,
            selectedClassID: classLayout.classes[1].id, draftId: draftId)
        try check(firstClass.first?.location == "西十二楼S201" && secondClass.first?.location == "西十二楼S202",
            "跨班合并单元格按班级分配教室，不拼入其他班教室")
        try check(firstClass.contains { $0.courseName == "线性代数(A)" && $0.weekday == .monday }
            && !firstClass.contains { $0.courseName == "大学物理" }
            && secondClass.contains { $0.courseName == "大学物理" }, "纵向星期与跨班分隔线决定各班自己的课程")
        let unknownGroups = firstClass.filter { $0.imageReview?.requiresClassReview == true }
        try check(unknownGroups.count == 2 && unknownGroups.allSatisfy { !$0.isSelected && $0.status == .skipped }
            && Set(unknownGroups.compactMap { $0.imageReview?.classGroup }) == ["课堂1", "课堂2"],
            "课堂1不自动对应行政班1，未知分组逐条保留且默认跳过")
        let lostBrackets = classFixture.blocks.map {
            TimetableOCRBlock(text: $0.text.replacingOccurrences(of: "(课堂1)", with: "课堂1")
                .replacingOccurrences(of: "(课堂2)", with: "课堂2"), bounds: $0.bounds, confidence: $0.confidence)
        }
        let lostBracketCourses = classParser.parse(lostBrackets, layout: classLayout,
            selectedClassID: classLayout.classes[0].id, draftId: draftId).filter { $0.courseName == "计算思维" }
        try check(!lostBracketCourses.isEmpty && lostBracketCourses.allSatisfy { !$0.isSelected && $0.imageReview?.requiresClassReview == true },
            "OCR丢失分组括号时仍识别课堂提示，不意外默认纳入")
        try check(firstClass.contains { $0.courseName == "工程训练" && $0.startPeriod == 3 && $0.endPeriod == 6 },
            "纵向合并单元格从实际边线和多个课节标签还原跨度")
        try check(classParser.parse(classFixture.blocks, layout: classLayout, selectedClassID: "不存在的班", draftId: draftId).isEmpty,
            "无效班级不落入第一个班或全部班级")
        let oldReview = try JSONDecoder().decode(ImportImageReview.self,
            from: Data(#"{"notes":[],"requiresWeekConfirmation":false}"#.utf8))
        try check(oldReview.requiresClassReview == nil && oldReview.selectedClassName == nil,
            "新增班级核对信息兼容旧版图片草稿")
        let savedGroups = try JSONDecoder().decode([ImportDraftEntry].self, from: JSONEncoder().encode(unknownGroups))
        try check(savedGroups.allSatisfy { !$0.isSelected && $0.imageReview?.requiresClassReview == true },
            "默认跳过、班级和课堂分组提示在草稿恢复后仍保留")

        #if !IMAGE_IMPORT_LAYOUT_ONLY
        let store = AppStore()
        let semester = try store.createSemester(name: "图片导入测试", startDate: CalendarDate(year: 2026, month: 9, day: 7)!, endDate: CalendarDate(year: 2027, month: 1, day: 24)!)
        let imported = try await store.createImportDraft(fromImageData: Data([1]), fileName: "测试.png", semesterId: semester.id, recognizer: StubRecognizer(entries: entries))
        try check(store.data.courses.isEmpty && store.data.scheduleEntries.isEmpty, "识别成功只保存草稿，不写入正式课表")
        try check(imported.entries.allSatisfy { $0.draftId == imported.id } && imported.sourceKind == .image, "候选记录归属正确草稿且通过现有校验")
        let saved = try JSONEncoder().encode(store.data)
        let restored = try JSONDecoder().decode(AppData.self, from: saved)
        try check(restored.importDrafts.first?.entries.count == 3, "图片草稿可按现有 JSON 格式持久化恢复")
        do {
            _ = try store.commitImportDraft(draftId: imported.id, userConfirmed: false)
            throw CheckFailure(message: "未经确认不应提交")
        } catch is AppError {}
        try check(store.data.courses.isEmpty, "未确认提交时课程保持为空")
        let committed = try store.commitImportDraft(draftId: imported.id, userConfirmed: true)
        try check(committed.succeeded && store.data.scheduleEntries.count == 3, "确认后通过现有提交链路生成正式课程")

        let before = store.importDrafts.count
        do {
            _ = try await store.createImportDraft(fromImageData: Data(), fileName: "空.png", semesterId: semester.id, recognizer: StubRecognizer(entries: []))
            throw CheckFailure(message: "空识别结果不应成功")
        } catch is AppError {}
        try check(store.importDrafts.count == before, "失败不遗留空草稿")
        let task = Task { @MainActor in
            try await store.createImportDraft(fromImageData: Data(), fileName: "取消.png", semesterId: semester.id, recognizer: StubRecognizer(entries: entries))
        }
        task.cancel()
        do { _ = try await task.value; throw CheckFailure(message: "取消不应成功") } catch is CancellationError {}
        try check(store.importDrafts.count == before, "取消识别不保存草稿")

        let mobileDraft = try await store.createImportDraft(fromImageData: Data([1]), fileName: "手机周视图.png", semesterId: semester.id, recognizer: StubRecognizer(entries: mobileEntries))
        try check(mobileDraft.status == .notStarted && !mobileDraft.status.isFinished, "待核对图片草稿保持尚未提交，可退出后继续")
        let oldCount = store.data.scheduleEntries.count
        let blocked = try store.commitImportDraft(draftId: mobileDraft.id, userConfirmed: true)
        try check(!blocked.succeeded && store.data.scheduleEntries.count == oldCount, "直接确认提交仍会拦截未核对周次，正式数据不变")
        let activeEntry = mobileDraft.entries[0]
        var mobileEdit = ImportEntryEdit(entry: activeEntry)
        mobileEdit.weekRule = WeekRule(startWeek: 9, endWeek: 9)
        let stillBlocked = try store.updateImportEntry(draftId: mobileDraft.id, entryId: activeEntry.id, edit: mobileEdit)
        try check(stillBlocked.imageReview?.requiresWeekConfirmation == true, "普通字段修改不会绕过周次核对")
        mobileEdit.confirmsImageWeeks = true
        _ = try store.updateImportEntry(draftId: mobileDraft.id, entryId: activeEntry.id, edit: mobileEdit)
        let mobileCommitted = try store.commitImportDraft(draftId: mobileDraft.id, userConfirmed: true)
        try check(mobileCommitted.succeeded && store.data.scheduleEntries.count == oldCount + 1, "明确核对周次后只提交选中安排，非本周记录保持跳过")

        let automaticStore = AppStore()
        let automaticSemester = try automaticStore.createSemester(name: "图片默认周次测试", startDate: CalendarDate(year: 2026, month: 8, day: 31)!, endDate: CalendarDate(year: 2027, month: 1, day: 17)!)
        let automaticDraft = try await automaticStore.createImportDraft(fromImageData: Data([1]), fileName: "第9周.png", semesterId: automaticSemester.id, recognizer: StubRecognizer(entries: defaultWeekEntries))
        try check(automaticDraft.status == .readyToCommit, "图片周次已明确的草稿直接达到可提交状态")
        let automaticRestored = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(automaticStore.data))
        try check(automaticRestored.importDrafts.first?.entries.first?.weekRule.resolvedWeeks(upTo: 20) == [9], "自动填入的单周规则可持久化恢复")
        let automaticCommit = try automaticStore.commitImportDraft(draftId: automaticDraft.id, userConfirmed: true)
        try check(automaticCommit.succeeded && automaticStore.data.scheduleEntries.count == 1,
            "不调用编辑或手动选周，确认后直接写入已识别周次")

        var legacyEntry = mobileEntries[0]
        legacyEntry.imageReview = ImportImageReview(notes: ["截图显示第9周，完整上课周次未知，请在修改记录中选择并确认。"], requiresWeekConfirmation: true)
        var legacySkipped = mobileEntries[1]
        legacySkipped.imageReview = legacyEntry.imageReview
        var legacyData = AppData.empty
        legacyData.semesters = [automaticSemester]
        legacyData.importDrafts = [ImportDraft(semesterId: automaticSemester.id, sourceKind: .image, entries: [legacyEntry, legacySkipped])]
        let migrated = legacyData.migrated()
        try check(migrated.importDrafts[0].status == .readyToCommit
            && migrated.importDrafts[0].entries[0].weekRule.resolvedWeeks(upTo: 20) == [9], "已有未填写周次的旧图片草稿也自动恢复第9周")
        try check(migrated.importDrafts[0].entries[1].imageReview?.requiresWeekConfirmation == true
            && migrated.importDrafts[0].entries[1].startWeek == nil, "旧草稿迁移仍跳过非本周记录")
        legacyData.importDrafts[0].entries[0].weekRule = WeekRule(startWeek: 3, endWeek: 5)
        try check(legacyData.migrated().importDrafts[0].entries[0].weekRule.resolvedWeeks(upTo: 20) == [3, 4, 5], "旧草稿里手动设置的周次保持原值")
        legacyData.importDrafts[0].entries[0] = legacyEntry
        legacyData.importDrafts[0].status = .succeeded
        try check(legacyData.migrated().importDrafts[0].entries[0].imageReview?.requiresWeekConfirmation == true, "已提交草稿与正式安排不参与默认周次迁移")
        #endif

        let vision = VisionTimetableImageRecognizer()
        do {
            _ = try await vision.recognize(imageData: Data([0, 1, 2]), fileName: "损坏.png")
            throw CheckFailure(message: "损坏图片不应成功")
        } catch is AppError {}
        try check(true, "损坏图片给出明确的解析错误")
        do {
            _ = try await vision.recognize(imageData: Data(repeating: 0, count: 20 * 1024 * 1024 + 1), fileName: "超限.png")
            throw CheckFailure(message: "超限图片不应成功")
        } catch is AppError {}
        try check(true, "20 MB 限制在图片解码之前生效")
        if CommandLine.arguments.contains("--ocr") {
            let data = try makeFixture()
            let recognized = try await vision.recognize(imageData: data, fileName: "synthetic-timetable.png")
            print("OCR courses: \(recognized.map { "\($0.courseName):\($0.weekday?.shortName ?? "?")" }.joined(separator: ", "))")
            try check(recognized.contains { $0.courseName.contains("数学") && $0.weekday == .monday }, "真实 Vision OCR 从合成图片识别星期与课程")
            try check(recognized.contains { $0.courseName.contains("物理") && $0.weekday == .tuesday }, "真实 Vision OCR 区分相邻星期列")
        }

        if let index = CommandLine.arguments.firstIndex(of: "--school-image"), CommandLine.arguments.indices.contains(index + 1) {
            let image = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            let schoolRecognizer = VisionTimetableImageRecognizer()
            let options = try await schoolRecognizer.classOptions(imageData: image)
            try check(options.map(\.name) == (2601...2611).map { "计算机\($0)班" }, "真实学校总课表发现完整11个班级")
            do {
                _ = try await schoolRecognizer.recognize(imageData: image, fileName: "多班级.png")
                throw CheckFailure(message: "未选班级不能生成全部班级混合草稿")
            } catch is AppError {}
            try check(true, "多班级未选择时要求选班，不默认第一个班")
            let englishRooms = ["西十二楼S205", "西十二楼S206", "西十二楼S207", "西十二楼N307", "西十二楼S308", "西十二楼N305", "西五楼205", "西十二楼N207", "西十二楼N207", "西十二楼S206", "西十二楼S205"]
            let cRooms = ["西十二楼S411", "西十二楼S411", "西十二楼S411", "西十二楼S409", "西十二楼S409", "西十二楼S409", "西十二楼S412", "西十二楼S412", "西十二楼S412", "西十二楼S505", "西十二楼S505"]
            for (offset, option) in options.enumerated() {
                let candidates = try await schoolRecognizer.recognize(imageData: image, fileName: "多班级.png", selectedClassID: option.id)
                let mondayEnglish = candidates.first { $0.weekday == .monday && $0.startPeriod == 1 }
                let wednesdayC = candidates.first { $0.weekday == .wednesday && $0.startPeriod == 3 }
                let lab = candidates.first { $0.courseName == "C语言程序设计实验" }
                let linear = candidates.first { $0.weekday == .tuesday && $0.courseName == "线性代数(A)" }
                try check(candidates.count == 28 && candidates.filter(\.isSelected).count == 18
                    && candidates.filter { $0.imageReview?.requiresClassReview == true }.allSatisfy { !$0.isSelected }
                    && mondayEnglish?.location == englishRooms[offset] && wednesdayC?.location == cRooms[offset]
                    && lab?.weekday == (offset < 6 ? .thursday : .wednesday)
                    && linear?.startPeriod == (offset < 6 ? 5 : 7),
                    "真实\(option.name)：18条明确记录、10条跳过，教室和跨班实验安排正确")
                let practice = candidates.first { $0.courseName == "新生实践课" && $0.imageReview?.classGroup == "课堂2" }
                try check(practice?.weekRule.resolvedWeeks(upTo: 20) == [4, 5, 6, 7, 9, 10, 11, 12]
                    && candidates.contains { $0.courseName == "计算思维" && $0.startPeriod == 9 && $0.startWeek == 16 && $0.endWeek == 17 },
                    "真实\(option.name)：同格多课程、多组周次互不覆盖")
            }
            #if !IMAGE_IMPORT_LAYOUT_ONLY
            let schoolStore = AppStore()
            let schoolSemester = try schoolStore.createSemester(name: "多班级原图测试", startDate: CalendarDate(year: 2026, month: 8, day: 31)!, endDate: CalendarDate(year: 2027, month: 1, day: 17)!)
            let schoolDraft = try await schoolStore.createImportDraft(fromImageData: image, fileName: "多班级.png", semesterId: schoolSemester.id,
                recognizer: ClassSelectedTimetableImageRecognizer(recognizer: schoolRecognizer, selectedClassID: options[0].id))
            try check(schoolDraft.status == .readyToCommit && schoolDraft.readyCount == 18 && schoolStore.data.courses.isEmpty,
                "多班级识别只生成18条可提交草稿，未知分组不阻塞明确课程")
            let schoolResult = try schoolStore.commitImportDraft(draftId: schoolDraft.id, userConfirmed: true)
            try check(schoolResult.succeeded && schoolStore.data.scheduleEntries.count == 18
                && !schoolStore.data.courses.contains { $0.name == "计算思维" || $0.name == "新生实践课" },
                "确认后仅写入18条选中安排，10条未知分组未进入正式课表")
            #endif
        }
        if let index = CommandLine.arguments.firstIndex(of: "--phone-image"), CommandLine.arguments.indices.contains(index + 1) {
            let image = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            let options = try await vision.classOptions(imageData: image)
            let candidates = try await vision.recognize(imageData: image, fileName: "原手机课表.png")
            try check(options.isEmpty && candidates.count == 9 && candidates.filter(\.isSelected).count == 6
                && candidates.filter(\.isSelected).allSatisfy { $0.weekRule.resolvedWeeks(upTo: 20) == [9] },
                "原手机图片仍识别9条、选中6条并自动填第9周，无需班级选择")
        }
        print("\n\(count) image import checks passed.")
        report.append("\(count) image import checks passed.")
    }

    @MainActor
    static func makeClassTableFixture() throws -> (image: CGImage, blocks: [TimetableOCRBlock]) {
        let width = 1000, height = 1000
        var pixels = [UInt8](repeating: 255, count: width * height)
        func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
            let minX = max(0, Int(min(x1, x2) * Double(width)) - 1), maxX = min(width - 1, Int(max(x1, x2) * Double(width)) + 1)
            let minY = max(0, Int(min(y1, y2) * Double(height)) - 1), maxY = min(height - 1, Int(max(y1, y2) * Double(height)) + 1)
            for y in minY...maxY { for x in minX...maxX { pixels[y * width + x] = 0 } }
        }
        for x in [0.0, 0.08, 0.16, 0.98] { line(x, 0, x, 0.9) }
        line(0.58, 0, 0.58, 0.15); line(0.58, 0.3, 0.58, 0.5)
        for y in [0.0, 0.15, 0.5, 0.9] { line(0, y, 0.98, y) }
        for y in [0.3, 0.65] { line(0.08, y, 0.98, y) }
        line(0.08, 0.77, 0.16, 0.77)
        func b(_ text: String, _ x: Double, _ y: Double, _ width: Double) -> TimetableOCRBlock {
            .init(text: text, bounds: CGRect(x: x, y: y, width: width, height: 0.025), confidence: 1)
        }
        let blocks = [b("计算机", 0.25, 0.02, 0.12), b("111班", 0.23, 0.07, 0.16),
            b("计算机", 0.68, 0.02, 0.12), b("112班", 0.66, 0.07, 0.16),
            b("星期一", 0.005, 0.31, 0.06), b("星期二", 0.005, 0.69, 0.06),
            b("1-2", 0.095, 0.20, 0.05), b("3-4", 0.095, 0.38, 0.05),
            b("1-2", 0.095, 0.56, 0.05), b("3-4", 0.095, 0.69, 0.05), b("5-6", 0.095, 0.82, 0.05),
            b("综合英语 1-8周 西十二楼S201(计1班) 西十二楼S202(计2班)", 0.18, 0.20, 0.75),
            b("线性代数(A) 2-16周 西十二楼N109(计1班)", 0.18, 0.36, 0.36),
            b("大学物理 3-15周 西十二楼N110(计2班)", 0.60, 0.36, 0.35),
            b("计算思维 3-9周 西十二楼S302(课堂1) 西十二楼S304(课堂2)", 0.18, 0.56, 0.75),
            b("工程训练 4-13周 工程中心(计1-2班)", 0.28, 0.74, 0.5)]
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = try require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
            bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [], provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        return (image, blocks)
    }

    static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw CheckFailure(message: "缺少预期记录") }
        return value
    }

    @MainActor
    private static func writeReport() throws {
        guard let index = CommandLine.arguments.firstIndex(of: "--report"),
              CommandLine.arguments.indices.contains(index + 1) else { return }
        try report.joined(separator: "\n").write(toFile: CommandLine.arguments[index + 1], atomically: true, encoding: .utf8)
    }

    @MainActor
    static func makeCardFixture(_ cards: [TimetableImageCard]) throws -> CGImage {
        let width = 800, height = 1200
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor(calibratedRed: 0.75, green: 0.8, blue: 0.88, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        for card in cards {
            NSColor(calibratedRed: 0.3, green: 0.55, blue: 0.95, alpha: 1).setFill()
            let b = card.bounds
            NSRect(x: b.minX * CGFloat(width), y: (1 - b.maxY) * CGFloat(height), width: b.width * CGFloat(width), height: b.height * CGFloat(height)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        return try require(bitmap.cgImage)
    }

    @MainActor
    static func makeFixture() throws -> Data {
        let width = 1200, height = 900
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        func text(_ value: String, _ x: Int, _ y: Int, size: CGFloat = 32) {
            (value as NSString).draw(at: NSPoint(x: x, y: height - y - 45), withAttributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.black])
        }
        text("星期一", 260, 70); text("星期二", 610, 70); text("星期三", 960, 70)
        text("1-2节", 20, 280, size: 26); text("3-4节", 20, 620, size: 26)
        text("高等数学", 250, 210); text("1-16周", 250, 260); text("王老师", 250, 310); text("教三201", 250, 360)
        text("大学物理", 600, 550); text("1-16周", 600, 600); text("第3-4节", 600, 650); text("李老师", 600, 700)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CheckFailure(message: "无法生成合成夹具") }
        try png.write(to: URL(fileURLWithPath: ".build/synthetic-timetable.png"))
        return png
    }
}

private struct CheckFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

private struct StubRecognizer: TimetableImageRecognizer {
    let entries: [ImportDraftEntry]
    func recognize(imageData: Data, fileName: String) async throws -> [ImportDraftEntry] { entries }
}
