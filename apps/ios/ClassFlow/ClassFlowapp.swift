import SwiftUI

@main
struct ClassFlowApp: App {

    @State private var store: AppStore
    /// 桌面组件的深链路由（`classflow://…`）
    @State private var router = AppRouter()
    /// 课程 Live Activity 的启动 / 收尾控制器
    @State private var liveActivity: CourseLiveActivityController
    /// 按课表时间自动开关课程 Live Activity
    @State private var liveActivityScheduler: CourseLiveActivityScheduler

    init() {
        let store = AppStore(store: FileDataStore(url: FileDataStore.defaultURL()))
        let liveActivity = CourseLiveActivityController()

        _store = State(initialValue: store)
        _liveActivity = State(initialValue: liveActivity)
        _liveActivityScheduler = State(
            initialValue: CourseLiveActivityScheduler(store: store, controller: liveActivity)
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(router)
                .environment(liveActivity)
                .environment(liveActivityScheduler)
                .preferredColorScheme(store.preferences.appearance.colorScheme)
        }
    }
}

#Preview("应用根视图") {
    ContentView()
        .environment(PreviewSupport.store)
        .environment(AppRouter())
}
