import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 课表导入流程；识别结果只形成草稿，用户确认提交前不写入正式课程数据。
struct ImportScreen: View {

    @Environment(AppStore.self) private var store

    @State private var selectedSemesterId: UUID?
    @State private var draftId: UUID?
    @State private var pastedText = ""
    @State private var showsTextSheet = false
    @State private var showsFileImporter = false
    @State private var showsImageImport = false
    @State private var imagePreview: UIImage?
    @State private var imagePreviewDraftId: UUID?
    @State private var showsImagePreview = false
    @State private var editingEntry: ImportDraftEntry?
    @State private var collapsedCourseIDs: Set<UUID> = []
    @State private var expandedClassIDs: Set<UUID> = []
    @State private var conflicts: [ImportConflict] = []
    @State private var conflictStrategy: ImportConflictStrategy = .keepAll
    @State private var commitResult: ImportCommitResult?
    @State private var showsResult = false
    @State private var errorMessage: String?

    /// 传入草稿 id 时直接继续该草稿；草稿持久化，重新进入不丢进度。
    init(draftId: UUID? = nil) {
        _draftId = State(initialValue: draftId)
    }

    private var draft: ImportDraft? {
        guard let draftId else { return nil }
        return store.importDraft(id: draftId)
    }

    private var semester: Semester? {
        guard let semesterId = draft?.semesterId ?? selectedSemesterId else { return nil }
        return store.data.semester(id: semesterId)
    }

    /// 尚未提交完成的草稿，供用户继续处理。
    private var resumableDrafts: [ImportDraft] {
        store.importDrafts.filter { !$0.status.isFinished || $0.status == .failed }
    }

    var body: some View {
        List {
            if let draft, let semester {
                draftSourceSection(draft)
                entriesSection(draft, semester: semester)
                periodCandidateSection(draft)
                conflictSection(draft)
                commitSection(draft)
            } else {
                resumeSection
                semesterSection
                sourceSection
            }
        }
        .navigationTitle("课表导入")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if selectedSemesterId == nil {
                selectedSemesterId = store.currentSemester?.id
            }
            if draftId == nil, let resumable = resumableDrafts.first {
                selectedSemesterId = resumable.semesterId
            }
        }
        .sheet(isPresented: $showsTextSheet) { textSheet }
        .sheet(isPresented: $showsImageImport) {
            if let semesterId = selectedSemesterId {
                TimetableImageImportView(semesterId: semesterId) { draft, preview in
                    imagePreview = preview
                    imagePreviewDraftId = draft.id
                    resume(draft)
                }
            }
        }
        .sheet(isPresented: $showsImagePreview) {
            NavigationStack {
                Group {
                    if let imagePreview {
                        TimetableImagePreview(image: imagePreview)
                    }
                }
                .navigationTitle("核对原图")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { showsImagePreview = false }
                    }
                }
            }
        }
        .sheet(item: $editingEntry) { entry in
            if let semester {
                ImportEntryEditView(semester: semester, entry: entry) { edit in
                    apply(edit, to: entry)
                }
            }
        }
        .sheet(isPresented: $showsResult) {
            if let commitResult {
                ImportResultView(result: commitResult) {
                    showsResult = false
                    if commitResult.succeeded {
                        draftId = nil
                        imagePreview = nil
                        imagePreviewDraftId = nil
                        conflicts = []
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: [.plainText, .commaSeparatedText, .text, .utf8PlainText],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
        .errorAlert($errorMessage)
    }
}

// MARK: - 未选择来源

extension ImportScreen {

    @ViewBuilder
    private var resumeSection: some View {
        if !resumableDrafts.isEmpty {
            Section {
                ForEach(resumableDrafts) { item in
                    Button {
                        resume(item)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.data.semester(id: item.semesterId)?.name ?? item.sourceKind.displayName)
                                .foregroundStyle(.primary)
                            Text(item.summaryText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("继续未完成的草稿")
            } footer: {
                Text("草稿保存在本地，关掉应用也不会丢失；提交成功或放弃后才会消失。")
            }
        }
    }

    @ViewBuilder
    private var semesterSection: some View {
        Section {
            if store.semesters.isEmpty {
                Text("还没有学期，请先到设置里创建学期")
                    .foregroundStyle(.secondary)
            } else {
                Picker("学期", selection: $selectedSemesterId) {
                    Text("未选择").tag(UUID?.none)
                    ForEach(store.semesters) { item in
                        Text(item.name).tag(UUID?.some(item.id))
                    }
                }
            }
        } header: {
            Text("1 · 选择目标学期")
        } footer: {
            Text("导入的课程会归属于所选学期。")
        }
    }

    @ViewBuilder
    private var sourceSection: some View {
        Section {
            ForEach(ImportSourceKind.allCases, id: \.self) { kind in
                Button {
                    selectSource(kind)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.displayName)
                            .foregroundStyle(.primary)
                        Text(kind.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(selectedSemesterId == nil)
            }
        } header: {
            Text("2 · 选择导入方式")
        } footer: {
            Text("识别结果先形成草稿，只有确认提交后才会写入正式课程数据。")
        }
    }
}

// MARK: - 草稿内容

extension ImportScreen {

    @ViewBuilder
    private func draftSourceSection(_ draft: ImportDraft) -> some View {
        Section {
            LabeledContent("学期", value: store.data.semester(id: draft.semesterId)?.name ?? "未知学期")
            LabeledContent("来源", value: draft.sourceName ?? draft.sourceKind.displayName)
            LabeledContent("状态", value: draft.status.displayName)
            if let className = draft.entries.compactMap({ $0.imageReview?.selectedClassName }).first {
                LabeledContent("所选班级", value: className)
            }
            if draft.sourceKind == .image, imagePreview != nil {
                Button("核对原图", systemImage: "photo") { showsImagePreview = true }
            }
            if draft.entries.contains(where: { $0.imageReview?.requiresClassReview == true }) {
                Label(ImportImageReview.classReviewMessage, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("导入草稿")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.summaryText)
                if draft.sourceKind == .image {
                    Text("识图可能犯错，请核对课程、周次和课节。可以点击课程手动修改。")
                }
            }
        }
    }

    @ViewBuilder
    private func entriesSection(_ draft: ImportDraft, semester: Semester) -> some View {
        Section {
            ForEach(draft.courseGroups) { group in
                DisclosureGroup(isExpanded: courseGroupExpansion(group.id)) {
                    ForEach(group.classResolvedEntries) { entry in
                        arrangementRow(entry, in: draft)
                    }
                    ForEach(group.unresolvedClassGroups) { classGroup in
                        classGroupRows(classGroup, courseName: group.displayName, in: draft)
                    }
                } label: {
                    HStack {
                        Text(group.displayName)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        Text("\(group.entries.count) 条安排")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if draft.status != .succeeded {
                Button("添加一条上课安排", systemImage: "plus") {
                    addEntry(to: draft)
                }
            }
        } header: {
            Text("3 · 预览与修正（\(draft.courseGroups.count) 门课程 · \(draft.entries.count) 条安排）")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if draft.entries.count > 1 {
                    HStack(spacing: 12) {
                        Button("全选") { setAll(draft, selected: true) }
                        Button("全不选") { setAll(draft, selected: false) }
                    }
                }
                Text("同名课程归为一门课，各条安排保留自己的时间、周次和教室。点击安排可修改，勾选决定是否导入。")
                if draft.entries.contains(where: { $0.imageReview?.requiresClassReview == true }) {
                    Text("待核对的安排先按原图课堂分组。勾选课堂会选中该课堂的全部安排，也可逐条调整。")
                }
            }
            .font(.caption)
        }
    }

    private func courseGroupExpansion(_ id: UUID) -> Binding<Bool> {
        Binding(get: { !collapsedCourseIDs.contains(id) }, set: { expanded in
            if expanded { collapsedCourseIDs.remove(id) } else { collapsedCourseIDs.insert(id) }
        })
    }

    @ViewBuilder
    private func classGroupRows(_ group: ImportDraftClassGroup, courseName: String, in draft: ImportDraft) -> some View {
        let expanded = expandedClassIDs.contains(group.id)
        // 选择与展开使用并列按钮，点击课堂标题只展开，不同时勾选整组。
        HStack(spacing: 8) {
            Button {
                toggleClassSelection(group, in: draft)
            } label: {
                Image(systemName: group.isFullySelected ? "checkmark.circle.fill"
                    : group.isPartiallySelected ? "minus.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(group.selectedCount > 0 ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(draft.status == .succeeded)
            .accessibilityLabel("\(courseName)，\(group.displayName)，选择全部安排")
            .accessibilityValue(group.isFullySelected ? "已全选" : group.isPartiallySelected ? "部分已选" : "未选择")

            Button {
                if expanded { expandedClassIDs.remove(group.id) } else { expandedClassIDs.insert(group.id) }
            } label: {
                HStack(spacing: 8) {
                    Text(group.displayName)
                        .foregroundStyle(.primary)
                    Text("待核对")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Spacer(minLength: 4)
                    Text("\(group.entries.count) 条安排")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(courseName)，\(group.displayName)，\(expanded ? "收起" : "展开")，\(group.entries.count)条安排")
        }
        if expanded {
            ForEach(group.entries) { entry in
                arrangementRow(entry, in: draft)
                    .padding(.leading, 16)
            }
        }
    }

    private func arrangementRow(_ entry: ImportDraftEntry, in draft: ImportDraft) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                toggleSelection(entry, in: draft)
            } label: {
                Image(systemName: entry.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(entry.isSelected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(draft.status == .succeeded)

            Button {
                editingEntry = entry
            } label: {
                ImportEntryRow(entry: entry, showsCourseName: false)
            }
            .buttonStyle(.plain)
            .disabled(draft.status == .succeeded)
        }
        .swipeActions(edge: .trailing) {
            if draft.status != .succeeded {
                Button("删除", role: .destructive) { remove(entry, in: draft) }
            }
        }
    }

    @ViewBuilder
    private func periodCandidateSection(_ draft: ImportDraft) -> some View {
        let candidates = store.importedPeriodTimeCandidates(draftId: draft.id)

        if !candidates.isEmpty {
            Section {
                ForEach(candidates, id: \.periodNumber) { candidate in
                    LabeledContent(
                        "第 \(candidate.periodNumber) 节",
                        value: "\(candidate.startTime.displayText)-\(candidate.endTime.displayText)"
                    )
                }

                Button("写入学期作息") { applyPeriodCandidates(draft) }
            } header: {
                Text("识别到课节钟点")
            } footer: {
                Text("目标学期还没有对应的课节配置。钟点不会写进课程安排，只会作为学期作息的候选值；写入后按课节的课程会使用它。")
            }
        }
    }

    @ViewBuilder
    private func conflictSection(_ draft: ImportDraft) -> some View {
        Section {
            if conflicts.isEmpty {
                Label("未发现时间冲突", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(conflicts) { conflict in
                    ImportConflictRow(conflict: conflict)
                }

                if conflicts.contains(where: { $0.kind.isTimeOverlap }) {
                    Picker("冲突处理", selection: $conflictStrategy) {
                        ForEach(ImportConflictStrategy.allCases, id: \.self) { strategy in
                            Text(strategy.displayName).tag(strategy)
                        }
                    }
                }
            }

            Button("重新检查冲突") { refreshConflicts(draft) }
                .disabled(draft.status == .succeeded)
        } header: {
            Text("4 · 冲突检查")
        } footer: {
            Text("同一学期内课程名相同即视为同一门课程，学期里已存在的同名课程会直接并入。导入不会删除或覆盖已有安排；存在时间冲突时需确认后才能继续。")
        }
    }

    @ViewBuilder
    private func commitSection(_ draft: ImportDraft) -> some View {
        Section {
            Button("确认提交") { commit(draft) }
                .disabled(draft.selectedCount == 0 || draft.status == .succeeded)

            if draft.status == .succeeded {
                Button("查看提交结果") {
                    commitResult = store.importCommitResult(draftId: draft.id)
                    showsResult = true
                }
            }

            Button("放弃这份草稿", role: .destructive) { discard(draft) }
        } header: {
            Text("5 · 提交")
        } footer: {
            Text("提交会把全部选中且通过校验的记录一次性写入；只要有一条记录未通过校验，整次提交都不会写入任何课程。")
        }
    }

    @ViewBuilder
    private var textSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $pastedText)
                        .frame(minHeight: 200)
                        .font(.body.monospaced())
                } header: {
                    Text("每行一条课程")
                } footer: {
                    Text("例如：高等数学,周一,第1-2节,1-16周,教三201,王老师")
                }
            }
            .navigationTitle("粘贴课表文本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showsTextSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("解析") { parsePastedText() }
                        .disabled(pastedText.isBlank)
                }
            }
        }
    }
}

// MARK: - 动作

extension ImportScreen {

    private func resume(_ draft: ImportDraft) {
        if draftId != draft.id {
            collapsedCourseIDs = []
            expandedClassIDs = []
        }
        if imagePreviewDraftId != draft.id {
            imagePreview = nil
            imagePreviewDraftId = nil
        }
        draftId = draft.id
        selectedSemesterId = draft.semesterId
        conflictStrategy = .keepAll
        refreshConflicts(draft)
    }

    private func selectSource(_ kind: ImportSourceKind) {
        switch kind {
        case .manualEntry:
            startNewDraft(kind: .manualEntry, addFirstEntry: true)
        case .pastedText:
            pastedText = ""
            showsTextSheet = true
        case .file:
            showsFileImporter = true
        case .image:
            showsImageImport = true
        }
    }

    private func startNewDraft(kind: ImportSourceKind, addFirstEntry: Bool = false) {
        guard let semesterId = selectedSemesterId else { return }

        do {
            let draft = try store.createImportDraft(
                semesterId: semesterId,
                sourceKind: kind,
                sourceName: nil
            )
            if addFirstEntry {
                _ = try store.addManualImportEntry(draftId: draft.id)
            }
            draftId = draft.id
            conflicts = []
            conflictStrategy = .keepAll
            refreshConflicts(draft)
        } catch {
            errorMessage = error.userMessage
        }
    }

    private func parsePastedText() {
        guard let semesterId = selectedSemesterId else { return }

        do {
            let draft = try store.createImportDraft(semesterId: semesterId, sourceKind: .pastedText)
            do {
                _ = try store.parseImportSource(draftId: draft.id, text: pastedText)
            } catch {
                try? store.deleteImportDraft(id: draft.id)
                throw error
            }

            draftId = draft.id
            conflicts = []
            showsTextSheet = false
            refreshConflicts(draft)
        } catch {
            errorMessage = error.userMessage
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        guard let semesterId = selectedSemesterId else { return }

        do {
            guard let url = try result.get().first else { return }
            let draft = try store.createImportDraft(fromFileURL: url, semesterId: semesterId)
            draftId = draft.id
            conflicts = []
            refreshConflicts(draft)
        } catch {
            errorMessage = error.userMessage
        }
    }

    private func apply(_ edit: ImportEntryEdit, to entry: ImportDraftEntry) {
        guard let draftId else { return }

        do {
            _ = try store.updateImportEntry(draftId: draftId, entryId: entry.id, edit: edit)
            refreshConflicts(store.importDraft(id: draftId))
        } catch {
            errorMessage = error.userMessage
        }
    }

    private func toggleSelection(_ entry: ImportDraftEntry, in draft: ImportDraft) {
        do {
            _ = try store.setImportEntrySelection(
                draftId: draft.id,
                entryId: entry.id,
                isSelected: !entry.isSelected
            )
            refreshConflicts(store.importDraft(id: draft.id))
        } catch {
            errorMessage = error.userMessage
        }
    }

    private func setAll(_ draft: ImportDraft, selected: Bool) {
        do {
            _ = try store.setImportSelection(draftId: draft.id, isSelected: selected)
            refreshConflicts(store.importDraft(id: draft.id))
        } catch {
            errorMessage = error.userMessage
        }
    }

    private func toggleClassSelection(_ group: ImportDraftClassGroup, in draft: ImportDraft) {
        do {
            _ = try store.setImportSelection(draftId: draft.id, entryIds: Set(group.entries.map(\.id)),
                isSelected: !group.isFullySelected)
            refreshConflicts(store.importDraft(id: draft.id))
        } catch {
            errorMessage = error.userMessage
        }
    }

    private func addEntry(to draft: ImportDraft) {
        do {
            let entry = try store.addManualImportEntry(draftId: draft.id)
            editingEntry = entry
            refreshConflicts(store.importDraft(id: draft.id))
        } catch {
            errorMessage = error.userMessage
        }
    }

    private func remove(_ entry: ImportDraftEntry, in draft: ImportDraft) {
        do {
            _ = try store.removeImportEntry(draftId: draft.id, entryId: entry.id)
            refreshConflicts(store.importDraft(id: draft.id))
        } catch {
            errorMessage = error.userMessage
        }
    }

    private func applyPeriodCandidates(_ draft: ImportDraft) {
        do {
            _ = try store.applyImportedPeriodTimeCandidates(draftId: draft.id)
            refreshConflicts(store.importDraft(id: draft.id))
        } catch {
            errorMessage = error.userMessage
        }
    }

    private func refreshConflicts(_ draft: ImportDraft?) {
        guard let draft else {
            conflicts = []
            return
        }

        do {
            conflicts = try store.detectImportConflicts(draftId: draft.id)
        } catch {
            conflicts = []
        }
    }

    private func commit(_ draft: ImportDraft) {
        do {
            commitResult = try store.commitImportDraft(
                draftId: draft.id,
                userConfirmed: true,
                conflictStrategy: conflictStrategy
            )
            showsResult = true
        } catch {
            errorMessage = error.userMessage
        }
    }

    private func discard(_ draft: ImportDraft) {
        do {
            _ = try store.cancelImportDraft(draftId: draft.id)
            try store.deleteImportDraft(id: draft.id)
            draftId = nil
            imagePreview = nil
            imagePreviewDraftId = nil
            conflicts = []
        } catch {
            errorMessage = error.userMessage
        }
    }
}

#Preview("课表导入 · 新建") {
    NavigationStack {
        ImportScreen()
    }
    .environment(PreviewSupport.store)
}

#Preview("课表导入 · 继续未完成的草稿") {
    let seed = PreviewSupport.seed

    NavigationStack {
        ImportScreen(draftId: seed.importDraftId)
    }
    .environment(seed.store)
}
