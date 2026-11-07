import Foundation

/// What the alert rules talk to (TT-141): the alert server at alerts.traintimes.ca, the APNs device token and the
/// notification permission in the app; the fixture server and token in previews and tests, which never reach APNs or the
/// network. UI tests (`TT_FIXTURES`) can fix the permission with `TT_NOTIFICATIONS` and keep rules on device; the unit
/// test host and previews keep them in memory.
@MainActor
struct AlertDependencies {
    let server: any AlertServer
    let push: any PushRegistering
    let permissions: any NotificationPermissionProviding
    let defaults: UserDefaults?

    static func app(environment: [String: String] = ProcessInfo.processInfo.environment) -> AlertDependencies {
        #if DEBUG
        if ScheduleDependencies.isFixtureRun(environment) {
            var permissions: any NotificationPermissionProviding = SystemNotificationPermission()
            if let fixed = environment["TT_NOTIFICATIONS"].flatMap(NotificationPermission.init(rawValue:)) {
                permissions = FixedNotificationPermission(value: fixed)
            }
            return AlertDependencies(
                server: FixtureAlertServer(),
                push: FixturePushRegistration(),
                permissions: permissions,
                defaults: environment["TT_FIXTURES"] != nil ? .standard : nil
            )
        }
        #endif
        return AlertDependencies(
            server: HTTPAlertServer(), push: SystemPushRegistration.shared, permissions: SystemNotificationPermission(), defaults: .standard
        )
    }

    func rules(settings: AppSettings) -> AlertRules {
        AlertRules(server: server, push: push, permissions: permissions, settings: settings, defaults: defaults)
    }
}
