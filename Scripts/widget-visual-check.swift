// 小组件视觉自检：把 `NextClassWidgetEntryView` 真渲染成 PNG，再用 Vision OCR + 像素采样核对版面。
//
// 为什么要它：当前会话的模型**没有图片输入能力**，没法「看」Xcode 预览截图。所以把「看不看得对」
// 拆成两件机器可判的事：
//   1. OCR 出卡片上的文字行 + 它们的 y 坐标 → 版面顺序是否等于设计稿
//      （`29 分钟后` / `下一节课` / `高等数学` / `10:10-11:50・第3-4节` / `教室302` / `ClassFlow`）
//   2. 采样像素 → 卡片底色是不是 `#171717`、倒计时是不是 `#B41818`
// 同时把 PNG 落到 `.build/`，交给有眼睛的人复核。
//
// 运行（macOS，不需要 iOS 模拟器、不需要 WidgetKit 宿主）：
//
//   cd /Users/ray/classflow/ClassFlow
//   xcrun swiftc -O -o /tmp/classflow-widget-visual \
//     ClassFlow/Models/WidgetSnapshot.swift \
//     ClassFlow/Views/Widget/NextClassWidgetView.swift \
//     /Users/ray/classflow/Scripts/widget-visual-check.swift
//   /tmp/classflow-widget-visual /Users/ray/classflow/.build
//
// 说明：`widgetFamily` 在非 widget 宿主里是只读的，脚本会把窗口尺寸设成
// systemMedium 338×158 / systemSmall 158×158 —— 版面顺序与配色是真值，字号取的是默认分支。

import AppKit
import Foundation
import SwiftUI
import Vision

// MARK: - 尺寸（与系统小组件一致）

let mediumSize = CGSize(width: 338, height: 158)
let smallSize = CGSize(width: 158, height: 158)
/// widget 内容距卡片边缘的系统内边距
let widgetPadding: CGFloat = 16

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

// MARK: - 渲染

@MainActor
func renderCard(
    entry: NextClassEntry,
    size: CGSize,
    scale: CGFloat,
    name: String
) throws -> (url: URL, cgImage: CGImage) {
    let content = NextClassWidgetEntryView(entry: entry)
        .padding(widgetPadding)
        .frame(width: size.width, height: size.height)
        .background(WidgetTheme.background)

    let renderer = ImageRenderer(content: content)
    renderer.scale = scale

    guard let cgImage = renderer.cgImage else {
        throw NSError(domain: "widget-visual-check", code: 1, userInfo: [NSLocalizedDescriptionKey: "渲染 \(name) 失败"])
    }

    let representation = NSBitmapImageRep(cgImage: cgImage)
    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "widget-visual-check", code: 2, userInfo: [NSLocalizedDescriptionKey: "PNG 编码 \(name) 失败"])
    }

    let url = outputDirectory.appendingPathComponent("widget-\(name).png")
    try data.write(to: url)
    return (url, cgImage)
}

// MARK: - OCR

/// 认出图上的文字行，按从上到下排序；返回 `(文本, 归一化 y)`。
func recognizeText(in image: CGImage) throws -> [(text: String, y: Double)] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["zh-Hans", "en-US"]
    request.usesLanguageCorrection = false

    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try handler.perform([request])

    let observations = (request.results ?? []).compactMap { observation -> (String, Double)? in
        guard let candidate = observation.topCandidates(1).first else { return nil }
        // Vision 的原点在左下角，转到「从上到下」的直觉坐标
        return (candidate.string, 1 - observation.boundingBox.midY)
    }

    return observations.sorted { $0.1 < $1.1 }
}

// MARK: - 像素采样

struct PixelStats {
    let backgroundRatio: Double
    let accentRatio: Double
    let whiteRatio: Double
}

func pixelStats(of image: CGImage, background: (Int, Int, Int), accent: (Int, Int, Int), tolerance: Int = 12) -> PixelStats {
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
        return PixelStats(backgroundRatio: 0, accentRatio: 0, whiteRatio: 0)
    }

    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    func isClose(_ r: Int, _ g: Int, _ b: Int, _ target: (Int, Int, Int)) -> Bool {
        abs(r - target.0) <= tolerance && abs(g - target.1) <= tolerance && abs(b - target.2) <= tolerance
    }

    var backgroundCount = 0
    var accentCount = 0
    var whiteCount = 0

    for index in stride(from: 0, to: pixels.count, by: 4) {
        let r = Int(pixels[index])
        let g = Int(pixels[index + 1])
        let b = Int(pixels[index + 2])
        let a = pixels[index + 3]
        guard a > 200 else { continue }

        if isClose(r, g, b, background) { backgroundCount += 1 }
        if isClose(r, g, b, accent) { accentCount += 1 }
        if r > 240, g > 240, b > 240 { whiteCount += 1 }
    }

    let total = Double(width * height)
    return PixelStats(
        backgroundRatio: Double(backgroundCount) / total,
        accentRatio: Double(accentCount) / total,
        whiteRatio: Double(whiteCount) / total
    )
}

// MARK: - 主流程

@MainActor
func run() throws {
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

    let now = Date()
    let cases: [(name: String, entry: NextClassEntry, size: CGSize)] = [
        ("medium", NextClassEntry(date: now, snapshot: .placeholder), mediumSize),
        ("small", NextClassEntry(date: now, snapshot: .placeholder), smallSize),
        ("medium-empty", NextClassEntry(date: now, snapshot: .empty), mediumSize),
    ]

    let background = (0x17, 0x17, 0x17)
    let accent = (0xB4, 0x18, 0x18)
    var failures: [String] = []

    for item in cases {
        let (url, image) = try renderCard(entry: item.entry, size: item.size, scale: 3, name: item.name)
        let lines = try recognizeText(in: image)
        let stats = pixelStats(of: image, background: background, accent: accent)

        print("── \(item.name)  \(Int(item.size.width))×\(Int(item.size.height))pt  →  \(url.path)")
        for line in lines {
            print(String(format: "   y=%.3f  %@", line.y, line.text))
        }
        print(String(
            format: "   底色 #171717 %.1f%%   强调色 #B41818 %.2f%%   白字 %.1f%%",
            stats.backgroundRatio * 100, stats.accentRatio * 100, stats.whiteRatio * 100
        ))

        if stats.backgroundRatio < 0.5 {
            failures.append("\(item.name)：底色不是 #171717（仅 \(String(format: "%.1f", stats.backgroundRatio * 100))%）")
        }

        // OCR 会在中英文之间插空格（`教室 302`），比对时统一去掉空白
        let joined = lines.map(\.text).joined(separator: " | ")
        let compact = joined.filter { !$0.isWhitespace }

        if item.entry.snapshot.activeSlot(at: now) != nil {
            if stats.accentRatio < 0.0001 {
                failures.append("\(item.name)：有课时却找不到强调色 #B41818")
            }

            let expected = ["29 分钟后", "下一节课", "高等数学", "10:10-11:50・第3-4节", "教室302", "ClassFlow"]
            for fragment in expected where !compact.contains(fragment.filter { !$0.isWhitespace }) {
                failures.append("\(item.name)：OCR 没认出「\(fragment)」（实际：\(joined)）")
            }
            // 版面顺序：课名在倒计时下面、`ClassFlow` 在最下面
            if let statusY = lines.first(where: { $0.text.contains("29 分钟后") })?.y,
               let courseY = lines.first(where: { $0.text.contains("高等数学") })?.y,
               let footerY = lines.first(where: { $0.text.contains("ClassFlow") })?.y,
               !(statusY < courseY && courseY < footerY) {
                failures.append("\(item.name)：版面顺序不对（倒计时 y=\(statusY)，课名 y=\(courseY)，页脚 y=\(footerY)）")
            }
        } else {
            // 空态本来就没有倒计时，因此没有强调色是对的
            for fragment in ["下一节课", "暂无课程", "打开 ClassFlow 添加课程", "ClassFlow"]
            where !compact.contains(fragment.filter { !$0.isWhitespace }) {
                failures.append("\(item.name)：OCR 没认出「\(fragment)」（实际：\(joined)）")
            }
        }
        print("")
    }

    if failures.isEmpty {
        print("✅ 小组件视觉自检通过：文案、版面顺序与配色都对得上设计稿")
    } else {
        print("❌ 小组件视觉自检失败：")
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
