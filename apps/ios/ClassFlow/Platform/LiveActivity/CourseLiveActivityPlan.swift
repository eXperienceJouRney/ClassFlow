import Foundation

// MARK: - 一次自动评估的结论

/// 在某个时刻评估「自动课程通知」后应该做什么。
///
/// 只做纯计算，不碰 ActivityKit，方便单测覆盖跨天、课程取消与时间修改。
///
/// 规则：
/// - 只给**正在上**的课自动开启活动，不提前显示还没开始的课
///   （活动里的倒计时表示本节课剩余时间，提前显示会误导）。
/// - 当前没课时不启动，但会把唤醒点定在下一节课的开始时刻。
/// - 下一节课可以跨天，间隔多久都没关系；`nextEvaluation` 是绝对时刻。
nonisolated struct CourseLiveActivityPlan: Equatable, Sendable {

    /// 现在应该自动显示实时活动的课；`nil` 表示当前没有在上课。
    let session: ClassSession?
    /// 这节课的下一节，用于活动里的「下一节」。
    let nextSession: ClassSession?
    /// 下一次需要重新评估的时刻：本节课下课，或下一节上课。
    let nextEvaluation: Date?

    static let inactive = CourseLiveActivityPlan(
        session: nil,
        nextSession: nil,
        nextEvaluation: nil
    )

    /// 根据课表与开关状态算出本次评估的结论。
    ///
    /// - Parameters:
    ///   - timetable: 当前学期的课表；没有学期 / 作息未配置时为 nil
    ///   - autoStartEnabled: 用户是否在设置里打开了自动课程通知
    ///   - systemEnabled: 系统是否允许实时活动（设置 › ClassFlow › 实时活动）
    ///   - now: 评估时刻
    static func make(
        timetable: Timetable?,
        autoStartEnabled: Bool,
        systemEnabled: Bool,
        now: Date,
        calendar: Calendar = .current
    ) -> CourseLiveActivityPlan {
        guard autoStartEnabled, systemEnabled, let timetable else { return .inactive }

        if let current = timetable.currentSession(at: now, calendar: calendar) {
            return CourseLiveActivityPlan(
                session: current,
                nextSession: timetable.nextSession(after: current, calendar: calendar),
                nextEvaluation: current.end
            )
        }

        // 还没上课：不提前启动，只把下一次唤醒定在下一节开始。
        guard let next = timetable.nextSession(startingAtOrAfter: now, calendar: calendar) else {
            return .inactive
        }

        return CourseLiveActivityPlan(
            session: nil,
            nextSession: next,
            nextEvaluation: next.start
        )
    }
}
