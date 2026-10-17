import SwiftUI

/// 学期管理页：全部学期列表与添加学期入口。
struct SemesterListScreen: View {

    @Environment(AppStore.self) private var store

    @State private var showsNewSemester = false

    var body: some View {
        List {
            Section {
                if store.semesters.isEmpty {
                    Text("还没有学期")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.semesters) { semester in
                        NavigationLink {
                            SemesterDetailScreen(semesterId: semester.id)
                        } label: {
                            row(semester)
                        }
                    }
                }
            } header: {
                Text("全部学期")
            } footer: {
                Text("历史学期及其数据会保留。")
            }

            Section {
                Button {
                    showsNewSemester = true
                } label: {
                    Label("添加学期", systemImage: "plus")
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("学期管理")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsNewSemester) {
            SemesterEditView()
        }
    }
}

extension SemesterListScreen {

    @ViewBuilder
    private func row(_ semester: Semester) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(semester.name)
                    .font(DesignTokens.Typography.sectionTitle)
                    .foregroundStyle(.primary)

                if store.currentSemester?.id == semester.id {
                    Text("V当前")
                        .font(DesignTokens.Typography.label)
                        .foregroundStyle(Color.accentColor)
                }
            }

            Text(semester.dateRangeText)
                .font(DesignTokens.Typography.secondary)
                .foregroundStyle(.secondary)

            Text("\(store.courses(in: semester.id).count) 门课程")
                .font(DesignTokens.Typography.secondary)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview("学期管理") {
    NavigationStack {
        SemesterListScreen()
    }
    .environment(PreviewSupport.store)
}

#Preview("学期管理 · 空") {
    NavigationStack {
        SemesterListScreen()
    }
    .environment(PreviewSupport.blankStore)
}
