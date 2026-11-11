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
    /// the rider's first "Enable alerts" (TT-142), never before the first timetable.
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
        // Visible notifications with sound; no badges, no critical alerts. Time Sensitive (the ride's arriving
        // notifications, TT-173) needs no option here: it comes with the app's entitlement.
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        return await current()
    }
}

/// A fixed permission: UI tests set it with `TT_NOTIFICATIONS` (allowed, off or notAsked) in fixture runs.
struct FixedNotificationPermission: NotificationPermissionProviding {
    let value: NotificationPermission

    func current() async -> NotificationPermission { value }
}
