import Foundation

/// 记录「用户手动收掉过的那一节」，避免自动课程通知马上又把它建回来。
///
/// 只保存最近一节，键里带上安排 id 与上课时刻：
/// - 每周重复的同一门课不会串到别的周；
/// - 下一节课天然不命中，不需要额外清理；
/// - 写进 `UserDefaults`，App 重启后依然尊重用户上一次的「结束」操作。
nonisolated struct CourseLiveActivitySuppression {

    private static let storageKey = "classflow.liveActivity.suppressedSession"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 这一节课是否被用户手动收掉过。
    func isSuppressed(_ session: ClassSession) -> Bool {
        defaults.string(forKey: Self.storageKey) == Self.identity(of: session)
    }

    /// 记住「这一节被用户收掉了」。
    func suppress(_ session: ClassSession) {
        defaults.set(Self.identity(of: session), forKey: Self.storageKey)
    }

    /// 用户重新手动开启活动时忘掉这条记录。
    func clear() {
        defaults.removeObject(forKey: Self.storageKey)
    }

    /// 一节课的稳定标识：同一条安排 + 同一个上课时刻。
    static func identity(of session: ClassSession) -> String {
        "\(session.entry.id.uuidString)@\(Int(session.start.timeIntervalSince1970))"
    }
}
