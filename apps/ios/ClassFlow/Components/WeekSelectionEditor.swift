import SwiftUI

/// 上课周次选择：选中的周即上课的周，支持区间与单双周快捷选择。
struct WeekSelectionEditor: View {

    let weekCount: Int
    @Binding var selection: Set<Int>

    /// 快速选择区间端点，仅影响「a-b 周 / 单周 / 双周」三个快捷按钮；默认取当前已选周次的起止。
    @State private var rangeStart: Int
    @State private var rangeEnd: Int

    init(weekCount: Int, selection: Binding<Set<Int>>) {
        let total = max(weekCount, 1)
        let current = selection.wrappedValue

        self.weekCount = total
        self._selection = selection
        self._rangeStart = State(initialValue: current.min() ?? 1)
        self._rangeEnd = State(initialValue: current.max() ?? total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.item) {
            rangeRow
            quickRow
            WeekSelectionGrid(weekCount: weekCount, selection: $selection)
            summaryRow
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 快速选择

extension WeekSelectionEditor {

    /// 快速选择行：起止周次的两个下拉端点。
    private var rangeRow: some View {
        HStack(spacing: 6) {
            Text("快速选择")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.secondary)

            weekMenu(rangeStart) { rangeStart = $0 }
            Text("–").foregroundStyle(.secondary)
            weekMenu(rangeEnd) { rangeEnd = $0 }
            Text("周")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
    }

    private func weekMenu(_ value: Int, onSelect: @escaping (Int) -> Void) -> some View {
        Menu {
            ForEach(1...weekCount, id: \.self) { week in
                Button("第 \(week) 周") { onSelect(week) }
            }
        } label: {
            Text("\(value)")
                .font(DesignTokens.Typography.secondary.monospacedDigit())
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Color(uiColor: .tertiarySystemFill),
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                )
        }
    }

    private var quickRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                QuickChip(title: "\(normalizedStart)–\(normalizedEnd) 周") {
                    selection = WeekSelection.range(normalizedStart, normalizedEnd)
                }
                QuickChip(title: "单周") {
                    selection = WeekSelection.oddWeeks(from: normalizedStart, to: normalizedEnd)
                }
                QuickChip(title: "双周") {
                    selection = WeekSelection.evenWeeks(from: normalizedStart, to: normalizedEnd)
                }
                QuickChip(title: "全部") {
                    selection = WeekSelection.all(weekCount: weekCount)
                }
                QuickChip(title: "清空") {
                    selection = []
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
    }

    private var summaryRow: some View {
        Text(summaryText)
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(selection.isEmpty ? Color.red : Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 计算

extension WeekSelectionEditor {

    /// 区间端点始终落在 `1...weekCount` 里，并且起点不晚于终点。
    private var normalizedStart: Int {
        min(max(rangeStart, 1), normalizedEnd)
    }

    private var normalizedEnd: Int {
        min(max(rangeEnd, 1), weekCount)
    }

    private var summaryText: String {
        if selection.isEmpty {
            return "还没有选择周次，至少要选一周。"
        }

        let rule = WeekRule.compact(weeks: selection, weekCount: weekCount)

        if rule.pattern == .customWeeks && selection.count > 10 {
            return "已选 \(selection.count) 周"
        }
        return "已选 \(selection.count) 周：\(rule.displayName)"
    }
}

#Preview("上课周次 · 每周") {
    @Previewable @State var selection = Set(1...16)

    return Form {
        Section("上课周次") {
            WeekSelectionEditor(weekCount: 16, selection: $selection)
        }
    }
}

#Preview("上课周次 · 单周与自定义") {
    @Previewable @State var selection: Set<Int> = [1, 3, 5, 7, 9, 11, 13, 15]

    return Form {
        Section("上课周次") {
            WeekSelectionEditor(weekCount: 16, selection: $selection)
        }
    }
}
