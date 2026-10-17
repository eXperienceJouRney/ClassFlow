import AppIntents
import Foundation

// MARK: - 组件里的交互动作

// 这些 intent 主 App 与 widget 两个 target 都必须编译。

/// 勾选 / 取消勾选一条待办。
struct ToggleTaskDoneIntent: AppIntent {

    static var title: LocalizedStringResource = "勾选 ClassFlow 待办"

    static var description: IntentDescription? = IntentDescription(
        "在桌面上直接勾选或取消勾选一条 ClassFlow 待办。"
    )

    /// 就地完成，不把 App 拉到前台。
    static var openAppWhenRun: Bool = false

    @Parameter(title: "待办")
    var taskId: String

    init() {}

    init(taskId: UUID) {
        self.taskId = taskId.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: taskId) else { return .result() }

        await WidgetTaskAction.toggleDone(taskId: id)
        return .result()
    }
}

/// 左右箭头：把周课表往前 / 往后翻一周。
struct ShiftWidgetWeekIntent: AppIntent {

    static var title: LocalizedStringResource = "切换 ClassFlow 周课表"

    static var description: IntentDescription? = IntentDescription(
        "在桌面组件上把周课表往前或往后翻一周。"
    )

    static var openAppWhenRun: Bool = false

    /// -1 = 上一周，+1 = 下一周
    @Parameter(title: "方向")
    var delta: Int

    init() {}

    init(delta: Int) {
        self.delta = delta
    }

    func perform() async throws -> some IntentResult {
        await WidgetWeekAction.shift(by: delta)
        return .result()
    }
}

/// 打开 App 并落到指定页面：先把深链写进共享容器，回到前台时取走。
struct OpenWidgetLinkIntent: AppIntent {

    static var title: LocalizedStringResource = "打开 ClassFlow"

    static var description: IntentDescription? = IntentDescription(
        "从桌面组件跳到 ClassFlow 的指定页面。"
    )

    static var openAppWhenRun: Bool = true

    @Parameter(title: "目标")
    var link: String

    init() {}

    init(destination: WidgetDeepLink.Destination) {
        self.link = WidgetDeepLink.url(destination)?.absoluteString ?? "classflow://schedule/today"
    }

    func perform() async throws -> some IntentResult {
        guard let url = URL(string: link),
              let destination = WidgetDeepLink.parse(url)
        else { return .result() }

        await MainActor.run { WidgetDeepLink.storePending(destination) }
        return .result()
    }
}

// MARK: - 动作实现

/// 勾选待办：读盘 → 改状态 → 写回，不主动请求刷新（`widgetReloadKinds = []`）。
@MainActor
enum WidgetTaskAction {

    static func toggleDone(taskId: UUID, now: Date = Date()) {
        let store = FileDataStore(url: FileDataStore.defaultURL())
        store.widgetReloadKinds = []

        guard var data = try? store.load(),
              let index = data.tasks.firstIndex(where: { $0.id == taskId })
        else { return }

        var task = data.tasks[index]
        if task.status.isOpen {
            task.status = (try? task.status.transitioned(to: .completed)) ?? task.status
        } else {
            task.status = task.status.reopened
        }
        task.updatedAt = now
        data.tasks[index] = task

        // 保存会顺带重写组件快照，不能省掉这一步。
        try? store.save(data)
    }
}

/// 周课表翻周：偏移存 App Group 共享偏好，不主动请求刷新。
@MainActor
enum WidgetWeekAction {

    static func shift(by delta: Int) {
        WidgetSnapshotStore.setWeekOffset(WidgetSnapshotStore.weekOffset() + delta)
    }
}
