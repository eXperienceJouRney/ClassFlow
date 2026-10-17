import SwiftUI

struct ClassCardView: View {

    let occurrence: ClassOccurrence
    var showsWeekday: Bool = false
    var timeFormat: TimeFormatPreference = .twentyFourHour

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill((occurrence.course.color ?? .gray).color)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(occurrence.course.name)
                        .font(DesignTokens.Typography.sectionTitle)

                    if showsWeekday {
                        Text(occurrence.weekday.shortName)
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(detailText)
                    .font(DesignTokens.Typography.secondary)
                    .foregroundStyle(.secondary)

                if let teacher = occurrence.course.teacher {
                    Text(teacher)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.tertiary)
                }

                if occurrence.hasUnresolvedPeriodTime {
                    Label("课节时间未配置", systemImage: "exclamationmark.triangle")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(DesignTokens.Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

extension ClassCardView {

    /// 「时间・地点」文本；课节号在课表左轴上另表。
    private var detailText: String {
        occurrence.detailText(timeFormat: timeFormat, showsPeriod: true)
    }
}

#Preview("课程卡片") {
    let seed = PreviewSupport.seed

    List {
        ClassCardView(occurrence: seed.firstClass)
        ClassCardView(occurrence: seed.firstClass, showsWeekday: true)
    }
}
