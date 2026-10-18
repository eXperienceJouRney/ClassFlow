// 课程实时活动的离屏自检：把 Dynamic Island 的紧凑 / 最小化 / 展开与锁屏卡片
// 真渲染成 PNG，再用 Vision OCR + 像素采样核对版面。
//
// 断言项：各状态该出现的文案、长课名的折行与截断、地点缺失时不留分隔点、
// 倒计时在窄区域里仍然完整、进度条真的画出来了、已下课后不再停在 0:00。
//
// 运行（macOS，不需要模拟器，也不需要 ActivityKit 宿主）：
//
//   cd /Users/ray/classflow
//   xcrun swiftc -O -parse-as-library -o /tmp/classflow-live-activity-visual \
//     apps/ios/ClassFlow/Models/*.swift \
//     apps/ios/ClassFlow/Services/Inputs.swift \
//     apps/ios/ClassFlowWidget/CourseLiveActivityComponents.swift \
//     Scripts/live-activity-visual-check.swift
//   /tmp/classflow-live-activity-visual /Users/ray/classflow/.build
//
// 画布尺寸是系统容器（灵动岛 / 锁屏卡片）的近似值：这里只核对**内容排版**，
// 不核对系统给的圆角、安全区与动画。真机 / 模拟器上的最终形态仍以系统为准。
import AppKit
import Foundation
import SwiftUI
import Vision

/// 渲染倍数：3x 下 11pt 的小字 OCR 认不稳，4x 更稳。
let renderScale: CGFloat = 4

/// 灵动岛展开态的总宽度与左右两块上方区域的宽度（iPhone 17 级别，近似值）。
let expandedWidth: CGFloat = 371
let expandedWingWidth: CGFloat = 118
/// 紧凑态灵动岛的整宽 / 高。
let compactSize = CGSize(width: 220, height: 36)
/// 最小化形态的小胶囊。
let minimalSize = CGSize(width: 44, height: 36)
/// 锁屏卡片宽度（全面屏两侧各留一段边距后的内容宽度）。
let lockScreenWidth: CGFloat = 370

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

/// 所有用例共用同一个「现在」：倒计时与进度条才有确定的相对位置。
let now = Date()

// MARK: - 展示数据

/// 造一份展示数据：默认已经上 18 分钟、距下课 42 分钟。
func makePresentation(
    courseName: String = "数据结构与算法",
    location: String? = "教三-201",
    nextName: String? = "高等数学（A）",
    nextLocation: String? = "东九-306",
    startingAt startOffset: TimeInterval = -18 * 60,
    duration: TimeInterval = 60 * 60,
    isStale: Bool = false
) -> CourseActivityPresentation {
    CourseActivityPresentation(
        courseName: courseName,
        startTime: now.addingTimeInterval(startOffset),
        endTime: now.addingTimeInterval(startOffset + duration),
        location: location,
        nextCourse: nextName.map { name in
            CourseActivityPresentation.NextCourse(
                name: name,
                startTime: now.addingTimeInterval(startOffset + duration + 10 * 60),
                location: nextLocation
            )
        },
        isStale: isStale
    )
}

// MARK: - 文案归一化

/// OCR 结果与期望值的比对口径：去掉空白、统一破折号 / 间隔号 / 全角标点。
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
    /// 归一化坐标：0 = 顶部，1 = 底部
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

/// 底色占比 + 最长一段连续的非纯黑横向像素 + 这样的横条有多高。
///
/// 进度条是一条铺满卡片宽度的浅色细线（白 18% 的底槽 + 白色填充，高 4pt），
/// 分割线也是通栏的，但只有 1pt：用「连续长条的行数」就能把两者分开。
struct PixelStats {
    let backgroundRatio: Double
    let longestBarRun: Double
    /// 最长的一条通栏横条的高度（pt）
    let barBandHeight: Double
}

func pixelStats(of image: CGImage) -> PixelStats {
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
        return PixelStats(backgroundRatio: 0, longestBarRun: 0, barBandHeight: 0)
    }

    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    var black = 0

    for index in stride(from: 0, to: pixels.count, by: 4) {
        let a = Int(pixels[index + 3])
        guard a > 200 else { continue }
        let r = Int(pixels[index])
        let g = Int(pixels[index + 1])
        let b = Int(pixels[index + 2])
        if r < 12, g < 12, b < 12 { black += 1 }
    }

    var longestRun = 0
    var currentBand = 0
    var longestBand = 0

    for row in 0..<height {
        var run = 0
        var longestRunInRow = 0

        for column in 0..<width {
            let index = (row * width + column) * 4
            let a = Int(pixels[index + 3])
            let r = Int(pixels[index])
            let g = Int(pixels[index + 1])
            let b = Int(pixels[index + 2])
            // 白 18% 叠在黑底上约为 (46, 46, 46)，阈值取 28 留出抗锯齿余量。
            let isBar = a > 200 && r > 28 && g > 28 && b > 28 && abs(r - g) < 8 && abs(g - b) < 8
            if isBar {
                run += 1
                longestRunInRow = max(longestRunInRow, run)
            } else {
                run = 0
            }
        }

        longestRun = max(longestRun, longestRunInRow)

        if longestRunInRow > Int(Double(width) * 0.55) {
            currentBand += 1
            longestBand = max(longestBand, currentBand)
        } else {
            currentBand = 0
        }
    }

    return PixelStats(
        backgroundRatio: Double(black) / Double(width * height),
        longestBarRun: Double(longestRun) / Double(width),
        barBandHeight: Double(longestBand) / Double(renderScale)
    )
}

// MARK: - 渲染

@MainActor
func render(
    name: String,
    width: CGFloat,
    height: CGFloat?,
    content: some View
) throws -> (url: URL, lines: [RecognizedLine], stats: PixelStats, imageHeight: Double) {
    let sized = content
        .environment(\.courseActivityRendersStaticProgress, true)
        .frame(width: width, height: height, alignment: .top)

    let renderer = ImageRenderer(content: sized)
    renderer.scale = renderScale

    guard let cgImage = renderer.cgImage else {
        throw NSError(domain: "live-activity-visual-check", code: 1, userInfo: [NSLocalizedDescriptionKey: "渲染 \(name) 失败"])
    }

    guard let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
        throw NSError(domain: "live-activity-visual-check", code: 2, userInfo: [NSLocalizedDescriptionKey: "PNG 编码 \(name) 失败"])
    }

    let url = outputDirectory.appendingPathComponent("live-activity-\(name).png")
    try data.write(to: url)

    return (
        url,
        try recognizeText(in: cgImage),
        pixelStats(of: cgImage),
        Double(cgImage.height) / Double(renderScale)
    )
}

// MARK: - 容器

/// 紧凑态：课程名在左、倒计时在右的一整条灵动岛。
struct CompactIsland: View {
    let presentation: CourseActivityPresentation

    var body: some View {
        HStack(spacing: 0) {
            CourseActivityCompactLeadingView(presentation: presentation)
            Spacer(minLength: 12)
            CourseActivityCompactTrailingView(presentation: presentation)
        }
        .padding(.horizontal, 14)
        .frame(width: compactSize.width, height: compactSize.height)
        .background(Capsule().fill(CourseActivityPalette.background))
    }
}

/// 最小化形态：只有剩余时间的小胶囊。
struct MinimalIsland: View {
    let presentation: CourseActivityPresentation

    var body: some View {
        CourseActivityMinimalView(presentation: presentation)
            .padding(.horizontal, 4)
            .frame(width: minimalSize.width, height: minimalSize.height)
            .background(Capsule().fill(CourseActivityPalette.background))
    }
}

/// 展开态：上方左右两块区域 + 下方整行，近似系统给的版面。
///
/// 内边距 = 系统给的常见内边距（14 / 12）+ `CourseActivityMetrics` 里的额外留白，
/// 与 `CourseLiveActivity` 里给每个区域加的 `.padding` 对齐。
struct ExpandedIsland: View {
    let presentation: CourseActivityPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 0) {
                CourseActivityExpandedLeadingView(presentation: presentation)
                    .frame(width: expandedWingWidth, alignment: .leading)

                Spacer(minLength: 0)

                CourseActivityExpandedTrailingView(presentation: presentation)
                    .frame(width: expandedWingWidth, alignment: .trailing)
            }

            CourseActivityExpandedBottomView(presentation: presentation)
        }
        .padding(.horizontal, 14 + CourseActivityMetrics.expandedInsetHorizontal)
        .padding(.vertical, 12 + CourseActivityMetrics.expandedInsetVertical)
        .frame(width: expandedWidth)
        .background(RoundedRectangle(cornerRadius: 38, style: .continuous).fill(CourseActivityPalette.background))
    }
}

/// 锁屏卡片：内容自带内边距，这里只加宽度与黑底。
struct LockScreenCard: View {
    let presentation: CourseActivityPresentation

    var body: some View {
        CourseActivityLockScreenContent(presentation: presentation)
            .frame(width: lockScreenWidth)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(CourseActivityPalette.background))
    }
}

// MARK: - 检查项

struct StateCheck {
    let name: String
    let width: CGFloat
    /// `nil` 表示由内容决定高度（锁屏卡片就是这样）；
    /// 给了固定高度就相当于系统给的硬边界，用来抓「被高度挤到截断」。
    var height: CGFloat?
    let content: AnyView

    /// 必须出现的文案
    var fragments: [String] = []
    /// 不该再出现的文案（例如地点缺失时的分隔点）
    var absent: [String] = []
    /// 这些文案所在的行不许以省略号收尾
    var untruncated: [String] = []
    /// 前者必须在上方
    var above: [(String, String)] = []
    /// 前者必须在左侧
    var leftOf: [(String, String)] = []
    /// 倒计时必须在这段文案的右侧
    var countdownRightOf: String?
    /// 必须有一条铺满宽度、且超过 3pt 高的进度条（把 1pt 分割线排除掉）
    var requiresProgressBar: Bool = false
    /// 必须有一行「数字:数字」的倒计时（`Text(timerInterval:)` 真的画出来了）
    var requiresCountdown: Bool = false
    /// 渲染高度上限（pt）；灵动岛展开态不能高过系统给的高度
    var maxHeight: Double?
}

// MARK: - 断言

func verify(
    _ check: StateCheck,
    lines: [RecognizedLine],
    stats: PixelStats,
    imageHeight: Double,
    failures: inout [String]
) {
    let haystack = normalize(lines.map(\.text).joined(separator: " | "))
    /// 换行处不加分隔的版本：文案折成两行时也能认出整句
    let wrappedHaystack = normalize(lines.map(\.text).joined())

    /// 只做单向包含：反向包含会让 `日` 这类单字命中别的行。
    func locate(_ fragment: String) -> RecognizedLine? {
        let needle = normalize(fragment)
        guard !needle.isEmpty else { return nil }
        return lines.first { normalize($0.text).contains(needle) }
    }

    func locateCountdown() -> RecognizedLine? {
        lines.first { isCountdown($0.text) }
    }

    if stats.backgroundRatio < 0.5 {
        failures.append("\(check.name)：底色不是黑色（仅 \(percent(stats.backgroundRatio))）")
    }

    for fragment in check.fragments {
        let needle = normalize(fragment)
        guard !needle.isEmpty else { continue }
        if !haystack.contains(needle), !wrappedHaystack.contains(needle) {
            failures.append("\(check.name)：OCR 没认出「\(fragment)」")
        }
    }

    for fragment in check.absent {
        let needle = normalize(fragment)
        guard !needle.isEmpty else { continue }
        if lines.contains(where: { normalize($0.text).contains(needle) }) {
            failures.append("\(check.name)：不该出现「\(fragment)」")
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
            failures.append("\(check.name)：含「\(fragment)」的行被省略号截断 —— OCR 读到「\(hit.text)」")
        }
    }

    for (upper, lower) in check.above {
        guard let top = locate(upper), let bottom = locate(lower) else { continue }
        if !(top.y < bottom.y) {
            failures.append("\(check.name)：版面顺序不对，「\(upper)」(y=\(format(top.y))) 应在「\(lower)」(y=\(format(bottom.y))) 上方")
        }
    }

    for (left, right) in check.leftOf {
        guard let lhs = locate(left), let rhs = locate(right) else { continue }
        if !(lhs.x < rhs.x) {
            failures.append("\(check.name)：左右顺序不对，「\(left)」(x=\(format(lhs.x))) 应在「\(right)」(x=\(format(rhs.x))) 左侧")
        }
    }

    if let anchor = check.countdownRightOf {
        guard let countdown = locateCountdown(), let reference = locate(anchor) else {
            failures.append("\(check.name)：找不到倒计时或「\(anchor)」")
            return
        }
        if !(countdown.x > reference.x) {
            failures.append("\(check.name)：倒计时没有排在课程名右侧")
        }
    }

    if check.requiresProgressBar {
        if stats.barBandHeight < 3 {
            failures.append(
                "\(check.name)：没找到 4pt 左右的通栏进度条"
                + "（最长连续像素 \(percent(stats.longestBarRun))，横条高 \(String(format: "%.1f", stats.barBandHeight))pt）"
            )
        }
    }

    if check.requiresCountdown, locateCountdown() == nil {
        failures.append("\(check.name)：没找到倒计时文本（应为「数字:两位数字」）")
    }

    if let maxHeight = check.maxHeight, imageHeight > maxHeight + 0.5 {
        failures.append("\(check.name)：内容高 \(String(format: "%.1f", imageHeight))pt，超过灵动岛可用高度 \(Int(maxHeight))pt")
    }
}

/// 这一行是不是被省略号截断了。
func isTruncated(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    return trimmed.hasSuffix("…") || trimmed.hasSuffix("...") || trimmed.hasSuffix("..")
}

/// 倒计时行：`42:10` / `1:12:34` / `72:10`。
func isCountdown(_ text: String) -> Bool {
    let pattern = try? NSRegularExpression(pattern: #"\d{1,3}:\d{2}"#)
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return pattern?.firstMatch(in: text, range: range) != nil
}

func percent(_ value: Double) -> String {
    String(format: "%.1f%%", value * 100)
}

func format(_ value: Double) -> String {
    String(format: "%.3f", value)
}

// MARK: - 入口

@MainActor
func run() throws {
    let standard = makePresentation()
    let longName = "马克思主义基本原理概论（2026 秋季学期）"
    let longNoLocation = makePresentation(courseName: longName, location: "", nextLocation: "")
    let stale = makePresentation(isStale: true)

    /// 时段文案跟随运行环境（12/24 小时制都成立），断言不写死钟点。
    let startText = CourseActivityFormat.time(standard.startTime)
    let endText = CourseActivityFormat.time(standard.endTime)

    let checks: [StateCheck] = [
        // 锁屏：课程名 + 剩余时间为主，时段 / 地点次之，最后是进度与下一节。
        StateCheck(
            name: "lock",
            width: lockScreenWidth,
            content: AnyView(LockScreenCard(presentation: standard)),
            fragments: [
                "数据结构与算法", "剩余", startText, endText,
                "教三-201", "下一节", "高等数学（A）", "东九-306",
            ],
            untruncated: ["数据结构与算法", "教三-201", "东九-306"],
            above: [
                ("数据结构与算法", startText),
                (startText, "下一节"),
            ],
            leftOf: [("数据结构与算法", "剩余")],
            requiresProgressBar: true,
            requiresCountdown: true
        ),

        // 地点缺失：只剩时段，不留孤零零的分隔点。
        StateCheck(
            name: "lock-no-location",
            width: lockScreenWidth,
            content: AnyView(
                LockScreenCard(presentation: makePresentation(location: "", nextLocation: ""))
            ),
            fragments: ["数据结构与算法", "剩余", startText, "下一节"],
            absent: ["·"],
            requiresProgressBar: true,
            requiresCountdown: true
        ),

        // 当天没有后续课程：只留一行说明，不再挂「下一节」标签。
        StateCheck(
            name: "lock-no-next",
            width: lockScreenWidth,
            content: AnyView(LockScreenCard(presentation: makePresentation(nextName: nil))),
            fragments: ["数据结构与算法", "今天没有更多课程"],
            absent: ["下一节"],
            requiresProgressBar: true,
            requiresCountdown: true
        ),

        // 长课名：折成两行，剩余时间仍在右上角，进度条不被挤掉。
        StateCheck(
            name: "lock-long-name",
            width: lockScreenWidth,
            content: AnyView(LockScreenCard(presentation: makePresentation(courseName: longName))),
            fragments: ["马克思主义基本原理概论", "（2026 秋季学期）", "剩余", startText, "下一节"],
            untruncated: ["马克思主义基本原理概论", "（2026 秋季学期）"],
            above: [("剩余", startText)],
            requiresProgressBar: true,
            requiresCountdown: true
        ),

        // 已下课：不再显示「剩余」与进度条，也不停在 0:00。
        StateCheck(
            name: "lock-stale",
            width: lockScreenWidth,
            content: AnyView(LockScreenCard(presentation: stale)),
            fragments: ["数据结构与算法", "已结束", startText, "下一节"],
            absent: ["剩余", "0:00"],
            requiresProgressBar: false,
            requiresCountdown: false
        ),

        // 展开：课程名 / 起止时刻 / 地点在上，进度与下一节在下。
        StateCheck(
            name: "expanded",
            width: expandedWidth,
            content: AnyView(ExpandedIsland(presentation: standard)),
            fragments: [
                "数据结构与算法", startText, endText, "教三-201",
                "下一节", "高等数学（A）", "东九-306",
            ],
            untruncated: ["数据结构与算法", endText, "教三-201"],
            above: [
                ("数据结构与算法", "下一节"),
                ("教三-201", "下一节"),
            ],
            requiresProgressBar: true,
            maxHeight: 160
        ),

        // 展开 + 长课名 + 无地点：课名先缩放 / 截断，右侧时刻不能被挤没。
        StateCheck(
            name: "expanded-long-name",
            width: expandedWidth,
            content: AnyView(ExpandedIsland(presentation: longNoLocation)),
            fragments: [startText, endText, "下一节", "高等数学（A）"],
            absent: ["·"],
            untruncated: [endText],
            requiresProgressBar: true,
            maxHeight: 160
        ),

        // 展开 + 已下课：用一行静态文案替代进度条。
        StateCheck(
            name: "expanded-stale",
            width: expandedWidth,
            content: AnyView(ExpandedIsland(presentation: stale)),
            fragments: ["数据结构与算法", "本节课已结束", "下一节"],
            absent: ["0:00"],
            maxHeight: 160
        ),

        // 紧凑：课程名在左、倒计时在右。
        StateCheck(
            name: "compact",
            width: compactSize.width,
            height: compactSize.height,
            content: AnyView(CompactIsland(presentation: standard)),
            fragments: ["数据结构与算法"],
            untruncated: ["数据结构与算法"],
            countdownRightOf: "数据结构与算法",
            requiresCountdown: true
        ),

        // 紧凑 + 长课名：课名可以截断，倒计时必须完整。
        StateCheck(
            name: "compact-long-name",
            width: compactSize.width,
            height: compactSize.height,
            content: AnyView(CompactIsland(presentation: makePresentation(courseName: longName))),
            requiresCountdown: true
        ),

        // 紧凑 + 已下课：右侧不再倒数，换成「已结束」。
        StateCheck(
            name: "compact-stale",
            width: compactSize.width,
            height: compactSize.height,
            content: AnyView(CompactIsland(presentation: stale)),
            fragments: ["数据结构与算法", "已结束"],
            absent: ["0:00"]
        ),

        // 最小化：只放剩余时间。
        StateCheck(
            name: "minimal",
            width: minimalSize.width,
            height: minimalSize.height,
            content: AnyView(MinimalIsland(presentation: standard)),
            requiresCountdown: true
        ),

        // 最小化 + 已下课：显示「已结束」，不留在 0:00。
        StateCheck(
            name: "minimal-stale",
            width: minimalSize.width,
            height: minimalSize.height,
            content: AnyView(MinimalIsland(presentation: stale)),
            fragments: ["已结束"],
            absent: ["0:00"]
        ),
    ]

    var failures: [String] = []

    for check in checks {
        let (url, lines, stats, imageHeight) = try render(
            name: check.name,
            width: check.width,
            height: check.height,
            content: check.content
        )

        print("── \(check.name)  \(Int(check.width))×\(String(format: "%.1f", imageHeight))pt  →  \(url.path)")
        for line in lines {
            print(String(format: "   y=%.3f x=%.3f  %@", line.y, line.x, line.text))
        }
        print("   底色 \(percent(stats.backgroundRatio))   最长横条 \(percent(stats.longestBarRun))   横条高 \(String(format: "%.1f", stats.barBandHeight))pt")

        verify(check, lines: lines, stats: stats, imageHeight: imageHeight, failures: &failures)
        print("")
    }

    if failures.isEmpty {
        print("✅ 实时活动视觉自检通过：锁屏 / 展开 / 紧凑 / 最小化四种形态的文案、层级与留白都对得上")
        print("   一共渲染 \(checks.count) 张，PNG 在 \(outputDirectory.path)/live-activity-*.png")
    } else {
        print("❌ 实时活动视觉自检失败（\(failures.count) 项）：")
        for failure in failures { print("   - \(failure)") }
        exit(1)
    }
}

@main
enum LiveActivityVisualCheck {

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
