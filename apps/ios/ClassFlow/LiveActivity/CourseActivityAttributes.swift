import ActivityKit
import Foundation

/// 一节课的 Live Activity 数据契约。
///
/// `ActivityAttributes` 在活动创建时写入，之后不可更改，所以这里只放一节课本身不变的信息：
/// 课程名、起止时间与上课地点。下一节课会随上课进度变化，放在 `ContentState` 里，
/// 由主 App 在活动期间用 `Activity.update(_:)` 更新。
nonisolated struct CourseActivityAttributes: ActivityAttributes {

    /// 下一节课的展示信息。
    nonisolated struct NextCourse: Codable, Hashable, Sendable {
        /// 课程名称
        var name: String
        /// 开始时间
        var startTime: Date
        /// 上课地点
        var location: String

        init(name: String, startTime: Date, location: String) {
            self.name = name
            self.startTime = startTime
            self.location = location
        }
    }

    /// 活动期间会变化的内容。
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        /// 下一节课；当天没有后续课程时为 `nil`。
        var nextCourse: NextCourse?
        /// 这条活动是否由「自动课程通知」创建。
        ///
        /// 关闭自动通知时只收掉自动创建的活动，用户手动开启的保留。
        var isAutomatic: Bool

        init(nextCourse: NextCourse? = nil, isAutomatic: Bool = false) {
            self.nextCourse = nextCourse
            self.isAutomatic = isAutomatic
        }

        enum CodingKeys: String, CodingKey {
            case nextCourse
            case isAutomatic
        }

        /// 旧版本创建的活动没有 `isAutomatic`，缺省按「手动」处理。
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            nextCourse = try container.decodeIfPresent(NextCourse.self, forKey: .nextCourse)
            isAutomatic = try container.decodeIfPresent(Bool.self, forKey: .isAutomatic) ?? false
        }
    }

    /// 课程名称
    var courseName: String
    /// 开始时间
    var startTime: Date
    /// 结束时间
    var endTime: Date
    /// 上课地点
    var location: String
    /// 对应的 `ScheduleEntry.id`。
    ///
    /// 用来在上一条活动 / 每周重复的同一门课之间认准「就是这一节」。
    /// 旧版本创建的活动没有这个字段，解码后为 nil，此时退回课程名与时刻比较。
    var entryId: UUID?

    init(
        courseName: String,
        startTime: Date,
        endTime: Date,
        location: String,
        entryId: UUID? = nil
    ) {
        self.courseName = courseName
        self.startTime = startTime
        self.endTime = endTime
        self.location = location
        self.entryId = entryId
    }
}

nonisolated extension CourseActivityAttributes {

    /// 本节课的时间区间。
    ///
    /// 结束时间不晚于开始时间时退化为一个零长度区间，避免直接构造 `ClosedRange` 时崩溃。
    var timeRange: ClosedRange<Date> {
        startTime...max(startTime, endTime)
    }

    /// 本节课时长（秒）。
    var duration: TimeInterval {
        max(0, endTime.timeIntervalSince(startTime))
    }

    /// 这条活动是否就是给定的这一节课。
    ///
    /// 先比起止时刻，再比安排 id：每周重复的课安排 id 相同，只比 id 会把上周的活动认成今天。
    /// 旧版本的活动没有 `entryId`，退化为课程名比较。
    ///
    /// 这里只接收基础字段，不依赖模型层；课表到活动的映射由主 App 负责。
    func matches(
        entryId: UUID?,
        courseName: String,
        start: Date,
        end: Date
    ) -> Bool {
        guard abs(startTime.timeIntervalSince(start)) < 1,
              abs(endTime.timeIntervalSince(end)) < 1
        else { return false }

        // 旧版本活动没有 entryId：退回课程名比较。
        guard let storedEntryId = self.entryId else {
            return self.courseName == courseName
        }
        return storedEntryId == entryId
    }
}
