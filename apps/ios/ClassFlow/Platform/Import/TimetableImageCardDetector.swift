import Foundation
import CoreGraphics

/// 仅在日期行、星期列和连续课节均已确认后，利用卡片与列间背景的色差定位边界。
/// 不以文字首尾位置推断卡片占用课节，因此支持居中排版和跨多节的课程。
struct TimetableImageCardDetector: Sendable {
    func detect(in image: CGImage, layout: TimetableImageCalendarLayout) -> [TimetableImageCard] {
        let scale = min(1, 2048 / CGFloat(max(image.width, image.height)))
        let width = max(1, Int(CGFloat(image.width) * scale))
        let height = max(1, Int(CGFloat(image.height) * scale))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return [] }
        func color(_ x: CGFloat, _ y: Int) -> [Double] {
            let offset = (y * width + min(width - 1, max(0, Int(x * CGFloat(width))))) * 4
            return (0..<3).map { Double(pixels[offset + $0]) / 255 }
        }
        let top = max(0, Int(layout.top * CGFloat(height)))
        let bottom = min(height - 1, Int(layout.bottom * CGFloat(height)))
        guard top < bottom else { return [] }
        let gutterOffset: CGFloat = layout.columnWidth * 0.49
        let gutters: [CGFloat] = layout.columns.flatMap { column -> [CGFloat] in
            [column.x - gutterOffset, column.x + gutterOffset]
        }
            .filter { $0 > 0 && $0 < 1 }
        let backgrounds = (top...bottom).map { y -> [Double] in
            let samples = gutters.map { color($0, y) }
            return (0..<3).map { channel in samples.map { $0[channel] }.sorted()[samples.count / 2] }
        }
        var cards: [TimetableImageCard] = []
        for column in layout.columns {
            var rows = (top...bottom).map { y -> Bool in
                let background = backgrounds[y - top]
                let colored = (0..<24).filter { sample in
                    // 取卡片内侧的两条窄带，避开中央白色文字和「非本周」徽标。
                    let side: CGFloat = sample % 2 == 0 ? -1 : 1
                    let inset = 0.32 + CGFloat(sample / 2) / 11 * 0.06
                    let x = column.x + side * inset * layout.columnWidth
                    let rgb = color(x, y)
                    let maximum = rgb.max()!, minimum = rgb.min()!
                    let distance = zip(rgb, background).reduce(0) { $0 + pow($1.0 - $1.1, 2) }
                    return maximum - minimum > 0.09 && (maximum - minimum) / max(maximum, 0.01) > 0.14 && distance > 0.0144
                }.count
                return colored >= 9
            }
            // 只桥接一两个像素的抗锯齿孔洞，不跨过相邻两门课之间的间隔。
            if rows.count > 4 {
                for i in 1..<(rows.count - 2) where !rows[i] && rows[i - 1] && (rows[i + 1] || rows[i + 2]) {
                    rows[i] = true
                }
            }
            var start: Int?
            for i in 0...rows.count {
                if i < rows.count && rows[i] { if start == nil { start = i }; continue }
                guard let first = start else { continue }
                start = nil
                let minY = CGFloat(top + first) / CGFloat(height), maxY = CGFloat(top + i) / CGFloat(height)
                guard maxY - minY >= layout.rowHeight * 0.6 else { continue }
                let periods = layout.periods.filter { $0.y >= minY && $0.y < maxY }
                guard let firstPeriod = periods.first, let lastPeriod = periods.last else { continue }
                // 卡片若被裁掉或边界不对应课节，只保留课程文本，要求用户补时间。
                let aligned = abs(minY - (firstPeriod.y - layout.rowHeight * 0.27)) < layout.rowHeight * 0.3
                    && abs(maxY - (lastPeriod.y + layout.rowHeight * 0.73)) < layout.rowHeight * 0.3
                    && minY > layout.top + 1 / CGFloat(height)
                    && maxY < layout.bottom - 1 / CGFloat(height)
                cards.append(TimetableImageCard(
                    bounds: CGRect(x: column.x - layout.columnWidth * 0.46, y: minY,
                        width: layout.columnWidth * 0.92, height: maxY - minY),
                    weekday: column.weekday, startPeriod: aligned ? firstPeriod.number : nil,
                    endPeriod: aligned ? lastPeriod.number : nil))
            }
        }
        return cards
    }
}
