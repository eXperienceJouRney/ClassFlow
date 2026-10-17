import SwiftUI

/// 时间冲突提示；只做提示，不修改任何数据。
struct ScheduleConflictWarningView: View {

    let conflicts: [ScheduleConflict]
    var title: String = "时间冲突"
    @State private var showsDetails = false

    var body: some View {
        if !conflicts.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    showsDetails.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("发现 \(conflicts.count) 处\(title)")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                        Image(systemName: showsDetails ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                if showsDetails {
                    ForEach(conflicts) { conflict in
                        Text(conflict.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

#Preview {
    ScheduleConflictWarningView(
        conflicts: [
            ScheduleConflict(
                firstCourseName: "高等数学",
                secondCourseName: "大学物理",
                dateDescription: "周一 第 1-16 周",
                overlapDescription: "时间重叠 08:55-09:40"
            )
        ]
    )
}
