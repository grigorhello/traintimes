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

/// A clock a test moves forward by hand, for the Schedule minute tick.
/// `@unchecked Sendable` is safe: `value` is only read and written while holding `lock`.
final class TestClock: AppClock, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(now: Date) {
        value = now
    }

    var now: Date { lock.withLock { value } }

    func advance(minutes: Int) {
        lock.withLock { value = value.addingTimeInterval(TimeInterval(minutes * 60)) }
    }
}
