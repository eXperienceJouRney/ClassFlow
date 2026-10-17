import SwiftUI

/// 应用主框架：课表 · 待办 · 笔记三个顶级 Tab。
/// 负责转发 `classflow://` 深链与组件待处理请求，并在回到前台时刷新共享数据。
struct ContentView: View {

    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
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
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }

            store.reload()
            router.consumeWidgetRequests()
        }
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
