import Foundation
import CoreGraphics

/// 学校总课表：横向班级、纵向星期，单元格可横跨多个班或多个课节。
struct TimetableImageClassOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let code: Int
    let shortNumber: Int
    let prefix: String
}

struct TimetableImageClassTableLayout: Sendable {
    struct Cell: Sendable {
        let bounds: CGRect
        let weekday: Weekday
        let startPeriod: Int
        let endPeriod: Int?
    }
    let classes: [TimetableImageClassOption]
    let cellsByClass: [String: [Cell]]
}

struct TimetableImageClassTableParser: Sendable {
    func layout(in blocks: [TimetableOCRBlock], image: CGImage) -> TimetableImageClassTableLayout? {
        let days = blocks.compactMap { block -> (Weekday, TimetableOCRBlock)? in
            let token = block.text.filter { !$0.isWhitespace }
            guard let captures = Self.captures(#"^(?:星期|周|礼拜)([一二三四五六日天1-7])$"#, token),
                  let day = PlainTextTimetableParser.weekday(from: captures[0]) else { return nil }
            return (day, block)
        }.sorted { $0.1.bounds.midY < $1.1.bounds.midY }
        guard days.count >= 2, Set(days.map { $0.0 }).count == days.count,
              zip(days, days.dropFirst()).allSatisfy({ $0.0.rawValue < $1.0.rawValue }),
              let firstDay = days.first, let lastDay = days.last,
              lastDay.1.bounds.midY - firstDay.1.bounds.midY > 0.08,
              days.allSatisfy({ abs($0.1.bounds.midX - firstDay.1.bounds.midX) < 0.035 }) else { return nil }

        let headers = blocks.compactMap { block -> (String, String, TimetableOCRBlock)? in
            let text = TimetableImageLayoutParser.normalize(block.text).filter { !$0.isWhitespace }
            guard block.bounds.maxY < firstDay.1.bounds.minY,
                  block.bounds.minX > firstDay.1.bounds.maxX,
                  let captures = Self.captures(#"^([^0-9()]*?)([0-9]{1,6})班(?:\([0-9]+人\))?$"#, text) else { return nil }
            return (captures[0], captures[1], block)
        }.sorted { $0.2.bounds.midX < $1.2.bounds.midX }
        guard let seed = headers.first, headers.count >= 2,
              headers.allSatisfy({ abs($0.2.bounds.midY - seed.2.bounds.midY) < max(seed.2.bounds.height, 0.012) }),
              Set(headers.map { $0.1 }).count == headers.count,
              let raster = TimetableRuledImage(image) else { return nil }

        let headerTop = max(0, blocks.filter {
            $0.bounds.maxY <= seed.2.bounds.minY && $0.bounds.midX > firstDay.1.bounds.maxX
        }.map { $0.bounds.minY }.min() ?? seed.2.bounds.minY - seed.2.bounds.height)
        let headerBottom = min(firstDay.1.bounds.minY, headers.map { $0.2.bounds.maxY }.max()! + seed.2.bounds.height)
        // 截图的右边缘可能正好裁掉最外侧边框；仍保留完整可见的最后一班。
        let verticals = raster.verticalRules(top: headerTop, bottom: headerBottom, left: 0, right: 1) + [1]
        guard let bodyLeft = verticals.last(where: { $0 < seed.2.bounds.minX }),
              bodyLeft > firstDay.1.bounds.maxX else { return nil }
        let dayRight = raster.verticalRules(top: firstDay.1.bounds.minY,
            bottom: lastDay.1.bounds.maxY, left: firstDay.1.bounds.maxX, right: bodyLeft).first
        guard let dayRight, dayRight < bodyLeft else { return nil }
        let dayRules = raster.horizontalRules(left: firstDay.1.bounds.minX * 0.4, right: dayRight * 0.9)
        // 表格必须实际存在边线；不能用文字间距猜合并单元格。
        guard let bodyTop = dayRules.last(where: { $0 < firstDay.1.bounds.minY }) else { return nil }
        let periodBlocks = blocks.compactMap { block -> (Int, Int, CGFloat)? in
            guard block.bounds.midX > dayRight, block.bounds.maxX < bodyLeft,
                  block.bounds.midY > bodyTop,
                  let values = Self.captures(#"^第?\s*([0-9]{1,2})\s*[-–—~～至到]\s*([0-9]{1,2})\s*节?$"#, TimetableImageLayoutParser.normalize(block.text)),
                  let start = Int(values[0]), let end = Int(values[1]),
                  start >= 1, end >= start, end <= 30 else { return nil }
            return (start, end, block.bounds.midY)
        }
        guard periodBlocks.count >= 2 else { return nil }

        var common = Array(headers[0].1)
        for header in headers.dropFirst() {
            common = Array(zip(common, Array(header.1)).prefix { $0 == $1 }.map { $0.0 })
        }
        var classes: [TimetableImageClassOption] = []
        var cellsByClass: [String: [TimetableImageClassTableLayout.Cell]] = [:]
        for header in headers {
            let block = header.2
            let above = blocks.filter {
                $0.bounds.maxY <= block.bounds.minY + 0.003
                    && block.bounds.minY - $0.bounds.maxY < block.bounds.height * 1.5
                    && abs($0.bounds.midX - block.bounds.midX) < block.bounds.width * 0.45
                    && Self.captures(#"^[\p{Han}A-Za-z]+$"#, $0.text) != nil
            }.max { $0.bounds.maxY < $1.bounds.maxY }?.text ?? ""
            let prefix = header.0.isEmpty ? above : header.0
            let option = TimetableImageClassOption(id: prefix + header.1 + "班", name: prefix + header.1 + "班",
                code: Int(header.1)!, shortNumber: Int(String(header.1.dropFirst(common.count))) ?? Int(header.1)!, prefix: prefix)
            guard let left = verticals.last(where: { $0 < block.bounds.midX }),
                  let right = verticals.first(where: { $0 > block.bounds.midX }), right - left > 0.012 else { continue }
            classes.append(option)
            let inset = min((right - left) * 0.15, 0.008)
            var rows = raster.horizontalRules(left: left + inset, right: right - inset).filter { $0 >= bodyTop - 0.003 }
            let closedBottom = rows.last.map { $0 > 0.995 } ?? false
            if rows.last.map({ $0 < 0.995 }) ?? true { rows.append(1) }
            var cells: [TimetableImageClassTableLayout.Cell] = []
            for (top, bottom) in zip(rows, rows.dropFirst()) where bottom - top > 0.008 {
                let periods = periodBlocks.filter { $0.2 > top && $0.2 < bottom }.sorted { $0.2 < $1.2 }
                guard let first = periods.first, let last = periods.last,
                      let dayIndex = days.indices.first(where: { index in
                          let labelY = days[index].1.bounds.midY
                          let dayTop = dayRules.last(where: { $0 < labelY }) ?? bodyTop
                          let dayBottom = dayRules.first(where: { $0 > labelY }) ?? 1
                          return top >= dayTop - 0.003 && bottom <= dayBottom + 0.003
                      }) else { continue }
                let walls = raster.verticalRules(top: top + 0.002, bottom: bottom - 0.002, left: bodyLeft - 0.002, right: 1) + [1]
                guard let cellLeft = walls.last(where: { $0 < block.bounds.midX }),
                      let cellRight = walls.first(where: { $0 > block.bounds.midX }) else { continue }
                let isClosed = bottom < 0.999 || closedBottom
                cells.append(.init(bounds: CGRect(x: cellLeft, y: top, width: cellRight - cellLeft, height: bottom - top),
                    weekday: days[dayIndex].0, startPeriod: first.0, endPeriod: isClosed ? last.1 : nil))
            }
            cellsByClass[option.id] = cells
        }
        guard classes.count >= 2, cellsByClass.values.contains(where: { !$0.isEmpty }) else { return nil }
        return .init(classes: classes, cellsByClass: cellsByClass)
    }

    static func captures(_ pattern: String, _ text: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }

    /// 局部 OCR 偶尔漏掉教室首字；只补回整图同一单元格里唯一、明确的原词。
    static func restoringRoomPrefixes(in text: String, from originalRooms: [String]) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"[\p{Han}]+[A-Za-z]?[0-9]{3,5}"#) else { return text }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: text) else { continue }
            let room = String(text[range])
            guard !originalRooms.contains(room) else { continue }
            let candidates = Set(originalRooms.filter {
                $0.hasSuffix(room) && (1...2).contains($0.count - room.count)
            })
            if candidates.count == 1, let original = candidates.first,
               let replacementRange = Range(match.range, in: result) {
                result.replaceSubrange(replacementRange, with: original)
            }
        }
        return result
    }
}

extension TimetableImageClassTableParser {
    func parse(_ blocks: [TimetableOCRBlock], layout: TimetableImageClassTableLayout,
               selectedClassID: String, draftId: UUID) -> [ImportDraftEntry] {
        guard let selected = layout.classes.first(where: { $0.id == selectedClassID }) else { return [] }
        var result: [ImportDraftEntry] = []
        for cell in layout.cellsByClass[selectedClassID] ?? [] {
            let text = orderedText(blocks.filter {
                cell.bounds.contains(CGPoint(x: $0.bounds.midX, y: $0.bounds.midY))
            })
            guard !text.isBlank else { continue }
            for segment in courseSegments(in: text) {
                let rooms = allocations(in: segment.details)
                let matching = rooms.filter { belongs($0.group, to: selected) == true }
                let unknown = rooms.filter { belongs($0.group, to: selected) == nil }
                if !matching.isEmpty {
                    result.append(makeEntry(segment, cell: cell, selected: selected, draftId: draftId,
                        location: matching.map(\.room).joined(separator: "、"), group: nil,
                        unresolved: matching.count > 1, raw: text))
                }
                // 「课堂1」与行政班号没有必然关系，不能拿课堂序号匹配班号。
                for allocation in unknown {
                    result.append(makeEntry(segment, cell: cell, selected: selected, draftId: draftId,
                        location: allocation.room, group: allocation.group, unresolved: true, raw: text))
                }
                if rooms.isEmpty {
                    let hasUnknownGroup = segment.details.contains("课堂") || segment.details.contains("教学班")
                    result.append(makeEntry(segment, cell: cell, selected: selected, draftId: draftId,
                        location: segment.details.normalizedOrNil, group: hasUnknownGroup ? "课堂分组" : nil,
                        unresolved: hasUnknownGroup, raw: text))
                }
                // 明确只属于其他班的分组不生成所选班级的课程。
            }
        }
        return result.enumerated().map { index, value in
            var entry = value; entry.sourceIndex = index; return entry
        }
    }
}

private extension TimetableImageClassTableParser {
    struct Segment {
        let name: String
        let weeks: String?
        let details: String
    }
    struct Allocation {
        let room: String
        let group: String
    }

    func orderedText(_ blocks: [TimetableOCRBlock]) -> String {
        var rows: [[TimetableOCRBlock]] = []
        for block in blocks.sorted(by: { $0.bounds.midY < $1.bounds.midY }) {
            if let first = rows.last?.first,
               abs(first.bounds.midY - block.bounds.midY) < max(first.bounds.height * 0.55, 0.004) {
                rows[rows.count - 1].append(block)
            } else { rows.append([block]) }
        }
        return TimetableImageLayoutParser.normalize(rows.map {
            $0.sorted { $0.bounds.minX < $1.bounds.minX }.map(\.text).joined(separator: " ")
        }.joined(separator: "\n"))
    }

    func courseSegments(in text: String) -> [Segment] {
        let pattern = TimetableImageLayoutParser.weekListPattern + #"(?:\s*(?:\([单双]周?\)|[单双]周))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let exclusions = TimetableImageLayoutParser.weekExclusionRanges(in: text)
        let ranges = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text) }
            .filter { range in !exclusions.contains { $0.overlaps(range) } }
        guard let first = ranges.first else {
            let lines = text.components(separatedBy: .newlines)
            guard let name = lines.first?.normalizedOrNil, plausibleName(name) else { return [] }
            return [Segment(name: name, weeks: nil, details: lines.dropFirst().joined(separator: " "))]
        }
        var name = String(text[..<first.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard plausibleName(name) else { return [] }
        var result: [Segment] = []
        for index in ranges.indices {
            let range = ranges[index]
            let end = index + 1 < ranges.count ? ranges[index + 1].lowerBound : text.endIndex
            var details = String(text[range.upperBound..<end])
            // 排除周属于当前课程的周规则，不是另一门课，也不是教室分组。
            let excludedWeeks = TimetableImageLayoutParser.weekExclusionRanges(in: details).map { String(details[$0]) }
            let weeks = ([String(text[range])] + excludedWeeks).joined(separator: " ")
            details = TimetableImageLayoutParser.removingWeekExclusions(from: details)
            var nextName: String?
            if index + 1 < ranges.count {
                // 同一单元格可能先写不同分组周次，再在下一行写另一门课。
                let cut = details.lastIndex(of: ")").map { details.index(after: $0) }
                    ?? details.lastIndex(of: "\n").map { details.index(after: $0) }
                if let cut {
                    let suffix = String(details[cut...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if plausibleName(suffix) {
                        nextName = suffix
                        details = String(details[..<cut])
                    }
                }
            }
            result.append(Segment(name: name, weeks: weeks,
                details: details.trimmingCharacters(in: .whitespacesAndNewlines)))
            if let nextName { name = nextName }
        }
        return result
    }

    func plausibleName(_ text: String) -> Bool {
        guard !text.isBlank, text.count <= 100,
              text.rangeOfCharacter(from: .letters) != nil,
              Self.captures(#"(?:楼\s*[A-Za-z0-9]|大楼|课堂\s*[0-9]|^第?[0-9]|^(?:教室|地点|教师)[:：])"#, text) == nil else { return false }
        return true
    }

    func allocations(in details: String) -> [Allocation] {
        guard let regex = try? NSRegularExpression(pattern: #"([^()]+)\(([^()]*)\)"#) else { return [] }
        return regex.matches(in: details, range: NSRange(details.startIndex..., in: details)).compactMap { match in
            guard let roomRange = Range(match.range(at: 1), in: details),
                  let groupRange = Range(match.range(at: 2), in: details),
                  let room = String(details[roomRange])
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "|｜")))
                    .normalizedOrNil else { return nil }
            return Allocation(room: room, group: String(details[groupRange]).replacingOccurrences(of: "\n", with: ""))
        }
    }

    /// true 是本班，false 是明确的其他班，nil 需要用户核对。
    func belongs(_ group: String, to selected: TimetableImageClassOption) -> Bool? {
        if group.contains("课堂") || group.contains("教学班") { return nil }
        let prefixes = Array(Set([selected.prefix, selected.prefix.first.map(String.init) ?? ""]))
            .filter { !$0.isEmpty }.sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }
        let prefix = prefixes.isEmpty ? "" : "(?:" + prefixes.joined(separator: "|") + ")"
        let pattern = #"(?<![\p{Han}A-Za-z0-9])"# + prefix
            + #"\s*([0-9]{1,6}(?:\s*[-–—~～至到,、，]\s*[0-9]{1,6})*)\s*班"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let matches = regex.matches(in: group, range: NSRange(group.startIndex..., in: group))
        guard !matches.isEmpty else { return nil }
        return matches.contains { match in
            guard let range = Range(match.range(at: 1), in: group) else { return false }
            return String(group[range]).components(separatedBy: CharacterSet(charactersIn: ",、，")).contains { piece in
                if let ends = Self.captures(#"^\s*([0-9]+)\s*[-–—~～至到]\s*([0-9]+)\s*$"#, piece),
                   let start = Int(ends[0]), let end = Int(ends[1]), start <= end {
                    return (start...end).contains(selected.code) || (!prefixes.isEmpty && (start...end).contains(selected.shortNumber))
                }
                guard let number = Int(piece.trimmingCharacters(in: .whitespaces)) else { return false }
                return number == selected.code || (!prefixes.isEmpty && number == selected.shortNumber)
            }
        }
    }

    func makeEntry(_ segment: Segment, cell: TimetableImageClassTableLayout.Cell,
                   selected: TimetableImageClassOption, draftId: UUID, location: String?,
                   group: String?, unresolved: Bool, raw: String) -> ImportDraftEntry {
        var entry = ImportDraftEntry(draftId: draftId, sourceIndex: 0, courseName: segment.name,
            location: location, weekday: cell.weekday, startPeriod: cell.startPeriod, endPeriod: cell.endPeriod)
        if let weeks = segment.weeks {
            // 只解析周规则，课程名与 OCR 换行不能让逐行解析器截断这条记录。
            let weekText = weeks.components(separatedBy: .newlines).joined(separator: " ")
            if let parsed = PlainTextTimetableParser().parse("课程," + weekText, draftId: draftId).entries.first {
                entry.weekRule = parsed.weekRule
            }
            TimetableImageLayoutParser().applyWeekRanges(in: weeks, to: &entry)
        }
        var notes: [String] = []
        if unresolved {
            notes.append(group.map { "原图分组「\($0)」暂时无法对应到\(selected.name)，已默认跳过。" }
                ?? "本班对应多个教室，已默认跳过，请对照原图修改。")
        }
        if cell.endPeriod == nil { notes.append("单元格底部被裁切，结束课节待核对；已默认跳过。") }
        if segment.weeks == nil { notes.append("未识别到本课程的上课周次，请在修改记录中选择并确认。") }
        if location == nil { notes.append("未识别到教室，可对照原图补充。") }
        entry.imageReview = ImportImageReview(notes: notes, requiresWeekConfirmation: segment.weeks == nil,
            selectedClassName: selected.name, classGroup: group, requiresClassReview: unresolved)
        entry.rawPayload = "所选班级：\(selected.name)\n" + raw
        entry.isSelected = !unresolved && cell.endPeriod != nil
        entry.status = entry.isSelected ? .parsed : .skipped
        return entry
    }
}

/// 只把长直线作为表格边界，文字笔画不参与单元格跨度推断。
private struct TimetableRuledImage {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init?(_ image: CGImage) {
        let scale = min(1, 2048 / CGFloat(max(image.width, image.height)))
        let width = max(1, Int(CGFloat(image.width) * scale))
        let height = max(1, Int(CGFloat(image.height) * scale))
        var pixels = [UInt8](repeating: 255, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.width = width; self.height = height; self.pixels = pixels
    }

    func horizontalRules(left: CGFloat, right: CGFloat) -> [CGFloat] {
        let start = max(0, min(width - 1, Int(left * CGFloat(width))))
        let end = max(start + 1, min(width, Int(right * CGFloat(width))))
        return runs((0..<height).map { y in
            (start..<end).filter { pixels[y * width + $0] < 160 }.count > Int(Double(end - start) * 0.91)
        }).map { CGFloat($0) / CGFloat(height) }
    }

    func verticalRules(top: CGFloat, bottom: CGFloat, left: CGFloat, right: CGFloat) -> [CGFloat] {
        let start = max(0, min(height - 1, Int(top * CGFloat(height))))
        let end = max(start + 1, min(height, Int(bottom * CGFloat(height))))
        let minX = max(0, min(width - 1, Int(left * CGFloat(width))))
        let maxX = max(minX + 1, min(width, Int(right * CGFloat(width))))
        return runs((minX..<maxX).map { x in
            (start..<end).filter { pixels[$0 * width + x] < 160 }.count > Int(Double(end - start) * 0.91)
        }).map { CGFloat(minX + $0) / CGFloat(width) }
    }

    private func runs(_ flags: [Bool]) -> [Int] {
        var result: [Int] = [], start: Int?
        for index in 0...flags.count {
            if index < flags.count && flags[index] { if start == nil { start = index }; continue }
            if let first = start { result.append((first + index - 1) / 2) }
            start = nil
        }
        return result
    }
}
