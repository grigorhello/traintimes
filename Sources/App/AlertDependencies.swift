import Foundation

/// What the alert rules talk to (TT-141): the alert server at alerts.traintimes.ca, the APNs device token and the
/// notification permission in the app; the fixture server and token in previews and tests, which never reach APNs or the
/// network. UI tests (`TT_FIXTURES`) can fix the permission with `TT_NOTIFICATIONS`, keep rules on device and hold the
/// bell's toast longer with `TT_TOAST_SECONDS`; the unit test host and previews keep rules in memory.
@MainActor
struct AlertDependencies {
    let server: any AlertServer
    let push: any PushRegistering
    let permissions: any NotificationPermissionProviding
    let defaults: UserDefaults?
    /// The notifications Notification Center still shows, for Recent updates (TT-143); none in fixture runs.
    var delivered: any DeliveredNotificationsProviding = FixedDeliveredNotifications()
    /// How long the bell's toast and the Alerts tab's undo toast show (TT-141, TT-143).
    var toastDuration: Duration = .seconds(5)

    static func app(environment: [String: String] = ProcessInfo.processInfo.environment) -> AlertDependencies {
        #if DEBUG
        if ScheduleDependencies.isFixtureRun(environment) {
            var permissions: any NotificationPermissionProviding = SystemNotificationPermission()
            if let fixed = environment["TT_NOTIFICATIONS"].flatMap(NotificationPermission.init(rawValue:)) {
                permissions = FixedNotificationPermission(value: fixed)
            }
            var dependencies = AlertDependencies(
                server: FixtureAlertServer(),
                push: FixturePushRegistration(),
                permissions: permissions,
                defaults: environment["TT_FIXTURES"] != nil ? .standard : nil
            )
            // A slow CI runner can take longer than 5 s to read the toast after a tap.
            if let seconds = environment["TT_TOAST_SECONDS"].flatMap(Int.init) {
                dependencies.toastDuration = .seconds(seconds)
            }
            return dependencies
        }
        #endif
        return AlertDependencies(
            server: HTTPAlertServer(), push: SystemPushRegistration.shared, permissions: SystemNotificationPermission(), defaults: .standard,
            delivered: SystemDeliveredNotifications()
        )
    }

    func rules(settings: AppSettings) -> AlertRules {
        AlertRules(server: server, push: push, permissions: permissions, settings: settings, defaults: defaults)
    }

    func updates(clock: any AppClock) -> AlertUpdates {
        AlertUpdates(source: delivered, clock: clock, defaults: defaults)
    }
}
