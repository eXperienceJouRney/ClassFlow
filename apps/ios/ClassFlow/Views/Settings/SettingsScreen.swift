import SwiftUI

/// 设置页；页面自身不含 `NavigationStack`，由调用方提供外层导航容器。
struct SettingsScreen: View {

    @Environment(AppStore.self) private var store
    @Environment(CourseLiveActivityController.self) private var liveActivity: CourseLiveActivityController?

    @State private var showsNewSemester = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            semesterSection
            courseSection
            importSection
            preferencesSection
            liveActivitySection
            periodSection
            aboutSection
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsNewSemester) {
            SemesterEditView()
        }
        .errorAlert($errorMessage)
    }
}

// MARK: - 学期

extension SettingsScreen {

    @ViewBuilder
    private var semesterSection: some View {
        Section("学期") {
            if let semester = store.currentSemester {
                NavigationLink {
                    SemesterDetailScreen(semesterId: semester.id)
                } label: {
                    LabeledContent("当前学期", value: semester.name)
                }
            } else {
                LabeledContent("当前学期", value: "未设置")
                    .foregroundStyle(.secondary)
            }

            NavigationLink {
                SemesterListScreen()
            } label: {
                Text("管理学期")
            }
        }
    }
}

// MARK: - 课程

extension SettingsScreen {

    @ViewBuilder
    private var courseSection: some View {
        Section("课程") {
            NavigationLink {
                CourseManagementScreen()
            } label: {
                Text("管理课程")
            }
        }
    }
}

// MARK: - 导入

extension SettingsScreen {

    @ViewBuilder
    private var importSection: some View {
        Section("导入") {
            NavigationLink {
                ImportScreen()
            } label: {
                Text("导入课表")
            }
            NavigationLink("AI 识别配置") { AIImageImportSettingsView() }
        }
    }
}

// MARK: - 偏好设置

extension SettingsScreen {

    @ViewBuilder
    private var preferencesSection: some View {
        Section {
            Picker("默认课表视图", selection: preference(\.defaultScheduleMode)) {
                ForEach(ScheduleMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            Picker("每周起始日", selection: preference(\.firstWeekday)) {
                ForEach(Weekday.allCases, id: \.self) { weekday in
                    Text(weekday.shortName).tag(weekday)
                }
            }

            Picker("外观", selection: preference(\.appearance)) {
                ForEach(AppearancePreference.allCases) { item in
                    Text(item.displayName).tag(item)
                }
            }

            Picker("时间格式", selection: preference(\.timeFormat)) {
                ForEach(TimeFormatPreference.allCases) { item in
                    Text(item.displayName).tag(item)
                }
            }

            Toggle("周视图显示教师", isOn: preference(\.showsTeacherInWeekGrid))
        } header: {
            Text("偏好设置")
        } footer: {
            Text("周视图一列很窄：打开时授课教师只占一行，课程名与上课地点能多显示几行；关闭后这几行全部留给课程名与地点。日视图不受影响。")
        }
    }

    /// 偏好项的双向绑定；每次写入立即持久化，失败时置 `errorMessage`。
    private func preference<Value>(
        _ keyPath: WritableKeyPath<AppPreferences, Value>
    ) -> Binding<Value> {
        Binding(
            get: { store.preferences[keyPath: keyPath] },
            set: { newValue in
                do {
                    try store.updatePreferences { $0[keyPath: keyPath] = newValue }
                } catch {
                    errorMessage = error.userMessage
                }
            }
        )
    }
}

// MARK: - 实时活动

extension SettingsScreen {

    @ViewBuilder
    private var liveActivitySection: some View {
        Section {
            Toggle("自动显示当前课程", isOn: preference(\.autoStartLiveActivity))

            if liveActivity?.areActivitiesEnabled == false {
                LabeledContent("系统实时活动", value: "已关闭")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("实时活动")
        } footer: {
            Text("开启后，上课时自动在灵动岛和锁屏显示当前课程，下课后自动结束；下一节课开始时再自动切换。\n\niOS 只允许 App 在前台（或刚回到前台）时启动实时活动。App 被系统挂起后不会准点自动开始，回到 App 时会按当前课程立即校正；要做到完全准点需要推送通知。\n\n如果系统设置里关闭了 ClassFlow 的「实时活动」，这里不会生效。App 内没有手动开启的入口，活动只在打开本项时自动出现。")
        }
    }
}

// MARK: - 课节与作息时间

extension SettingsScreen {

    @ViewBuilder
    private var periodSection: some View {
        Section {
            NavigationLink {
                PeriodTimesScreen()
            } label: {
                LabeledContent("课节与作息时间", value: "\(periodCount) 节课")
            }
        } footer: {
            Text("作息时间按学期保存，只影响当前学期。")
        }
    }

    /// 当前学期生效的作息节数；未配置作息时返回内置默认节数。
    private var periodCount: Int {
        guard let semesterId = store.currentSemester?.id else { return 0 }
        return store.effectivePeriodTimes(in: semesterId).count
    }
}

// MARK: - 关于

extension SettingsScreen {

    @ViewBuilder
    private var aboutSection: some View {
        Section("关于") {
            NavigationLink {
                AboutScreen()
            } label: {
                Text("关于 ClassFlow")
            }

            NavigationLink {
                PrivacyScreen()
            } label: {
                Text("隐私")
            }

            LabeledContent("版本", value: AppVersion.displayText)
        }
    }
}

/// 应用版本号。
enum AppVersion {

    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    static var displayText: String { "\(shortVersion)（\(buildNumber)）" }
}

#Preview("设置") {
    NavigationStack {
        SettingsScreen()
    }
    .environment(PreviewSupport.store)
}

#Preview("设置 · 首次启动") {
    NavigationStack {
        SettingsScreen()
    }
    .environment(PreviewSupport.blankStore)
}
