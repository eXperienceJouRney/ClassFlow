import Foundation

/// 上课周次的快速选择算法：返回值可直接作为编辑器的勾选状态写回。
enum WeekSelection {

    /// `a-b 周`：闭区间内的每一周。端点写反了会自动换回来，小于 1 的周次会被丢掉。
    static func range(_ first: Int, _ second: Int) -> Set<Int> {
        let lower = min(first, second)
        let upper = max(first, second)
        guard upper >= 1 else { return [] }
        return Set(max(lower, 1)...upper)
    }

    /// `单周`：`a-b 周` 里的奇数周。
    static func oddWeeks(from first: Int, to second: Int) -> Set<Int> {
        range(first, second).filter { !$0.isMultiple(of: 2) }
    }

    /// `双周`：`a-b 周` 里的偶数周。
    static func evenWeeks(from first: Int, to second: Int) -> Set<Int> {
        range(first, second).filter { $0.isMultiple(of: 2) }
    }

    /// `全部`：整个学期的每一周。
    static func all(weekCount: Int) -> Set<Int> {
        range(1, max(weekCount, 1))
    }
}
