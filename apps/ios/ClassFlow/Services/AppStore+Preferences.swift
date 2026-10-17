import Foundation

extension AppStore {

    var preferences: AppPreferences {
        data.preferences
    }

    /// 用给定值整体替换偏好设置并立即持久化。
    func updatePreferences(_ preferences: AppPreferences) throws {
        try commit { $0.preferences = preferences }
    }

    /// 只改其中一项偏好。
    func updatePreferences(_ mutate: (inout AppPreferences) -> Void) throws {
        var next = data.preferences
        mutate(&next)
        try updatePreferences(next)
    }
}
