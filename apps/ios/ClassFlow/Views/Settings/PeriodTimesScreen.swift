import SwiftUI

/// 课节与作息时间编辑页：维护当前学期各课节的起止时刻。
/// 无保存按钮，改动即时落盘；开始晚于结束的状态只提示、不写入。
struct PeriodTimesScreen: View {

    @Environment(AppStore.self) private var store

    @State private var periods: [ClassPeriodInput] = []
    /// 最近一次落盘的课节快照，用于判断是否需要写盘。
    @State private var savedPeriods: [ClassPeriodInput] = []
    @State private var semesterId: UUID?
    @State private var editMode: EditMode = .inactive
    @State private var isLoaded = false

    var body: some View {
        List {
            if semesterId == nil {
                Section {
                    Text("请先创建一个学期").foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(periods.indices, id: \.self) { index in
                        periodRow(index)
                    }
                    .onDelete { offsets in
                        // 删除课节后不重排其余编号。
                        periods.remove(atOffsets: offsets)
                    }
                    .onMove { source, destination in
                        periods.move(fromOffsets: source, toOffset: destination)
                        renumber()
                    }

                    Button("+添加课节") { appendPeriod() }
                } header: {
                    sectionHeader
                } footer: {
                    if hasInvalidPeriods {
                        Text("开始时刻必须早于结束时刻。")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(editMode == .active ? "完成" : "管理课节") {
                        withAnimation {
                            editMode = editMode == .active ? .inactive : .active
                        }
                    }
                } footer: {
                    Text("保留原有课节编号")
                }
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("课节与作息时间")
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
        .onChange(of: periods) { _, newValue in
            guard isLoaded, newValue != savedPeriods else { return }
            persist(newValue)
        }
    }
}

// MARK: - 区块与行

extension PeriodTimesScreen {

    private var sectionHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("当前学期・\(store.currentSemester?.name ?? "未设置")")
            Text("作息时间仅用于当前学期。")

            HStack {
                Text("课节")
                Spacer()
                Text(store.preferences.timeFormat.displayName)
            }
            .padding(.top, 6)
        }
        .font(DesignTokens.Typography.caption)
        .foregroundStyle(.secondary)
    }

    /// 第 N 节行：开始 / 结束两列的行内编辑。
    private func periodRow(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("第\(periods[index].periodNumber)节")
                    .font(DesignTokens.Typography.body)
                    .frame(width: 56, alignment: .leading)

                Text("开始")
                    .font(DesignTokens.Typography.label)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("结束")
                    .font(DesignTokens.Typography.label)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                Color.clear
                    .frame(width: 56, height: 1)

                DatePicker(
                    "开始",
                    selection: timeBinding(index, \.startTime),
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)

                DatePicker(
                    "结束",
                    selection: timeBinding(index, \.endTime),
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 2)
    }

    private func timeBinding(
        _ index: Int,
        _ keyPath: WritableKeyPath<ClassPeriodInput, TimeOfDay>
    ) -> Binding<Date> {
        Binding(
            get: { periods[index][keyPath: keyPath].dateValue() },
            set: { newValue in
                guard let time = TimeOfDay.from(newValue) else { return }
                periods[index][keyPath: keyPath] = time
            }
        )
    }
}

// MARK: - 载入与保存

extension PeriodTimesScreen {

    private var hasInvalidPeriods: Bool {
        periods.contains { $0.startTime >= $0.endTime }
    }

    private func load() {
        guard !isLoaded else { return }

        guard let semester = store.currentSemester else {
            semesterId = nil
            isLoaded = true
            return
        }

        semesterId = semester.id

        let stored = store.periodTimes(in: semester.id).map {
            ClassPeriodInput(
                periodNumber: $0.periodNumber,
                startTime: $0.startTime,
                endTime: $0.endTime
            )
        }

        let initial = stored.isEmpty ? ClassPeriodTime.defaults(for: semester.id).map {
            ClassPeriodInput(
                periodNumber: $0.periodNumber,
                startTime: $0.startTime,
                endTime: $0.endTime
            )
        } : stored
        periods = initial
        savedPeriods = initial
        isLoaded = true
    }

    private func persist(_ newValue: [ClassPeriodInput]) {
        guard let semesterId else { return }
        guard !newValue.contains(where: { $0.startTime >= $0.endTime }) else { return }

        do {
            try store.setPeriodTimes(newValue, for: semesterId)
            savedPeriods = newValue
        } catch {
            // 写盘失败不打断输入。
        }
    }

    /// 按当前位置重排课节编号。
    private func renumber() {
        for index in periods.indices {
            periods[index].periodNumber = index + 1
        }
    }

    private func appendPeriod() {
        let nextNumber = (periods.map(\.periodNumber).max() ?? 0) + 1
        let start = periods.last?.endTime ?? TimeOfDay(hour: 8, minute: 0)!
        let end = TimeOfDay(
            hour: min(start.hour + 1, 23),
            minute: start.minute
        ) ?? start

        periods.append(
            ClassPeriodInput(
                periodNumber: nextNumber,
                startTime: start,
                endTime: end
            )
        )
    }
}

#Preview("课节与作息时间 · 已配置") {
    NavigationStack {
        PeriodTimesScreen()
    }
    .environment(PreviewSupport.store)
}

#Preview("课节与作息时间 · 未配置（显示内置默认作息）") {
    NavigationStack {
        PeriodTimesScreen()
    }
    .environment(PreviewSupport.emptyStore)
}

#Preview("课节与作息时间 · 还没有学期") {
    NavigationStack {
        PeriodTimesScreen()
    }
    .environment(PreviewSupport.blankStore)
}
