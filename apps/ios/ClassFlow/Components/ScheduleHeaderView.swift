import SwiftUI

/// 一周日期条：按顺序展示 7 个日期，选中项高亮。
struct WeekStripView: View {

    let dates: [CalendarDate]
    let selectedDate: CalendarDate
    var onSelect: (CalendarDate) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(dates, id: \.self) { date in
                dayItem(date)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.page)
    }
}

extension WeekStripView {

    private func dayItem(_ date: CalendarDate) -> some View {
        let isSelected = date == selectedDate
        let isToday = date == CalendarDate.today()
        let weekday = date.weekday()?.shortName.replacingOccurrences(of: "周", with: "") ?? ""

        return Button {
            onSelect(date)
        } label: {
            VStack(spacing: 2) {
                Text(weekday)
                    .font(DesignTokens.Typography.label)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)

                Text("\(date.day)")
                    .font(DesignTokens.Typography.secondary.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.white : (isToday ? Color.accentColor : Color.primary))
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                    .fill(isSelected ? Color.accentColor : Color(uiColor: .tertiarySystemFill).opacity(0.6))
            )
        }
        .buttonStyle(.plain)
    }
}

/// 课表头部：标题 + 学期副标题 + `日/周/月` 视图切换，仅日视图显示一周日期条。
struct ScheduleHeaderView: View {

    let semester: Semester
    let title: String
    let mode: ScheduleMode

    /// 当前应当高亮/展示的一周（周视图是整周，日视图是所选日期所在周）。
    let weekDates: [CalendarDate]
    let selectedDate: CalendarDate

    var onSelectMode: (ScheduleMode) -> Void
    var onSelectDate: (CalendarDate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.item) {
            titleRow
            if mode == .day {
                WeekStripView(dates: weekDates, selectedDate: selectedDate, onSelect: onSelectDate)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
}

extension ScheduleHeaderView {

    /// 标题行：左边大标题 + 学期副标题，右边 `日 | 周 | 月` 视图切换。
    private var titleRow: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignTokens.Typography.pageTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(semester.name)
                    .font(DesignTokens.Typography.pageSubtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Picker("视图", selection: modeBinding) {
                ForEach(ScheduleMode.segmentedCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 156)
            .padding(.top, 6)
        }
        .padding(.horizontal, DesignTokens.Spacing.page)
    }

    private var modeBinding: Binding<ScheduleMode> {
        Binding(
            get: { mode },
            set: { onSelectMode($0) }
        )
    }
}

#Preview("课表头部") {
    let seed = PreviewSupport.seed
    let week = seed.timetable.dates(inWeek: 1)

    return VStack {
        ScheduleHeaderView(
            semester: seed.semester,
            title: "1月12-18日",
            mode: .week,
            weekDates: week,
            selectedDate: week.first ?? seed.monday,
            onSelectMode: { _ in },
            onSelectDate: { _ in }
        )
        Spacer()
    }
}
