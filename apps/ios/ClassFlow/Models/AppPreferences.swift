import Foundation

/// 用户偏好设置；`firstWeekday` 只影响展示顺序，周次编号仍以周一为基准。
struct AppPreferences: Codable, Hashable, Sendable {

    var defaultScheduleMode: ScheduleMode
    var firstWeekday: Weekday
    var appearance: AppearancePreference
    var timeFormat: TimeFormatPreference
    /// 周视图的课程块是否显示授课教师。
    var showsTeacherInWeekGrid: Bool

    init(
        defaultScheduleMode: ScheduleMode = .week,
        firstWeekday: Weekday = .monday,
        appearance: AppearancePreference = .system,
        timeFormat: TimeFormatPreference = .twentyFourHour,
        showsTeacherInWeekGrid: Bool = true
    ) {
        self.defaultScheduleMode = defaultScheduleMode
        self.firstWeekday = firstWeekday
        self.appearance = appearance
        self.timeFormat = timeFormat
        self.showsTeacherInWeekGrid = showsTeacherInWeekGrid
    }

    static let `default` = AppPreferences()
}

extension AppPreferences {

    enum CodingKeys: String, CodingKey {
        case defaultScheduleMode
        case firstWeekday
        case appearance
        case timeFormat
        case showsTeacherInWeekGrid
    }

    /// 缺失的偏好项按默认值补齐。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AppPreferences()

        defaultScheduleMode = try container.decodeIfPresent(ScheduleMode.self, forKey: .defaultScheduleMode)
            ?? fallback.defaultScheduleMode
        firstWeekday = try container.decodeIfPresent(Weekday.self, forKey: .firstWeekday)
            ?? fallback.firstWeekday
        appearance = try container.decodeIfPresent(AppearancePreference.self, forKey: .appearance)
            ?? fallback.appearance
        timeFormat = try container.decodeIfPresent(TimeFormatPreference.self, forKey: .timeFormat)
            ?? fallback.timeFormat
        showsTeacherInWeekGrid = try container.decodeIfPresent(Bool.self, forKey: .showsTeacherInWeekGrid)
            ?? fallback.showsTeacherInWeekGrid
    }
}

/// 外观偏好。
enum AppearancePreference: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {

    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }
}

/// 时间格式偏好。
enum TimeFormatPreference: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {

    /// 24 小时制：`08:00`
    case twentyFourHour
    /// 12 小时制：`上午8:00`
    case twelveHour

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .twentyFourHour: "24小时制"
        case .twelveHour: "12小时制"
        }
    }
}

extension TimeOfDay {

    /// 按偏好格式化的时刻文本。
    func displayText(format: TimeFormatPreference) -> String {
        switch format {
        case .twentyFourHour:
            return displayText

        case .twelveHour:
            let marker = hour < 12 ? "上午" : "下午"
            let twelveHour = hour % 12 == 0 ? 12 : hour % 12
            return "\(marker)\(twelveHour):\(String(format: "%02d", minute))"
        }
    }
}

extension TimeRange {

    /// 按偏好格式化的时间段文本。
    func displayText(format: TimeFormatPreference) -> String {
        "\(start.displayText(format: format))-\(end.displayText(format: format))"
    }
}
