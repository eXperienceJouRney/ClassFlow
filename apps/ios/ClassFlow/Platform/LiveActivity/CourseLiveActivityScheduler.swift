import Foundation
import Observation

/// 按课表时间自动开关课程 Live Activity。
///
/// 设计要点：
/// - **不轮询**：只在「下课」和「下一节上课」两个边界各醒一次，界面上的倒计时仍由
///   Live Activity 自己按系统时间绘制。
/// - **不做后台魔法**：iOS 不允许 App 在后台任意启动实时活动。App 被挂起后，这里的
///   `Task` 不会准点执行；回到前台时 `activate()` 会按当前时间重新对账。
/// - **尊重用户**：系统实时活动开关关闭时不请求；用户手动收掉某一节后，本次课内不再自动重建。
@MainActor
@Observable
final class CourseLiveActivityScheduler {

    private let store: AppStore
    private let controller: any CourseLiveActivityControlling

    /// 用户是否打开了「自动显示当前课程」。
    private(set) var isAutoStartEnabled: Bool

    /// 最近一次评估的结果；界面与测试可以据此说明下一次何时检查。
    private(set) var plan: CourseLiveActivityPlan = .inactive

    /// 下一次边界检查；只保留一个，重新评估时整体替换。
    @ObservationIgnored
    private var evaluationTask: Task<Void, Never>?

    /// 同一时刻只跑一轮评估；期间的重复请求合并成一次补跑。
    @ObservationIgnored
    private var isSyncing = false
    @ObservationIgnored
    private var needsAnotherPass = false

    init(store: AppStore, controller: any CourseLiveActivityControlling) {
        self.store = store
        self.controller = controller
        self.isAutoStartEnabled = store.preferences.autoStartLiveActivity
    }

    // MARK: - 入口

    /// App 启动 / 回到前台：重新读取设置，并按当前时间对账。
    func activate(now: Date = Date()) async {
        isAutoStartEnabled = store.preferences.autoStartLiveActivity
        await sync(now: now)
    }

    /// App 进入后台：取消边界定时器。
    ///
    /// iOS 不允许在后台随意启动实时活动，定时器醒来也无法成功请求；回到前台时
    /// `activate()` 会按当前时间重新对账，因此这里停掉比让它白跑更干净。
    func suspend() {
        evaluationTask?.cancel()
        evaluationTask = nil
    }

    /// 数据或设置变化后重新评估（课程时间修改、课程取消、切换学期等）。
    func sync(now: Date = Date()) async {
        guard !isSyncing else {
            needsAnotherPass = true
            return
        }

        isSyncing = true
        var moment = now
        repeat {
            needsAnotherPass = false
            // 设置可能在等待期间被改掉，每轮都重新读取。
            isAutoStartEnabled = store.preferences.autoStartLiveActivity
            await performSync(now: moment)
            moment = Date()
        } while needsAnotherPass

        isSyncing = false
    }

    // MARK: - 评估

    private func performSync(now: Date) async {
        evaluationTask?.cancel()
        evaluationTask = nil

        guard isAutoStartEnabled else {
            plan = .inactive
            // 关掉自动通知时只收掉自动创建的活动；用户手动开的保留。
            await controller.endAutomaticActivities()

            // 但「回前台清理过期活动」仍然要做：手动开启的活动如果在后台期间下课了，
            // 也要在这里收掉。`reconcile` 只会结束不属于当前课程的活动，不会新建。
            let current = store.currentClassSession(at: now)
            let next = current.flatMap { store.nextClassSession(after: $0) }
            await controller.reconcile(currentSession: current, nextSession: next, now: now)
            return
        }

        let systemEnabled = controller.areActivitiesEnabled
        let plan = CourseLiveActivityPlan.make(
            timetable: store.currentTimetable(),
            autoStartEnabled: isAutoStartEnabled,
            systemEnabled: systemEnabled,
            now: now
        )
        self.plan = plan

        guard systemEnabled else {
            // 系统关掉了实时活动：系统已移除活动，这里只清理本地状态，不再请求。
            await controller.reconcile(currentSession: nil, nextSession: nil, now: now)
            return
        }

        if let session = plan.session {
            if controller.isAutoStartSuppressed(session) {
                // 用户手动收掉过这一节：本次课内不再自动重建。
            } else {
                await controller.startAutomatically(
                    session: session,
                    nextSession: plan.nextSession,
                    now: now
                )
            }
        } else {
            // 当前没课：收掉不属于此刻的活动（已下课 / 课程被取消 / 时间被改掉）。
            await controller.reconcile(currentSession: nil, nextSession: plan.nextSession, now: now)
        }

        scheduleEvaluation(at: plan.nextEvaluation)
    }

    /// 在下一次边界醒来；一次性的 `Task`，不按秒刷新 ActivityKit。
    private func scheduleEvaluation(at date: Date?) {
        evaluationTask?.cancel()
        evaluationTask = nil

        guard let date else { return }

        let delay = date.timeIntervalSinceNow
        guard delay > 0 else { return }

        evaluationTask = Task { [weak self] in
            // 多等半秒，避免刚好在边界前一瞬醒来时还算在上一节。
            try? await Task.sleep(for: .seconds(delay + 0.5))
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }
}
