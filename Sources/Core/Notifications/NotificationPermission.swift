import UserNotifications

/// Notification permission in words (Settings, TT-105): Allowed, Off or Not asked yet.
/// Raw values are what `TT_NOTIFICATIONS` takes in fixture runs.
enum NotificationPermission: String, CaseIterable, Sendable {
    case allowed
    case off
    case notAsked

    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .authorized, .provisional, .ephemeral: self = .allowed
        case .denied: self = .off
        case .notDetermined: self = .notAsked
        @unknown default: self = .notAsked
        }
    }
}

/// Reads the app's notification permission; tests inject a fixed state.
protocol NotificationPermissionProviding: Sendable {
    func current() async -> NotificationPermission
    /// Shows the iOS permission dialog if the rider has not been asked yet, then returns the answer. Called only after
    /// the rider's own tap (the first bell tap ever, TT-190), never before the first timetable.
    func request() async -> NotificationPermission
}

extension NotificationPermissionProviding {
    /// A source that cannot ask, such as a fixed test value, keeps its state.
    func request() async -> NotificationPermission { await current() }
}

/// The live permission from `UNUserNotificationCenter`.
struct SystemNotificationPermission: NotificationPermissionProviding {
    func current() async -> NotificationPermission {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return NotificationPermission(settings.authorizationStatus)
    }

    func request() async -> NotificationPermission {
        // Visible notifications with the default sound; no badges, no critical or time-sensitive alerts.
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        return await current()
    }
}

/// A fixed permission: UI tests set it with `TT_NOTIFICATIONS` (allowed, off or notAsked) in fixture runs.
struct FixedNotificationPermission: NotificationPermissionProviding {
    let value: NotificationPermission

    func current() async -> NotificationPermission { value }
}

/// Not asked yet, and its dialog answers by itself: UI tests set it with `TT_NOTIFICATIONS=deny` in fixture runs (TT-190).
/// iOS asks only once per install and a UI test cannot reset the answer, so the real dialog is answered "Allow" and the
/// refusal is tested with this one, which leaves the simulator as it was.
actor AnsweringNotificationPermission: NotificationPermissionProviding {
    private var value = NotificationPermission.notAsked
    private let answer: NotificationPermission

    init(answer: NotificationPermission) {
        self.answer = answer
    }

    func current() -> NotificationPermission { value }

    func request() -> NotificationPermission {
        if value == .notAsked { value = answer }
        return value
    }
}
