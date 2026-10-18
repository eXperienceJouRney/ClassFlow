import SwiftUI

/// 应用主框架：课表 · 待办 · 笔记三个顶级 Tab。
/// 负责转发 `classflow://` 深链与组件待处理请求，并在回到前台时刷新共享数据。
struct ContentView: View {

    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(CourseLiveActivityController.self) private var liveActivity: CourseLiveActivityController?
    @Environment(CourseLiveActivityScheduler.self) private var liveActivityScheduler: CourseLiveActivityScheduler?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            ScheduleScreen()
                .tabItem { Label("课表", systemImage: "calendar") }
                .tag(AppRouter.Tab.schedule)

            TaskListScreen()
                .tabItem { Label("待办", systemImage: "checklist") }
                .tag(AppRouter.Tab.tasks)

            NotesScreen()
                .tabItem { Label("笔记", systemImage: "note.text") }
                .tag(AppRouter.Tab.notes)
        }
        .onOpenURL { url in
            router.handle(url)
        }
        .task {
            #if DEBUG
            router.applyDemoScreenArgument()
            #endif
            router.consumeWidgetRequests()
            await reconcileLiveActivity(reloadingPreferences: true)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                store.reload()
                router.consumeWidgetRequests()
                Task { await reconcileLiveActivity(reloadingPreferences: true) }

            case .background:
                // 后台无法启动实时活动：停掉边界定时器，回前台再重新排。
                liveActivityScheduler?.suspend()

            default:
                break
            }
        }
        // 课程时间被改、课程被取消、切换学期……都会让 `revision` +1。
        // 不能只观察 `data`：`ScheduleEntry` / `Course` 的相等性只看 id，字段级改动不会触发。
        .onChange(of: store.revision) { _, _ in
            guard scenePhase == .active else { return }
            Task { await reconcileLiveActivity() }
        }
    }
}

// MARK: - 课程实时活动

extension ContentView {

    /// 启动 / 回前台 / 数据变化时，把 Live Activity 与当前课表对齐。
    ///
    /// 优先交给调度器：它会在打开「自动显示当前课程」时启动当前课，并在
    /// 下课 / 下一节上课两个边界重新评估。没有调度器（预览）时退回手动模式的对账。
    private func reconcileLiveActivity(reloadingPreferences: Bool = false) async {
        if let liveActivityScheduler {
            if reloadingPreferences {
                await liveActivityScheduler.activate()
            } else {
                await liveActivityScheduler.sync()
            }
            return
        }

        guard let liveActivity else { return }

        let now = Date()
        let current = store.currentClassSession(at: now)
        let next = current.flatMap { store.nextClassSession(after: $0) }
        await liveActivity.reconcile(currentSession: current, nextSession: next, now: now)
    }
}

#Preview("主框架") {
    ContentView()
        .environment(PreviewSupport.store)
        .environment(AppRouter())
}

#Preview("主框架 · 空数据") {
    ContentView()
        .environment(PreviewSupport.blankStore)
        .environment(AppRouter())
}
