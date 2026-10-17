import Foundation
import Observation

/// 从桌面组件跳回 App 的目的地 + 当前 Tab；只负责「去哪」，呈现方式留给页面。
/// 页面侧用可选的环境读取（`@Environment(AppRouter.self) var router: AppRouter?`），未注入时不会崩。
@MainActor
@Observable
final class AppRouter {

    enum Tab: Hashable {
        case schedule
        case tasks
        case notes
    }

    /// 当前选中的顶级 Tab（`ContentView` 的 `TabView` 绑它）
    var selectedTab: Tab = .schedule

    /// 待处理的深链；页面处理完后置回 nil。
    var pending: WidgetDeepLink.Destination?

    init(selectedTab: Tab = .schedule) {
        self.selectedTab = selectedTab
    }

    func handle(_ url: URL) {
        guard let destination = WidgetDeepLink.parse(url) else { return }
        dispatch(destination)
    }

    func dispatch(_ destination: WidgetDeepLink.Destination) {
        pending = nil

        switch destination {
        case .tasks, .task:
            selectedTab = .tasks
        case .notes, .memo, .newMemo:
            selectedTab = .notes
        case .course, .scheduleToday, .scheduleWeek, .periodTimes:
            selectedTab = .schedule
        }

        pending = destination
    }

    /// 取走组件按钮写下的待处理深链（App Intent 那条路）。
    func consumeWidgetRequests() {
        guard let destination = WidgetDeepLink.takePending() else { return }
        dispatch(destination)
    }

    /// 页面处理完深链后回调，避免同一目标被反复触发。
    func finish(_ destination: WidgetDeepLink.Destination) {
        guard pending == destination else { return }
        pending = nil
    }
}

#if DEBUG
extension AppRouter {

    /// 演示 / 截图脚本入口：启动参数 `-demoScreen <路径>`，取 `classflow://` 之后那一段。
    /// 取值：`tasks` / `notes` / `schedule/today` / `schedule/week?offset=0` / `course/<UUID>` / `task/<UUID>` / `settings/period-times`。
    func applyDemoScreenArgument(_ value: String? = UserDefaults.standard.string(forKey: "demoScreen")) {
        guard let value, let url = URL(string: "\(WidgetDeepLink.scheme)://\(value)") else { return }
        handle(url)
    }
}
#endif
