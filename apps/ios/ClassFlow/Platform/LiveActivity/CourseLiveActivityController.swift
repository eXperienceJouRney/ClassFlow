import ActivityKit
import Foundation
import Observation

// MARK: - 调度器依赖的接口

/// `CourseLiveActivityScheduler` 需要控制器做的事。
///
/// 单独抽出协议只是为了让调度器的规则可以在不接触 ActivityKit 的情况下单测；
/// 主 App 里始终使用 `CourseLiveActivityController`。
@MainActor
protocol CourseLiveActivityControlling: AnyObject {

    /// 系统是否允许实时活动（设置 › ClassFlow › 实时活动）。
    var areActivitiesEnabled: Bool { get }

    /// 这一节是否被用户手动收掉过；是的话自动通知不要再建回来。
    func isAutoStartSuppressed(_ session: ClassSession) -> Bool

    /// 为正在上的这一节自动开启活动；返回是否已经处于显示状态。
    @discardableResult
    func startAutomatically(
        session: ClassSession,
        nextSession: ClassSession?,
        now: Date
    ) async -> Bool

    /// 把活动与「当前课」对齐；`currentSession` 为 nil 时收掉不属于此刻的活动。
    func reconcile(
        currentSession: ClassSession?,
        nextSession: ClassSession?,
        now: Date
    ) async

    /// 只收掉自动创建的活动，保留用户手动开启的。
    func endAutomaticActivities() async
}

/// 课程 Live Activity 的启动、更新与收尾。
///
/// 这里**不按秒刷新 ActivityKit**：剩余时间、进度条全部交给 SwiftUI 的
/// `Text(timerInterval:)` / `ProgressView(timerInterval:)` 按系统时间自绘。
/// 主 App 只在课程开始时请求一次活动，在课程结束、用户手动结束或系统回收时把它收掉。
@MainActor
@Observable
final class CourseLiveActivityController {

    /// 当前正在显示的课程；系统里没有本 App 的活动时为 nil。
    private(set) var activeSession: ClassSession?
    /// 最近一次启动失败的原因；界面读取后提示一次即可。
    private(set) var lastErrorMessage: String?

    /// 系统是否允许实时活动（设置 › ClassFlow › 实时活动）。
    /// 用户关掉开关后系统会自行移除活动，这里也跟着回到「未启动」。
    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// 用户手动收掉过的课；自动通知据此不再重建。
    private let suppression: CourseLiveActivitySuppression

    /// 到下课时刻自动结束活动的任务。
    @ObservationIgnored
    private var endTask: Task<Void, Never>?
    /// 监听系统侧活动状态（用户划掉、系统置为过期）的任务。
    @ObservationIgnored
    private var stateObservationTask: Task<Void, Never>?

    init(suppression: CourseLiveActivitySuppression = CourseLiveActivitySuppression()) {
        self.suppression = suppression
    }

    // MARK: - 启动 / 结束

    /// 为正在上的这一节课启动实时活动（用户手动触发）。
    ///
    /// 同一节课已经有活动时只更新内容，不重复创建；其他课程的旧活动会先被结束，
    /// 保证系统里同一时刻只有一条课程活动。
    /// - Parameters:
    ///   - session: 当前正在上的课
    ///   - nextSession: 下一节课；没有后续课程时传 nil
    func start(
        session: ClassSession,
        nextSession: ClassSession?,
        now: Date = Date()
    ) async {
        // 用户重新手动开启：忘掉上一次「结束」，以后可以继续自动。
        suppression.clear()
        _ = await upsert(
            session: session,
            nextSession: nextSession,
            automatic: false,
            reportsErrors: true,
            now: now
        )
    }

    /// 自动课程通知的启动入口：失败时静默（不弹窗打扰用户），并标记活动来源。
    @discardableResult
    func startAutomatically(
        session: ClassSession,
        nextSession: ClassSession?,
        now: Date = Date()
    ) async -> Bool {
        // 用户刚把这一节收掉：本次课内不要再建回来。
        guard !suppression.isSuppressed(session) else { return false }

        return await upsert(
            session: session,
            nextSession: nextSession,
            automatic: true,
            reportsErrors: false,
            now: now
        )
    }

    /// 手动结束本 App 的全部课程活动，并记住这一节，避免自动通知立刻重建。
    func stop() async {
        if let activeSession {
            suppression.suppress(activeSession)
        }
        await finish()
    }

    /// 关闭「自动课程通知」时调用：只收掉自动创建的活动。
    ///
    /// 用户手动开启的活动保留，其下课自动收尾逻辑也不受影响。
    func endAutomaticActivities() async {
        var endedCurrent = false

        for activity in Activity<CourseActivityAttributes>.activities
        where activity.content.state.isAutomatic {
            if let activeSession, activity.attributes.matches(activeSession) {
                endedCurrent = true
            }
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        if endedCurrent {
            handleActivityRemoved()
        }
    }

    /// 这一节是否被用户手动收掉过。
    func isAutoStartSuppressed(_ session: ClassSession) -> Bool {
        suppression.isSuppressed(session)
    }

    // MARK: - 对账

    /// 把系统里的活动与当前课表对齐：
    /// - 正在上的课有活动 → 继续沿用（顺带更新下一节信息）；
    /// - 已经下课 / 课程被取消或改掉 → 结束旧活动；
    /// - 系统里没有活动 → 什么都不启动（启动始终由调用方决定）。
    ///
    /// 自动通知与前台恢复都会调用它，用来收掉后台期间到点的活动。
    func reconcile(
        currentSession: ClassSession?,
        nextSession: ClassSession?,
        now: Date = Date()
    ) async {
        guard areActivitiesEnabled else {
            await finish()
            return
        }

        let ongoing = currentSession.flatMap { $0.isOngoing(at: now) ? $0 : nil }

        // 先结束所有不属于「当前正在上的课」的活动（含已下课的、上周同一安排的）。
        await endActivities(except: ongoing)

        guard let ongoing,
              let activity = activeActivity(matching: ongoing)
        else {
            endTask?.cancel()
            endTask = nil
            stateObservationTask?.cancel()
            stateObservationTask = nil
            activeSession = nil
            return
        }

        let state = makeContentState(
            nextSession: nextSession,
            automatic: activity.content.state.isAutomatic
        )
        if activity.content.state != state {
            await activity.update(ActivityContent(state: state, staleDate: ongoing.end))
        }
        adopt(activity, session: ongoing)
    }

    // MARK: - 活动生命周期

    /// 手动 / 自动启动共用的入口。
    private func upsert(
        session: ClassSession,
        nextSession: ClassSession?,
        automatic: Bool,
        reportsErrors: Bool,
        now: Date
    ) async -> Bool {
        if reportsErrors {
            lastErrorMessage = nil
        }

        guard areActivitiesEnabled else {
            if reportsErrors {
                lastErrorMessage = "系统里的实时活动开关是关的，请到 设置 › ClassFlow 打开「实时活动」。"
            }
            return false
        }
        guard session.isOngoing(at: now) else {
            if reportsErrors {
                lastErrorMessage = "当前没有正在上的课，只能为正在上的课启动实时活动。"
            }
            return false
        }

        // 先清掉别的课（以及往周同一安排）留下的活动。
        await endActivities(except: session)

        let state = makeContentState(nextSession: nextSession, automatic: automatic)
        let content = ActivityContent(state: state, staleDate: session.end)

        if let existing = activeActivity(matching: session) {
            if existing.content.state != state {
                await existing.update(content)
            }
            adopt(existing, session: session)
            return true
        }

        do {
            let activity = try Activity.request(
                attributes: CourseActivityAttributes(session: session),
                content: content,
                pushType: nil
            )
            adopt(activity, session: session)
            return true
        } catch {
            if reportsErrors {
                lastErrorMessage = "启动实时活动失败：\(error.localizedDescription)"
            }
            return false
        }
    }

    private func makeContentState(
        nextSession: ClassSession?,
        automatic: Bool
    ) -> CourseActivityAttributes.ContentState {
        CourseActivityAttributes.ContentState(
            nextCourse: nextSession.map(CourseActivityAttributes.NextCourse.init(session:)),
            isAutomatic: automatic
        )
    }

    /// 系统里仍然有效、且属于这一节课的活动。
    private func activeActivity(
        matching session: ClassSession
    ) -> Activity<CourseActivityAttributes>? {
        Activity<CourseActivityAttributes>.activities.first {
            $0.activityState == .active && $0.attributes.matches(session)
        }
    }

    /// 结束除 `kept` 之外的全部课程活动。
    private func endActivities(except kept: ClassSession?) async {
        for activity in Activity<CourseActivityAttributes>.activities {
            if let kept, activity.attributes.matches(kept) { continue }
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func adopt(
        _ activity: Activity<CourseActivityAttributes>,
        session: ClassSession
    ) {
        activeSession = session
        scheduleEnd(for: session)
        observeState(of: activity)
    }

    /// 到下课时刻结束活动。App 在后台被挂起时这个任务可能不会准时执行，
    /// 由 `staleDate` + 前台 `reconcile` 兜底。
    private func scheduleEnd(for session: ClassSession) {
        endTask?.cancel()
        endTask = nil

        let remaining = session.end.timeIntervalSinceNow
        guard remaining > 0 else {
            Task { [weak self] in
                await self?.finish()
            }
            return
        }

        endTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            await self?.finish()
        }
    }

    /// 收掉全部活动并清空本地状态。
    private func finish() async {
        endTask?.cancel()
        endTask = nil
        stateObservationTask?.cancel()
        stateObservationTask = nil

        await endActivities(except: nil)
        activeSession = nil
    }

    /// 监听系统侧状态：用户划掉活动、系统把活动标成过期时同步本地状态。
    private func observeState(of activity: Activity<CourseActivityAttributes>) {
        stateObservationTask?.cancel()

        stateObservationTask = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                guard let self else { return }

                switch state {
                case .stale:
                    // 已过 `staleDate`（下课时刻）：立刻收掉，别留在锁屏上。
                    await activity.end(nil, dismissalPolicy: .immediate)
                    self.handleActivityRemoved()
                    return

                case .dismissed:
                    // 用户自己划掉了：本次课内不要自动重建。
                    self.suppressActiveSession()
                    self.handleActivityRemoved()
                    return

                case .ended:
                    self.handleActivityRemoved()
                    return

                default:
                    continue
                }
            }
        }
    }

    private func suppressActiveSession() {
        guard let activeSession else { return }
        suppression.suppress(activeSession)
    }

    private func handleActivityRemoved() {
        endTask?.cancel()
        endTask = nil
        activeSession = nil
    }
}

// MARK: - 调度器依赖的接口

extension CourseLiveActivityController: CourseLiveActivityControlling {}

// MARK: - 课表 → 活动数据

extension CourseActivityAttributes {

    /// 从课表里的一节真实课程构造；课程名、时刻与地点都来自课表。
    init(session: ClassSession) {
        self.init(
            courseName: session.courseName,
            startTime: session.start,
            endTime: session.end,
            location: session.location ?? "",
            entryId: session.entry.id
        )
    }

    /// 这条活动是否就是课表里的这一节课。
    func matches(_ session: ClassSession) -> Bool {
        matches(
            entryId: session.entry.id,
            courseName: session.courseName,
            start: session.start,
            end: session.end
        )
    }
}

extension CourseActivityAttributes.NextCourse {

    /// 从课表里的下一节课取值；地点缺失时用空串，界面按「没有地点」处理。
    init(session: ClassSession) {
        self.init(
            name: session.courseName,
            startTime: session.start,
            location: session.location ?? ""
        )
    }
}
