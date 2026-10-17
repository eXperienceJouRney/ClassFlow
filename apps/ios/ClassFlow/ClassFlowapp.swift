import SwiftUI

@main
struct ClassFlowApp: App {

    @State private var store = AppStore(store: FileDataStore(url: FileDataStore.defaultURL()))
    /// 桌面组件的深链路由（`classflow://…`）
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(router)
                .preferredColorScheme(store.preferences.appearance.colorScheme)
        }
    }
}

#Preview("应用根视图") {
    ContentView()
        .environment(PreviewSupport.store)
        .environment(AppRouter())
}
