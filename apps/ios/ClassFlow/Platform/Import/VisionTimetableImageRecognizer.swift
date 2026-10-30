import Foundation
import CoreGraphics
import ImageIO
import Vision

/// OCR 在独立 actor 上执行，不阻塞界面，也不发送网络请求。
actor VisionTimetableImageRecognizer: TimetableClassImageRecognizer {
    nonisolated static let maximumImageBytes = 20 * 1024 * 1024

    private struct Analysis {
        let image: CGImage
        let blocks: [TimetableOCRBlock]
        let classLayout: TimetableImageClassTableLayout?
    }
    private var cachedData: Data?
    private var cachedAnalysis: Analysis?

    /// 只发现班级，不创建草稿；用户选班后复用本次本地 OCR 结果。
    func classOptions(imageData: Data) async throws -> [TimetableImageClassOption] {
        try await analysis(imageData).classLayout?.classes ?? []
    }

    func recognize(imageData: Data, fileName: String) async throws -> [ImportDraftEntry] {
        try await recognize(imageData: imageData, fileName: fileName, selectedClassID: nil)
    }

    func recognize(imageData: Data, fileName: String, selectedClassID: String?) async throws -> [ImportDraftEntry] {
        let prepared = try await analysis(imageData)
        let draftId = UUID()
        let entries: [ImportDraftEntry]
        if let layout = prepared.classLayout {
            guard let selectedClassID, layout.classes.contains(where: { $0.id == selectedClassID }) else {
                throw AppError.importParseFailed(reason: "检测到多班级课表，请先选择要导入的班级")
            }
            entries = await TimetableImageClassTableParser().parse(prepared.blocks, layout: layout,
                selectedClassID: selectedClassID, draftId: draftId)
        } else {
            let calendarParser = TimetableImageCalendarParser()
            if let layout = await calendarParser.layout(in: prepared.blocks) {
                let cards = await TimetableImageCardDetector().detect(in: prepared.image, layout: layout)
                entries = await calendarParser.parse(cards, blocks: prepared.blocks, layout: layout, draftId: draftId)
            } else {
                entries = await TimetableImageLayoutParser().parse(prepared.blocks, draftId: draftId)
            }
        }
        try Task.checkCancellation()
        guard !entries.isEmpty else {
            throw AppError.importParseFailed(reason: "识别到了文字，但未找到课程。请保留完整星期、班级、课节与课程内容，或改用粘贴文本、手动录入")
        }
        return entries
    }


    private func analysis(_ imageData: Data) async throws -> Analysis {
        try Task.checkCancellation()
        if cachedData == imageData, let cachedAnalysis { return cachedAnalysis }
        guard imageData.count <= Self.maximumImageBytes else {
            throw AppError.importParseFailed(reason: "图片超过 20 MB，请裁剪或压缩后重试")
        }
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 4096,
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else {
            throw AppError.importParseFailed(reason: "无法读取图片，请选择清晰的 PNG、JPEG 或 HEIC 课表截图")
        }

        var blocks = try recognizeText(in: image)
        guard !blocks.isEmpty else {
            throw AppError.importParseFailed(reason: "没有识别到文字，请使用文字清晰、方向端正的完整课表截图")
        }
        let classLayout = await TimetableImageClassTableParser().layout(in: blocks, image: image)
        if let classLayout {
            blocks = try refineClassTableBlocks(blocks, layout: classLayout, image: image)
        } else {
            blocks = try refineAmbiguousRoomBlocks(blocks, image: image)
        }
        try Task.checkCancellation()
        let result = Analysis(image: image, blocks: blocks, classLayout: classLayout)
        cachedData = imageData
        cachedAnalysis = result
        return result
    }

    private func recognizeText(in image: CGImage, customWords: [String] = []) throws -> [TimetableOCRBlock] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.003
        request.customWords = customWords
        // 禁止依赖联网服务；Vision 在设备上完成文字识别。
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw AppError.importParseFailed(reason: "本地文字识别未完成，请换一张更清晰的截图重试")
        }
        try Task.checkCancellation()

        let headerPatterns = try [
            #"(?:星期|周|礼拜)[一二三四五六日天1-7]"#,
            #"第?\s*[0-9]{1,2}\s*[-–—~～至到]\s*[0-9]{1,2}\s*节"#,
        ].map { try NSRegularExpression(pattern: $0) }
        return (request.results ?? []).flatMap { observation -> [TimetableOCRBlock] in
            guard let candidate = observation.topCandidates(1).first else { return [] }
            func block(_ text: String, bounds: CGRect) -> TimetableOCRBlock {
                TimetableOCRBlock(
                    text: text,
                    bounds: CGRect(x: bounds.minX, y: 1 - bounds.maxY, width: bounds.width, height: bounds.height),
                    confidence: candidate.confidence
                )
            }
            for pattern in headerPatterns {
                let range = NSRange(candidate.string.startIndex..., in: candidate.string)
                let matches = pattern.matches(in: candidate.string, range: range)
                let remainder = pattern.stringByReplacingMatches(in: candidate.string, range: range, withTemplate: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                guard matches.count >= 2, remainder.isEmpty else { continue }
                // Vision 有时把整行星期或课节合成一个文本块；仅拆纯表头，保留其他内容。
                let headers = matches.compactMap { match -> TimetableOCRBlock? in
                    guard let range = Range(match.range, in: candidate.string),
                          let bounds = try? candidate.boundingBox(for: range)?.boundingBox else { return nil }
                    return block(String(candidate.string[range]), bounds: bounds)
                }
                if headers.count == matches.count { return headers }
            }
            return [block(candidate.string, bounds: observation.boundingBox)]
        }
    }

    /// 显式教室字段中的 $ 常是小字号字母被误读；放大原位置重读，不直接替换或猜房号。
    private func refineAmbiguousRoomBlocks(_ blocks: [TimetableOCRBlock], image: CGImage) throws -> [TimetableOCRBlock] {
        var result = blocks
        let label = #"^(?:上课地点|上课教室|地点|教室)\s*[:：]"#
        for (index, block) in blocks.enumerated() where block.text.contains("$")
            && block.text.range(of: label, options: .regularExpression) != nil {
            try Task.checkCancellation()
            let pixels = CGRect(x: block.bounds.minX * CGFloat(image.width), y: block.bounds.minY * CGFloat(image.height),
                width: block.bounds.width * CGFloat(image.width), height: block.bounds.height * CGFloat(image.height))
                .insetBy(dx: -4, dy: -4).integral
                .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            guard let crop = image.cropping(to: pixels) else { continue }
            let scale = min(3, 4096 / CGFloat(max(crop.width, crop.height)))
            let width = max(1, Int(CGFloat(crop.width) * scale))
            let height = max(1, Int(CGFloat(crop.height) * scale))
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            context.interpolationQuality = .high
            context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let enlarged = context.makeImage(), let reread = try? recognizeText(in: enlarged) else { continue }
            let text = reread.sorted { $0.bounds.minX < $1.bounds.minX }.map(\.text).joined(separator: " ")
            guard !text.contains("$"), text.range(of: label, options: .regularExpression) != nil else { continue }
            result[index] = TimetableOCRBlock(text: text, bounds: block.bounds,
                confidence: reread.map(\.confidence).min() ?? block.confidence)
        }
        return result
    }

    /// 总课表的小字在整图识别中容易丢笔画；按实际边框裁出单元格放大重读。
    /// 合并单元格只读一次，选班时复用缓存，不根据班号猜测 OCR 错字。
    private func refineClassTableBlocks(_ blocks: [TimetableOCRBlock],
                                       layout: TimetableImageClassTableLayout,
                                       image: CGImage) throws -> [TimetableOCRBlock] {
        var cells: [CGRect] = []
        for cell in layout.classes.flatMap({ layout.cellsByClass[$0.id] ?? [] }) {
            if !cells.contains(cell.bounds) { cells.append(cell.bounds) }
        }
        var result = blocks
        // 整图中已经读清的教室名称可作为词表，减少局部重读时丢字或 S/$ 混淆。
        let roomPattern = try NSRegularExpression(pattern: #"[\p{Han}]+[A-Za-z]?[0-9]{3,5}"#)
        func roomWords(in blocks: [TimetableOCRBlock]) -> [String] {
            Array(Set(blocks.flatMap { block in
                roomPattern.matches(in: block.text, range: NSRange(block.text.startIndex..., in: block.text)).compactMap { match in
                Range(match.range, in: block.text).map { String(block.text[$0]) }
                }
            }))
        }
        let customWords = roomWords(in: blocks)
        for bounds in cells {
            try Task.checkCancellation()
            let contains: (TimetableOCRBlock) -> Bool = {
                bounds.contains(CGPoint(x: $0.bounds.midX, y: $0.bounds.midY))
            }
            guard blocks.contains(where: contains) else { continue }
            let originalRooms = roomWords(in: blocks.filter(contains))
            let pixels = CGRect(x: bounds.minX * CGFloat(image.width), y: bounds.minY * CGFloat(image.height),
                width: bounds.width * CGFloat(image.width), height: bounds.height * CGFloat(image.height))
                .insetBy(dx: 2, dy: 2).integral
                .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            guard pixels.width > 0, pixels.height > 0, let crop = image.cropping(to: pixels) else { continue }
            let scale = min(3, 4096 / CGFloat(max(crop.width, crop.height)))
            let width = max(1, Int(CGFloat(crop.width) * scale))
            let height = max(1, Int(CGFloat(crop.height) * scale))
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            context.interpolationQuality = .high
            context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let enlarged = context.makeImage(),
                  let recognized = try? recognizeText(in: enlarged, customWords: customWords), !recognized.isEmpty else { continue }
            result.removeAll(where: contains)
            result.append(contentsOf: recognized.map { block in
                TimetableOCRBlock(text: TimetableImageClassTableParser.restoringRoomPrefixes(in: block.text, from: originalRooms),
                    bounds: CGRect(x: (pixels.minX + block.bounds.minX * pixels.width) / CGFloat(image.width),
                        y: (pixels.minY + block.bounds.minY * pixels.height) / CGFloat(image.height),
                        width: block.bounds.width * pixels.width / CGFloat(image.width),
                        height: block.bounds.height * pixels.height / CGFloat(image.height)),
                    confidence: block.confidence)
            })
        }
        return result
    }
}

/// 班级选择是本次识别的显式输入，不改变共享识别器的状态。
struct ClassSelectedTimetableImageRecognizer: TimetableImageRecognizer {
    let recognizer: VisionTimetableImageRecognizer
    let selectedClassID: String?

    func recognize(imageData: Data, fileName: String) async throws -> [ImportDraftEntry] {
        try await recognizer.recognize(imageData: imageData, fileName: fileName, selectedClassID: selectedClassID)
    }
}
