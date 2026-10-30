import SwiftUI

/// 导入候选记录的一行；校验错误必须对用户可见。
struct ImportEntryRow: View {

    let entry: ImportDraftEntry
    var showsCourseName = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(showsCourseName ? entry.displayName : "\(entry.weekday?.shortName ?? "未指定星期") · \(entry.timeDescription)")
                    .font(.body)
                    .foregroundStyle(.primary)

                statusChip
            }

            if showsCourseName {
                HStack(spacing: 10) {
                    Label(entry.weekday?.shortName ?? "未指定星期", systemImage: "calendar")
                    Label(entry.timeDescription, systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Label(entry.imageReview?.requiresWeekConfirmation == true ? "周次待核对" : entry.weekRule.displayName,
                systemImage: "repeat")
            .font(.caption)
            .foregroundStyle(.secondary)

            if entry.location != nil || entry.teacher != nil {
                HStack(spacing: 10) {
                    if let location = entry.location {
                        Label(location, systemImage: "mappin.and.ellipse")
                    }
                    if let teacher = entry.teacher {
                        Label(teacher, systemImage: "person")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            if let note = entry.imageReview?.notes.first {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let issue = entry.issues.first {
                Label(issue.message, systemImage: "exclamationmark.circle")
                    .font(.caption2)
                    .foregroundStyle(entry.status == .invalid ? Color.red : Color.orange)
            }
        }
        .padding(.vertical, 2)
        .opacity(entry.isSelected ? 1 : 0.5)
    }

    private var statusChip: some View {
        Text(entry.imageReview?.requiresClassReview == true ? "待核对" : entry.status.displayName)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.15), in: Capsule())
            .foregroundStyle(statusColor)
    }

    private var statusColor: Color {
        if entry.imageReview?.requiresClassReview == true { return .orange }
        return switch entry.status {
        case .ready: .green
        case .needsCorrection: .orange
        case .invalid: .red
        case .committed: .blue
        case .pending, .parsed: .secondary
        case .skipped: .gray
        }
    }
}

/// 冲突提示行。
struct ImportConflictRow: View {

    let conflict: ImportConflict

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: conflict.kind.isTimeOverlap ? "exclamationmark.triangle.fill" : "info.circle")
                    .foregroundStyle(conflict.kind.isTimeOverlap ? Color.orange : Color.secondary)
                Text(conflict.kind.displayName)
                    .font(.subheadline)
            }

            Text(conflict.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// 一次导入提交的结果汇总。
struct ImportResultView: View {

    let result: ImportCommitResult
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(result.summaryText, systemImage: result.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(result.succeeded ? Color.green : Color.red)
                } header: {
                    Text("提交状态")
                }

                if !result.committedEntryIds.isEmpty {
                    Section("已导入") {
                        LabeledContent("记录", value: "\(result.committedEntryIds.count) 条")
                        LabeledContent("涉及课程", value: "\(result.committedCourseIds.count) 门")
                    }
                }

                if !result.skippedEntryIds.isEmpty {
                    Section("已跳过") {
                        LabeledContent("记录", value: "\(result.skippedEntryIds.count) 条")
                    }
                }

                if !result.issues.isEmpty {
                    Section("未通过校验的记录") {
                        ForEach(result.issues, id: \.entryId) { failure in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(failure.message)
                                    .font(.callout)
                                Text(failure.code)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(result.status.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { onDone() }
                }
            }
        }
    }
}

#Preview("记录行") {
    List {
        ImportEntryRow(
            entry: ImportDraftEntry(
                draftId: UUID(),
                sourceIndex: 0,
                courseName: "高等数学",
                teacher: "王老师",
                location: "教三201",
                weekday: .monday,
                startPeriod: 1,
                endPeriod: 2,
                status: .ready
            )
        )
        ImportConflictRow(
            conflict: ImportConflict(
                draftId: UUID(),
                kind: .existingSchedule,
                firstEntryId: UUID(),
                firstLabel: "大学物理",
                secondLabel: "高等数学",
                weekday: .monday,
                overlapDescription: "时间重叠 08:55-09:40",
                weeksDescription: "第 1-16 周"
            )
        )
    }
}
