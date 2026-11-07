import Foundation
@testable import TrainTimes

extension UserDefaults {
    /// A fresh, empty suite, so tests never read or write the app's real settings.
    static func ephemeral() -> UserDefaults {
        let name = "TrainTimesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

/// A fixed notification permission in place of `UNUserNotificationCenter`.
struct FakeNotificationPermission: NotificationPermissionProviding {
    let value: NotificationPermission

    init(_ value: NotificationPermission) {
        self.value = value
    }

    func current() async -> NotificationPermission { value }
}
