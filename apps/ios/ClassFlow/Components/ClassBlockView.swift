import SwiftUI

/// 课程块三行文字的行数上限（课程名 / 上课地点 / 授课教师）。
struct ClassBlockTextLayout: Equatable {

    /// 课程名最多几行
    var titleLineLimit: Int
    /// 上课地点最多几行
    var locationLineLimit: Int
    /// 授课教师最多几行；0 = 不显示教师
    var teacherLineLimit: Int

    var showsTeacher: Bool { teacherLineLimit > 0 }

    /// 按紧凑（周视图多列网格）/ 宽松与是否显示教师推导行数上限；显示教师时教师固定一行。
    static func resolve(isCompact: Bool, showsTeacher: Bool) -> ClassBlockTextLayout {
        guard showsTeacher else {
            return ClassBlockTextLayout(
                titleLineLimit: isCompact ? 4 : 5,
                locationLineLimit: isCompact ? 4 : 5,
                teacherLineLimit: 0
            )
        }

        return ClassBlockTextLayout(
            titleLineLimit: isCompact ? 3 : 4,
            locationLineLimit: isCompact ? 3 : 4,
            teacherLineLimit: 1
        )
    }
}

/// 课表网格里的课程块：课程名 / 上课地点 / 授课教师三行，浅色底 + 左侧课程色条。
struct ClassBlockView: View {

    let occurrence: ClassOccurrence
    /// 周视图列窄，行数多时压缩字号
    var isCompact: Bool = false
    /// 是否显示授课教师（设置里的「周视图显示教师」；日视图一列很宽，始终显示）
    var showsTeacher: Bool = true
    /// 三行文字各占几行；默认按 `isCompact` / `showsTeacher` 推导
    private var textLayout: ClassBlockTextLayout

    init(occurrence: ClassOccurrence, isCompact: Bool = false, showsTeacher: Bool = true) {
        self.occurrence = occurrence
        self.isCompact = isCompact
        self.showsTeacher = showsTeacher
        self.textLayout = .resolve(isCompact: isCompact, showsTeacher: showsTeacher)
    }

    /// 直接指定排版策略（预览与排版测试用）。
    init(occurrence: ClassOccurrence, isCompact: Bool = false, textLayout: ClassBlockTextLayout) {
        self.occurrence = occurrence
        self.isCompact = isCompact
        self.showsTeacher = textLayout.showsTeacher
        self.textLayout = textLayout
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(color)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 1) {
                Text(occurrence.course.name)
                    .font(isCompact ? DesignTokens.Typography.gridBlockTitle : .footnote.weight(.semibold))
                    .lineLimit(textLayout.titleLineLimit)
                    .foregroundStyle(.primary)

                if let location {
                    Text(location)
                        .font(isCompact ? DesignTokens.Typography.gridBlockLocation : .caption2)
                        .lineLimit(textLayout.locationLineLimit)
                        .foregroundStyle(.secondary)
                        .layoutPriority(0)
                }

                if textLayout.showsTeacher, let teacher {
                    Text(teacher)
                        .font(isCompact ? DesignTokens.Typography.gridBlockLocation : .caption2)
                        .lineLimit(textLayout.teacherLineLimit)
                        .foregroundStyle(.tertiary)
                        .layoutPriority(-1)
                }

                if occurrence.hasUnresolvedPeriodTime {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(palette.blockFill, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.block))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.block))
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.block))
    }
}

extension ClassBlockView {

    /// 课程颜色：未设置时回退到灰色。
    private var palette: CourseColor {
        occurrence.course.color ?? .fallback
    }

    private var color: Color {
        palette.color
    }

    /// 上课地点；空白视为未填写，返回 nil。
    private var location: String? {
        guard let location = occurrence.location, !location.isBlank else { return nil }
        return location
    }

    private var teacher: String? {
        guard let teacher = occurrence.course.teacher, !teacher.isBlank else { return nil }
        return teacher
    }
}

#Preview("课程块") {
    let seed = PreviewSupport.seed

    return HStack(spacing: 8) {
        ClassBlockView(occurrence: seed.firstClass)
            .frame(width: 160, height: 70)
        ClassBlockView(occurrence: seed.firstClass, isCompact: true)
            .frame(width: 96, height: 88)
    }
    .padding()
}

#Preview("课程块 · 周视图列宽") {
    let seed = PreviewSupport.seed

    return HStack(spacing: 4) {
        ClassBlockView(occurrence: seed.firstClass, isCompact: true, showsTeacher: true)
        ClassBlockView(occurrence: seed.firstClass, isCompact: true, showsTeacher: false)
    }
    .frame(height: 86)
    .padding()
}
