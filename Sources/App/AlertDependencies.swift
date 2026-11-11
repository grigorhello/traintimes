import Foundation

/// What the alert rules talk to (TT-141): the alert server at alerts.traintimes.ca, the APNs device token and the
/// notification permission in the app; the fixture server and token in previews and tests, which never reach APNs or the
/// network. UI tests (`TT_FIXTURES`) can fix the permission with `TT_NOTIFICATIONS` (or answer the first ask with `deny`),
/// keep rules on device and hold the bell's capsule longer with `TT_TOAST_SECONDS`; the unit test host and previews keep
/// rules in memory.
@MainActor
struct AlertDependencies {
    let server: any AlertServer
    let push: any PushRegistering
    let permissions: any NotificationPermissionProviding
    let defaults: UserDefaults?
    /// The notifications Notification Center still shows, for Recent updates (TT-143); none in fixture runs.
    var delivered: any DeliveredNotificationsProviding = FixedDeliveredNotifications()
    /// How long the Alerts tab's undo toast and Schedule's "Tap the bell on a train" show (TT-143).
    var toastDuration: Duration = .seconds(5)
    /// How long the bell's glass capsule shows (TT-191): 5 s with an action (Repeat, Undo, Try again), 2.5 s without.
    var capsuleActionDuration: Duration = .seconds(5)
    var capsulePlainDuration: Duration = .milliseconds(2500)

    static func app(environment: [String: String] = ProcessInfo.processInfo.environment) -> AlertDependencies {
        #if DEBUG
        if ScheduleDependencies.isFixtureRun(environment) {
            var permissions: any NotificationPermissionProviding = SystemNotificationPermission()
            if let fixed = environment["TT_NOTIFICATIONS"].flatMap(NotificationPermission.init(rawValue:)) {
                permissions = FixedNotificationPermission(value: fixed)
            } else if environment["TT_NOTIFICATIONS"] == "deny" {
                // Not asked, and the first bell tap's dialog answers Don't Allow (TT-190).
                permissions = AnsweringNotificationPermission(answer: .off)
            }
            var dependencies = AlertDependencies(
                server: FixtureAlertServer(),
                push: FixturePushRegistration(),
                permissions: permissions,
                defaults: environment["TT_FIXTURES"] != nil ? .standard : nil
            )
            // A slow CI runner can take longer than 2.5 s to read the capsule after a tap.
            if let seconds = environment["TT_TOAST_SECONDS"].flatMap(Int.init) {
                dependencies.toastDuration = .seconds(seconds)
                dependencies.capsuleActionDuration = .seconds(seconds)
                dependencies.capsulePlainDuration = .seconds(seconds)
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
