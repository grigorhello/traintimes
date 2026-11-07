import UserNotifications

/// Notification permission in words (Settings, TT-105): Allowed, Off or Not asked yet.
enum NotificationPermission: CaseIterable, Sendable {
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
}

/// The live permission from `UNUserNotificationCenter`.
struct SystemNotificationPermission: NotificationPermissionProviding {
    func current() async -> NotificationPermission {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return NotificationPermission(settings.authorizationStatus)
    }
}
