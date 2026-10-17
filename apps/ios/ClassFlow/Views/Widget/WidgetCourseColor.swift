import SwiftUI

// MARK: - 课程颜色（主 App 与组件共用的唯一定义）

/// 课程颜色到实际色值的映射。
extension CourseColor {

    var color: Color {
        switch self {
        case .blue: .blue
        case .green: .green
        case .orange: .orange
        case .purple: .purple
        case .pink: .pink
        case .teal: .teal
        case .red: .red
        case .gray: .gray
        }
    }

    /// 课程块的淡色底：16% 不透明度叠在卡片底色上。
    var blockFill: Color { color.opacity(0.16) }

    /// 课程没设过颜色时的兜底：灰色。
    static let fallback: CourseColor = .gray
}
