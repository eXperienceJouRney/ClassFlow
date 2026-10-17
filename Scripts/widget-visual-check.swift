// 小组件视觉自检：把组件真渲染成 PNG，再用 Vision OCR + 像素采样核对版面。
//
// 断言项：关键文案与上下顺序、底色与分割线、课程块配色、文字截断（`untruncated`）、
// 大课表八行窗口（早上 1–8 / 晚上 5–12）。失败即 exit(1)，可直接当 CI 关卡。
//
// 运行（macOS，不需要模拟器，也不需要 WidgetKit 宿主）：
//
//   cd /Users/ray/classflow
//   xcrun swiftc -O -parse-as-library -DWIDGET_VISUAL_CHECK -o /tmp/classflow-widget-visual \
//     apps/ios/ClassFlow/Models/*.swift \
//     apps/ios/ClassFlow/Services/{AppData,AppDataStore,Inputs,WidgetSnapshotStore}.swift \
//     apps/ios/ClassFlow/Views/Widget/*.swift \
//     Scripts/widget-visual-check.swift
//   /tmp/classflow-widget-visual /Users/ray/classflow/.build
//
// `-parse-as-library` 与 `-DWIDGET_VISUAL_CHECK` 都不能省：前者避免 `@main` 被当脚本；
// 后者让 `WidgetLink` 退化成纯内容，否则 ImageRenderer 渲染不出其内容。
import AppKit
import Foundation
import SwiftUI
import Vision

// MARK: - 画布

let smallSize = CGSize(width: 158, height: 158)
let mediumSize = CGSize(width: 338, height: 158)
let largeSize = CGSize(width: 338, height: 354)
/// widget 内容距卡片边缘的系统内边距
let widgetPadding: CGFloat = 16
/// 渲染倍数（3x 下 9–11pt 的小字刚好能被 OCR 认出；4x 更稳，代价是像素统计变慢）
let renderScale: CGFloat = 4

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

// MARK: - 文案归一化

/// OCR 结果与期望值的比对口径：去掉空白、统一破折号 / 间隔号 / 全角标点。
///
/// Vision 会把 `10:10–11:50 · 第 3–4 节` 认成各种变体，实测见过：
/// - 破折号降级成连字符（`10:10-11:50`）；
/// - 间隔号 `·` 被认成项目符号 `•` 或片假名中点 `・`；
/// - 中英文之间插入空格。
/// 所以两边都按同一套规则压平再比。
func normalize(_ text: String) -> String {
    var result = ""
    for character in text {
        switch character {
        case "–", "—", "−", "‐", "‑", "‒", "―":
            result.append("-")
        case "·", "•", "・", "‧", "∙", "⋅", "●", "°":
            result.append("·")
        case "，":
            result.append(",")
        case "：":
            result.append(":")
        case "；":
            result.append(";")
        case "（":
            result.append("(")
        case "）":
            result.append(")")
        case "！":
            result.append("!")
        case "？":
            result.append("?")
        default:
            if character.isWhitespace { continue }
            result.append(character)
        }
    }
    return result
}

// MARK: - OCR

struct RecognizedLine {
    let text: String
    /// 归一化坐标：0 = 顶部，1 = 底部（Vision 的原点在左下角，这里翻过来）
    let y: Double
    /// 归一化坐标：0 = 最左，1 = 最右
    let x: Double
}

func recognizeText(in image: CGImage) throws -> [RecognizedLine] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["zh-Hans", "en-US"]
    request.usesLanguageCorrection = false

    try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])

    return (request.results ?? [])
        .compactMap { observation -> RecognizedLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return RecognizedLine(
                text: candidate.string,
                y: 1 - observation.boundingBox.midY,
                x: observation.boundingBox.midX
            )
        }
        .sorted { $0.y < $1.y }
}

// MARK: - 像素采样

struct PixelStats {
    let backgroundRatio: Double
    let dividerRatio: Double
    let accentRatio: Double
    let exact: [(String, Double)]

    func ratio(of name: String) -> Double {
        exact.first { $0.0 == name }?.1 ?? 0
    }
}

func pixelStats(of image: CGImage, targets: [(String, (Int, Int, Int))], tolerance: Int = 10) -> PixelStats {
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)

    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return PixelStats(backgroundRatio: 0, dividerRatio: 0, accentRatio: 0, exact: [])
    }

    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    var counts = [Int](repeating: 0, count: targets.count)

    for index in stride(from: 0, to: pixels.count, by: 4) {
        let r = Int(pixels[index])
        let g = Int(pixels[index + 1])
        let b = Int(pixels[index + 2])
        let a = Int(pixels[index + 3])
        guard a > 200 else { continue }

        for (position, target) in targets.enumerated() {
            if abs(r - target.1.0) <= tolerance,
               abs(g - target.1.1) <= tolerance,
               abs(b - target.1.2) <= tolerance {
                counts[position] += 1
            }
        }
    }

    let total = Double(width * height)
    let ratios = Array(zip(targets.map(\.0), counts.map { Double($0) / total }))

    return PixelStats(
        backgroundRatio: ratios.first?.1 ?? 0,
        dividerRatio: ratios.dropFirst().first?.1 ?? 0,
        accentRatio: ratios.count > 2 ? ratios[2].1 : 0,
        exact: Array(ratios)
    )
}

/// 卡片上的彩色像素：组件里除了课程块的配色之外全是灰阶（白 / 黑 / 灰 / 浅灰分割线），
/// 所以「出现了蓝色像素和绿色像素」就等于「大课表真的按课程颜色上色了」，
/// 而且不用去猜系统颜色（`.blue` / `.green`）在各种外观下的具体 RGB。
enum ChromaticFamily {
    case blueish
    case greenish
}

struct ChromaticStats {
    let ratios: [String: Double]

    func ratio(_ name: String) -> Double { ratios[name] ?? 0 }
}

/// 统计彩色像素占比。判定只看通道大小关系，留了足够的余量避开抗锯齿边缘：
/// - 蓝系：b 明显大于 r，且 b 大于 g
/// - 绿系：g 明显大于 r，且 g 大于 b
func chromaticStats(
    of image: CGImage,
    families: [(String, ChromaticFamily)],
    margin: Int = 18
) -> ChromaticStats {
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)

    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return ChromaticStats(ratios: [:])
    }

    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    var counts = [Int](repeating: 0, count: families.count)

    for index in stride(from: 0, to: pixels.count, by: 4) {
        let r = Int(pixels[index])
        let g = Int(pixels[index + 1])
        let b = Int(pixels[index + 2])
        guard Int(pixels[index + 3]) > 200 else { continue }

        for (position, family) in families.enumerated() {
            switch family.1 {
            case .blueish where b - r >= margin && b - g >= margin: counts[position] += 1
            case .greenish where g - r >= margin && g - b >= margin: counts[position] += 1
            default: break
            }
        }
    }

    let total = Double(width * height)
    return ChromaticStats(
        ratios: Dictionary(uniqueKeysWithValues: zip(families.map(\.0), counts.map { Double($0) / total }))
    )
}

// MARK: - 检查项

struct CardCheck {
    let name: String
    let size: CGSize
    /// 卡片底色（同时作为「画布底」）
    let background: (String, (Int, Int, Int))
    /// 字体颜色（`WidgetStyle` 解析出来的）
    let style: WidgetStyle
    /// 需要出现的文案（归一化后包含即可）
    var fragments: [String] = []
    /// **不该**再出现的文案（改版时从卡片上删掉的旧字段，防止又画回来）
    var absent: [String] = []
    /// 图上一旦出现含这些片段的行，那一行就**不许以省略号收尾**。
    ///
    /// 与 `fragments` 的分工：`fragments` 管「这句话在不在」，这一项管「这句话被没被截断」。
    /// 大课表里「西十二楼S401」被吃掉时渲染成 `西十二楼S…`，只有这一项能钉住。
    var untruncated: [String] = []
    /// 必须出现「N 月 N 日 周X」这样的日期行
    var requiresDate: Bool = false
    /// 需要出现的分割线颜色
    var divider: (String, (Int, Int, Int))?
    /// 需要出现的强调色（冲突红）
    var accent: (String, (Int, Int, Int))?
    /// 需要出现的**彩色**像素（按通道关系判定，不依赖具体色值）：名称 → (色系, 面积占比下限)
    var chromatic: [(String, ChromaticFamily, Double)] = []
    /// 前者必须在上方
    var above: [(String, String)] = []
    /// 前者必须在左侧
    var leftOf: [(String, String)] = []
}

// MARK: - 渲染

@MainActor
func render(_ check: CardCheck, content: some View) throws -> (url: URL, image: CGImage, lines: [RecognizedLine], stats: PixelStats, chromatic: ChromaticStats) {
    let canvas = content
        .environment(\.colorScheme, check.style.scheme)
        .environment(\.widgetRenderingMode, .fullColor)
        .padding(widgetPadding)
        .frame(width: check.size.width, height: check.size.height)
        .background(Color(
            red: Double(check.background.1.0) / 255,
            green: Double(check.background.1.1) / 255,
            blue: Double(check.background.1.2) / 255
        ))

    let renderer = ImageRenderer(content: canvas)
    renderer.scale = renderScale

    guard let cgImage = renderer.cgImage else {
        throw NSError(domain: "widget-visual-check", code: 1, userInfo: [NSLocalizedDescriptionKey: "渲染 \(check.name) 失败"])
    }

    guard let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
        throw NSError(domain: "widget-visual-check", code: 2, userInfo: [NSLocalizedDescriptionKey: "PNG 编码 \(check.name) 失败"])
    }

    let url = outputDirectory.appendingPathComponent("widget-\(check.name).png")
    try data.write(to: url)

    var targets: [(String, (Int, Int, Int))] = [check.background]
    if let divider = check.divider { targets.append(divider) }
    if let accent = check.accent { targets.append(accent) }
    while targets.count < 3 { targets.append(("占位", (-1, -1, -1))) }

    let stats = pixelStats(of: cgImage, targets: Array(targets.prefix(3)))
    let chromatic = chromaticStats(
        of: cgImage,
        families: check.chromatic.map { ($0.0, $0.1) }
    )
    let lines = try recognizeText(in: cgImage)

    return (url, cgImage, lines, stats, chromatic)
}

// MARK: - 断言

func verify(
    _ check: CardCheck,
    lines: [RecognizedLine],
    stats: PixelStats,
    chromatic: ChromaticStats,
    failures: inout [String]
) {
    let joined = lines.map(\.text).joined(separator: " | ")
    let haystack = normalize(joined)
    /// 换行处不加分隔的版本：文案被折成两行时（`打开 ClassFlow 查看后续` + `安排`）也能认出整句
    let wrappedHaystack = normalize(lines.map(\.text).joined())

    /// 定位一条已在图上的文字行；**只做单向包含** —— 反向包含会让 `日` 这种单字
    /// 命中 `今日 4 节课…`，把版面顺序判歪。
    func locate(_ fragment: String) -> RecognizedLine? {
        let needle = normalize(fragment)
        guard !needle.isEmpty else { return nil }
        return lines.first { normalize($0.text).contains(needle) }
    }

    if stats.backgroundRatio < 0.5 {
        failures.append("\(check.name)：底色不是 \(check.background.0)（仅 \(percent(stats.backgroundRatio))）")
    }

    if let divider = check.divider, stats.ratio(of: divider.0) < 0.0002 {
        failures.append("\(check.name)：找不到分割线色 \(divider.0)（\(percent(stats.ratio(of: divider.0)))）")
    }

    if let accent = check.accent, stats.ratio(of: accent.0) < 0.0003 {
        failures.append("\(check.name)：找不到强调色 \(accent.0)（\(percent(stats.ratio(of: accent.0)))）")
    }

    for (name, _, minimum) in check.chromatic where chromatic.ratio(name) < minimum {
        failures.append("\(check.name)：找不到\(name)像素（\(percent(chromatic.ratio(name)))，课程块配色没生效？")
    }

    for fragment in check.fragments {
        let needle = normalize(fragment)
        guard !needle.isEmpty else { continue }
        if !haystack.contains(needle), !wrappedHaystack.contains(needle) {
            failures.append("\(check.name)：OCR 没认出「\(fragment)」")
        }
    }

    if check.requiresDate, !hasDateLine(lines) {
        failures.append("\(check.name)：找不到「N 月 N 日 周X」日期行")
    }

    for fragment in check.absent {
        let needle = normalize(fragment)
        guard !needle.isEmpty else { continue }
        // 只在**单行**里查：跨行拼接会把「第1-」+「2节」凑成假命中
        if lines.contains(where: { normalize($0.text).contains(needle) }) {
            failures.append("\(check.name)：不该再出现「\(fragment)」")
        }
    }

    for fragment in check.untruncated {
        let needle = normalize(fragment)
        guard !needle.isEmpty else { continue }

        let hits = lines.filter { normalize($0.text).contains(needle) }
        guard !hits.isEmpty else {
            failures.append("\(check.name)：OCR 没认出「\(fragment)」")
            continue
        }

        for hit in hits where isTruncated(hit.text) {
            failures.append("\(check.name)：含「\(fragment)」的那一行被省略号吃掉了 —— OCR 读到「\(hit.text)」")
        }
    }

    for (upper, lower) in check.above {
        guard let top = locate(upper), let bottom = locate(lower) else { continue }
        if !(top.y < bottom.y) {
            failures.append("\(check.name)：版面顺序不对，「\(upper)」(y=\(format(top.y))) 应该在「\(lower)」(y=\(format(bottom.y))) 上面")
        }
    }

    for (left, right) in check.leftOf {
        guard let lhs = locate(left), let rhs = locate(right) else { continue }
        if !(lhs.x < rhs.x) {
            failures.append("\(check.name)：左右顺序不对，「\(left)」(x=\(format(lhs.x))) 应该在「\(right)」(x=\(format(rhs.x))) 左边")
        }
    }
}

/// 这一行是不是被省略号截断了。
///
/// Vision 对 `…` 的识别不稳定（`…` / `...` / `..` 都见过），所以三种收尾都算截断；
/// 另外只在**结尾**判，避免把文案里本来就有的间隔号当成截断。
func isTruncated(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    return trimmed.hasSuffix("…") || trimmed.hasSuffix("...") || trimmed.hasSuffix("..")
}

func hasDateLine(_ lines: [RecognizedLine]) -> Bool {    for line in lines {
        let text = normalize(line.text)
        guard text.contains("月"), text.contains("日") else { continue }
        if ["周一", "周二", "周三", "周四", "周五", "周六", "周日"].contains(where: text.contains) {
            return true
        }
    }
    return false
}

func percent(_ value: Double) -> String {
    String(format: "%.2f%%", value * 100)
}

func format(_ value: Double) -> String {
    String(format: "%.3f", value)
}

// MARK: - 真实课表那一档的素材（大课表 · 12 节 + 长教室名）

/// 真实课表第 6 周（2026-10-12 ~ 10-18）：纵轴 12 节带 `startMinute`；
/// `03b` / `03c` 共用这份快照、只换时刻，分别覆盖窗口 1–8 与 5–12。
@MainActor
func realWeekSnapshot() -> (snapshot: WidgetSnapshot, monday: Date) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.firstWeekday = 2
    // 2026-10-12（周一，第 6 周第一天）
    let monday = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_791_763_200))
    let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }

    /// 华中科技大学 2026 秋季作息（与 `Scripts/seed-24zhike-simulator.swift` 同一套）：
    /// `(第几节, 上课分钟, 下课分钟)` —— 卡片左轴现在上下课都写，所以两样都要。
    let periodSlots: [(Int, Int, Int)] = [
        (1, 8 * 60, 8 * 60 + 45), (2, 8 * 60 + 55, 9 * 60 + 40),
        (3, 10 * 60 + 10, 10 * 60 + 55), (4, 11 * 60 + 5, 11 * 60 + 50),
        (5, 14 * 60, 14 * 60 + 45), (6, 14 * 60 + 55, 15 * 60 + 40),
        (7, 16 * 60, 16 * 60 + 45), (8, 16 * 60 + 55, 17 * 60 + 40),
        (9, 18 * 60 + 30, 19 * 60 + 15), (10, 19 * 60 + 25, 20 * 60 + 10),
        (11, 20 * 60 + 20, 21 * 60 + 5), (12, 21 * 60 + 15, 22 * 60),
    ]

    /// 分钟 → `08:00`（与 `TimeOfDay.displayText` 同一套 24 小时制写法）
    func clockText(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    func course(
        _ name: String,
        _ location: String?,
        weekday: Int,
        start: Int,
        end: Int
    ) -> WidgetWeekCourse {
        WidgetWeekCourse(
            entryId: UUID(),
            courseId: UUID(),
            courseName: name,
            color: .blue,
            location: location,
            weekday: weekday,
            startPeriod: start,
            endPeriod: end,
            periodText: "第 \(start)–\(end) 节",
            timeText: "08:00–09:40",
            lane: 0,
            laneCount: 1
        )
    }

    // 第 6 周实际生效的安排（周次区间包含第 6 周的才排进来）
    let courses = [
        course("操作系统原理", "西十二楼S409", weekday: 1, start: 3, end: 4),
        course("函数式编程原理", "西十二楼S301(课堂1)/西十二楼S311(课堂2)", weekday: 1, start: 5, end: 6),
        course("计算机通信与网络", "西五楼220", weekday: 2, start: 3, end: 4),
        course("计算机图形学", "西十二楼S401", weekday: 2, start: 5, end: 6),
        course("计算理论", "西十二楼S208", weekday: 2, start: 7, end: 8),
        course("函数式编程原理实验", "计算机大楼2006(课堂1)", weekday: 2, start: 9, end: 12),
        course("操作系统原理", "西十二楼S504", weekday: 3, start: 3, end: 4),
        course("大学体育", nil, weekday: 3, start: 5, end: 6),
        course("计算机通信与网络", "西五楼320", weekday: 4, start: 3, end: 4),
        course("计算机图形学", "西十二楼S401", weekday: 5, start: 1, end: 2),
        course("函数式编程原理", "西十二楼S301(课堂1)/西十二楼S403(课堂2)", weekday: 5, start: 3, end: 4),
        course("计算理论", "西十二楼S203", weekday: 5, start: 5, end: 6),
        course("软件工程", "计算机大楼2048", weekday: 5, start: 9, end: 12),
    ]

    let grid = WidgetWeekGrid(
        weekOffset: 0,
        rangeText: WidgetText.weekRangeText(days: days, calendar: calendar),
        subtitle: "第 6 周 · 2026～2027 学年度第一学期",
        days: days,
        // 真实学期排到第 12 节 —— 纵轴整份都在快照里，卡片每次只画其中连续 8 行。
        // 每一节都带上「上课 / 下课」两个时刻文本（左轴三行：课节号 / 上课 / 下课）。
        periods: periodSlots.map { number, start, end in
            WidgetPeriod(
                number: number,
                timeText: clockText(start),
                endTimeText: clockText(end),
                startMinute: start
            )
        },
        courses: courses
    )

    return (
        WidgetSnapshot(
            generatedAt: monday,
            semesterName: "2026～2027 学年度第一学期",
            today: days[1],
            weeks: [grid],
            todayStats: WidgetDayStats(periodCount: 4, minutes: 180)
        ),
        monday
    )
}

// MARK: - 主流程

@MainActor
func run() throws {
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

    // 只取一份 placeholder：它按 `Date()` 现算相对时刻，多取一份会让渲染与断言差几毫秒。
    let snapshot = WidgetSnapshot.placeholder
    let now = snapshot.generatedAt
    let filled = ClassFlowWidgetEntry(date: now, snapshot: snapshot)
    let empty = ClassFlowWidgetEntry(date: now, snapshot: .empty)

    let lightBackground = ("#FFFFFF 浅色卡底", (0xFF, 0xFF, 0xFF))
    let lightDivider = ("#E5E5E5 浅色分割线", (0xE5, 0xE5, 0xE5))

    // 组件 06 的「课毕」状态：今天确实没有剩余课程（明天还有一节数据结构）
    var doneSnapshot = snapshot
    doneSnapshot.todaySlots = []
    doneSnapshot.upcomingSlots = snapshot.upcomingSlots.filter { $0.courseName == "数据结构" }

    // ── 从模型问出「随当前时间变化」的那几句，避免把期望值抄死
    let active = snapshot.activeSlot(at: now)
    let countdown = active?.isTimeConfigured == true ? active?.countdownText(at: now) ?? "" : ""
    let locationPeriod = active?.locationPeriodText ?? ""
    let englishSlot = snapshot.todaySlots.first { $0.courseName == "英语" }
    let englishProgress = englishSlot?.progressText(at: now) ?? ""
    let todayHeader = WidgetText.monthDayWeekdayText(snapshot.today)
    let weekRange = snapshot.week(offset: 0)?.rangeText ?? ""
    let weekSubtitle = snapshot.week(offset: 0)?.subtitle ?? ""
    let statsLine = "今日 \(snapshot.todayStats.periodCount) 节课 · 上课 \(snapshot.todayStats.durationText)"
    let todo1 = snapshot.todos.first
    let todoAux = todo1?.auxiliaryText(now: now) ?? ""
    let memo = snapshot.latestMemo
    let memoAge = memo.map { WidgetText.relativeEditText(from: $0.updatedAt, now: now) } ?? ""

    var checks: [(CardCheck, AnyView)] = []

    func add(_ check: CardCheck, _ view: some View) {
        checks.append((check, AnyView(view)))
    }

    // ── 01 下一节课 · 小
    add(
        CardCheck(
            name: "01-next-class-small",
            size: smallSize,
            background: lightBackground,
            style: .light,
            fragments: ["下一节课", "高等数学", "10:10–11:50", locationPeriod, countdown],
            requiresDate: true,
            divider: lightDivider,
            above: [("下一节课", "高等数学"), ("高等数学", "10:10–11:50"), ("10:10–11:50", "教室 302")],
            leftOf: [("下一节课", countdown)]
        ),
        NextClassSmallEntryView(entry: filled)
    )

    add(
        CardCheck(
            name: "01-next-class-small-empty",
            size: smallSize,
            background: lightBackground,
            style: .light,
            fragments: ["下一节课", "今天没有更多课程", "打开 ClassFlow 查看后续安排"],
            requiresDate: true,
            divider: lightDivider
        ),
        NextClassSmallEntryView(entry: empty)
    )

    // ── 02 今日课程 · 中
    add(
        CardCheck(
            name: "02-today-schedule",
            size: mediumSize,
            background: lightBackground,
            style: .light,
            fragments: [
                todayHeader, "2 门课", "08:00", "英语", "教室 B201", englishProgress,
                "10:10", "高等数学", "教室 302",
            ],
            divider: lightDivider,
            above: [("08:00", "10:10"), ("英语", "高等数学")],
            leftOf: [("08:00", "英语"), ("10:10", "高等数学")]
        ),
        TodayScheduleEntryView(entry: filled)
    )

    // 同一天晚些时候：两行都应写 `已结束`。
    let evening = Calendar.current.date(
        bySettingHour: 23, minute: 50, second: 0, of: snapshot.today
    ) ?? now
    let eveningEntry = ClassFlowWidgetEntry(date: evening, snapshot: snapshot)

    add(
        CardCheck(
            name: "02-today-schedule-evening",
            size: mediumSize,
            background: lightBackground,
            style: .light,
            fragments: [todayHeader, "2 门课", "08:00", "英语", "10:10", "高等数学", "已结束"],
            divider: lightDivider,
            above: [("08:00", "10:10"), ("英语", "高等数学")]
        ),
        TodayScheduleEntryView(entry: eveningEntry)
    )

    add(
        CardCheck(
            name: "02-today-schedule-empty",
            size: mediumSize,
            background: lightBackground,
            style: .light,
            fragments: ["0 门课", "今天没有课程", "打开 ClassFlow 查看本周安排"],
            divider: lightDivider
        ),
        TodayScheduleEntryView(entry: empty)
    )

    // ── 03 本周课表 · 大
    // 网格里的课名会**折成两行**（`高等` / `数学`），所以按行片段断言，不拼整名。
    // 占位数据里英语在 B201、高数在 302，两行文字（课名 + 地点）都要能认出来。
    // 左轴是**三行**：课节号 / 上课 / 下课 —— 上下课两个时刻都要能认出来，且上课在上、下课在下。
    add(
        CardCheck(
            name: "03-week-timetable",
            size: largeSize,
            background: lightBackground,
            style: .light,
            fragments: [
                weekRange, weekSubtitle, statsLine, "高等", "数学", "英语", "B201", "302",
                "08:00", "08:45", "14:00", "14:45", "14:55", "15:40",
            ],
            // 课程块上**只写课程名与上课地点**：旧版那行节次文案不该再出现 ——
            // 块的位置本身已经表达了第几节、跨几节，左轴也已经写了每节的上下课时刻。
            absent: ["第 1–2 节", "第 3–4 节", "第 5–6 节"],
            divider: lightDivider,
            // 大课表的课程块按课程颜色着色：示例数据里「英语」是绿色、「高等数学」是蓝色，
            // 所以卡上必须同时出现蓝系与绿系像素（灰阶卡片里原本一个彩色像素都没有）。
            chromatic: [("蓝系课程块", .blueish, 0.01), ("绿系课程块", .greenish, 0.01)],
            above: [
                (weekRange, "英语"), ("英语", statsLine),
                ("08:00", "08:45"), ("14:00", "14:45"), ("14:55", "15:40"),
            ]
        ),
        WeekTimetableEntryView(entry: filled)
    )

    add(
        CardCheck(
            name: "03-week-timetable-empty",
            size: largeSize,
            background: lightBackground,
            style: .light,
            fragments: ["本周课表", "这一周还没有课程", "打开 ClassFlow 导入或添加课程安排"],
            // 空态卡上不该出现任何彩色块
            chromatic: [("空态不该有彩色块", .blueish, 0)]
        ),
        WeekTimetableEntryView(entry: empty)
    )

    // ── 03b 本周课表 · 真实课表 · 早上那一档（窗口 = 第 1–8 节）
    //
    // 盯的是用户报的那件事：「西十二楼S401」只显示成「西十二楼S…」。
    // 真实课表排到第 12 节，卡片只画连续 8 行 —— 早上还没到第 1 节，窗口就是 1–8，
    // 这段里的教室名要一个不少地画全。
    //
    // 判据分两层：
    // - `fragments` 管「教室号还在不在图上」——注意大课表是**七列网格**，OCR 的阅读顺序
    //   会被左轴的节次号打断（`计算机` / `1` / `图形学`），所以这里只断言**单行**片段；
    // - `untruncated` 管「有没有被省略号吃掉」——凡是含 `西十二楼` / `S401` 的行都不许以
    //   省略号收尾。截断时那一行正是用户看到的 `西十二楼S…`，第一层抓不到、这一层抓得到。
    // 两个教室 / 三个教室的长写法（`西十二楼S301(课堂1)/西十二楼S311(课堂2)`）本来就放不下，
    // 不在断言范围里（它们由 `ClassBlockLocationFittingTests` 的「判据本身有效」那条看着）。
    let (realSnapshot, realMonday) = realWeekSnapshot()
    // 时刻用 `Calendar.current` 算：窗口是按**本地钟点**挑的（`WidgetWeekWindow` 默认日历），
    // 这样无论跑在哪个时区，08:00 / 20:00 落在哪一档都和组件里的判断一致。
    let clock = Calendar.current
    func moment(_ hour: Int, _ minute: Int) -> Date {
        clock.date(bySettingHour: hour, minute: minute, second: 0, of: realMonday) ?? realMonday
    }

    add(
        CardCheck(
            name: "03b-week-timetable-real-rooms",
            size: largeSize,
            background: lightBackground,
            style: .light,
            fragments: [
                // 表头：`10 月 12–18 日` 会被 OCR 拆成两行（`10月` / `｜12-18 日`），
                // 所以只认日期区间这一截；周次那一行是整行。
                "12-18",
                "第 6 周",
                // 课名（用户举的那门课）
                "计算机",
                "图形学",
                // 第 1–8 节里的教室：楼与号分开认
                "西十二楼",
                "西五楼",
                "S401",
                "S409",
                "S504",
                "S208",
                "S203",
                "220",
                "320",
                // 左轴：第 1–8 节的上下课时刻（第 1 节 08:00 / 08:45、第 8 节 16:55 / 17:40）
                "08:00", "08:45", "08:55", "09:40", "16:55", "17:40",
            ],
            // 第 9–12 节的课（晚课）不在早上的窗口里，别把它们认进来；
            // 晚课的时刻（18:30 起）同样不该出现在这一档上。
            absent: ["计算机大楼", "2048", "18:30", "22:00"],
            untruncated: [
                "西十二楼", "西五楼",
                "S401", "S409", "S504", "S208", "S203", "220", "320",
            ],
            divider: lightDivider,
            chromatic: [("蓝系课程块", .blueish, 0.01)],
            // 三行左轴的顺序：课节号在上、上课时刻居中、下课时刻在下
            above: [("08:00", "08:45"), ("08:55", "09:40"), ("16:55", "17:40")]
        ),
        WeekTimetableEntryView(entry: ClassFlowWidgetEntry(date: moment(8, 0), snapshot: realSnapshot))
    )

    // ── 03c 本周课表 · 真实课表 · 晚上那一档（窗口滑到第 5–12 节）
    //
    // 八行窗口的核心承诺：晚课的学生在卡片上找得到自己的课。20:00 时第 10 节已经开讲，
    // 窗口按「当前节次落在第 4 行」滑到 5–12 —— 第 9–12 节的课（计算机大楼 2006 / 2048）
    // 必须出现在卡上，而只排在第 3–4 节的课（S409 / S504）必须滑出窗口。
    add(
        CardCheck(
            name: "03c-week-timetable-real-evening",
            size: largeSize,
            background: lightBackground,
            style: .light,
            // `实验` 那一路不写整名：一列 32pt 的文字宽度排不下「函数式编程原理实验」，
            // 课名两行就会被省略号收尾（地点优先，见 `WeekCard.courseCell`），
            // 所以这里只认短片段 + 晚上才有的「计算机大楼 / 2048 / 2006 / 软件工程」。
            // 左轴跟着窗口滑到第 5–12 节：14:00 起、22:00 收（08:00 / 08:45 必须已经滑出画面）。
            fragments: [
                "第 6 周", "计算机大楼", "2048", "2006", "软件", "工程", "函数式",
                "14:00", "14:45", "18:30", "19:15", "21:15", "22:00",
            ],
            absent: ["S409", "S504", "08:00", "08:45"],
            untruncated: ["计算机大楼", "2048", "S401", "S208"],
            divider: lightDivider,
            chromatic: [("蓝系课程块", .blueish, 0.01)],
            above: [("14:00", "14:45"), ("18:30", "19:15"), ("21:15", "22:00")]
        ),
        WeekTimetableEntryView(entry: ClassFlowWidgetEntry(date: moment(20, 0), snapshot: realSnapshot))
    )

    // ── 04 课程待办 · 中
    add(
        CardCheck(
            name: "04-todo",
            size: mediumSize,
            background: lightBackground,
            style: .light,
            fragments: ["即将到期", "2 项待办", "完成习题集", "阅读第四章", todoAux],
            divider: lightDivider,
            above: [("即将到期", "完成习题集"), ("完成习题集", "阅读第四章")]
        ),
        TodoEntryView(entry: filled)
    )

    add(
        CardCheck(
            name: "04-todo-empty",
            size: mediumSize,
            background: lightBackground,
            style: .light,
            // OCR 有时把数字 `0` 认成项目符号（`• 项待办`），所以这里只断言尾巴
            fragments: ["即将到期", "项待办", "暂无待办", "打开 ClassFlow 添加一条待办"],
            divider: lightDivider
        ),
        TodoEntryView(entry: empty)
    )

    // ── 05 快速笔记 · 小
    add(
        CardCheck(
            name: "05-quick-memo",
            size: smallSize,
            background: lightBackground,
            style: .light,
            fragments: ["课程笔记", memo?.courseName ?? "", memo?.title ?? "", memoAge, "+ 添加笔记"],
            above: [("课程笔记", memo?.title ?? ""), (memo?.title ?? "", "+ 添加笔记")]
        ),
        QuickMemoEntryView(entry: filled)
    )

    add(
        CardCheck(
            name: "05-quick-memo-empty",
            size: smallSize,
            background: lightBackground,
            style: .light,
            fragments: ["课程笔记", "还没有笔记", "把课堂要点记在这里", "+ 添加笔记"]
        ),
        QuickMemoEntryView(entry: empty)
    )

    // ── 06 今日课毕 · 小（今天确实没有剩余课程的「课毕」分支）
    add(
        CardCheck(
            name: "06-day-done",
            size: smallSize,
            background: lightBackground,
            style: .light,
            fragments: ["休息一下", "放松片刻", "今天没有更多课程。", "下节课 · 周二第 5–6 节"],
            above: [("休息一下", "今天没有更多课程。"), ("今天没有更多课程。", "下节课 · 周二第 5–6 节")]
        ),
        DayDoneEntryView(entry: ClassFlowWidgetEntry(date: now, snapshot: doneSnapshot))
    )

    // 同一张卡在「今天还有课」时必须改口，不谎报收工
    add(
        CardCheck(
            name: "06-day-done-still-busy",
            size: smallSize,
            background: lightBackground,
            style: .light,
            fragments: ["今天还有 1 节课", "下一节 10:10", "高等数学"]
        ),
        DayDoneEntryView(entry: filled)
    )

    // 07 下一节课 · 深色 · 中 —— 已按要求移除（连同深色卡底 / 深色分割线的核对一起删掉）
    //    对应视图 `NextClassDarkEntryView` 与 kind `ClassFlowNextClassDarkWidget` 也已删除。

    var failures: [String] = []

    for (check, content) in checks {
        let (url, _, lines, stats, chromatic) = try render(check, content: content)

        print("── \(check.name)  \(Int(check.size.width))×\(Int(check.size.height))pt  →  \(url.path)")
        for line in lines {
            print(String(format: "   y=%.3f x=%.3f  %@", line.y, line.x, line.text))
        }
        print("   底色 \(percent(stats.backgroundRatio))"
            + (check.divider.map { "   分割线 \(percent(stats.ratio(of: $0.0)))" } ?? "")
            + (check.accent.map { "   强调色 \(percent(stats.ratio(of: $0.0)))" } ?? "")
            + check.chromatic.map { "   \($0.0) \(percent(chromatic.ratio($0.0)))" }.joined())

        verify(check, lines: lines, stats: stats, chromatic: chromatic, failures: &failures)
        print("")
    }

    if failures.isEmpty {
        print("✅ 组件视觉自检通过：6 种组件的文案、版面顺序、底色与分割线都对得上设计稿")
        print("   一共渲染 \(checks.count) 张卡片，PNG 在 \(outputDirectory.path)/widget-*.png")
    } else {
        print("❌ 组件视觉自检失败（\(failures.count) 项）：")
        for failure in failures { print("   - \(failure)") }
        exit(1)
    }
}

@main
enum WidgetVisualCheck {

    static func main() {
        MainActor.assumeIsolated {
            do {
                try run()
            } catch {
                print("❌ 渲染失败：\(error)")
                exit(1)
            }
        }
    }
}
