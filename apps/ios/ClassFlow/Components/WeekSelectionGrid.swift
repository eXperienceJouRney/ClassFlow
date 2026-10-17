import SwiftUI

struct WeekSelectionGrid: View {

    let weekCount: Int
    @Binding var selection: Set<Int>

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(1...max(weekCount, 1), id: \.self) { week in
                Button {
                    toggle(week)
                } label: {
                    Text("\(week)")
                        .font(.caption)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(
                            selection.contains(week)
                                ? Color.accentColor
                                : Color(uiColor: .tertiarySystemFill),
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .foregroundStyle(selection.contains(week) ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func toggle(_ week: Int) {
        if selection.contains(week) {
            selection.remove(week)
        } else {
            selection.insert(week)
        }
    }
}

private struct WeekSelectionGridPreview: View {

    @State private var customWeeks: Set<Int> = [1, 2, 3, 5, 8]

    var body: some View {
        Form {
            Section("勾选上课周次") {
                WeekSelectionGrid(weekCount: 16, selection: $customWeeks)
            }
            Section("带快速选择的上课周次编辑") {
                WeekSelectionEditor(weekCount: 16, selection: $customWeeks)
            }
        }
    }
}

#Preview("周次网格") {
    WeekSelectionGridPreview()
}
