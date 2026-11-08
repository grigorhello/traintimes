import UIKit
import UserNotifications

/// Notification taps (TT-144) and the APNs device token (TT-141). It becomes the notification centre's delegate at launch,
/// so a tap that launches a closed app reaches it too, and hands each tap's link to the router, which RootView opens.
/// The token callbacks go to `SystemPushRegistration`, which the alert rules ask for the token.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// The app's one router; created on first use, so the delegate's init stays free of main-actor work.
    lazy var router = AppRouter()

    func application(
        _ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        #if DEBUG
        // UI tests stand in for a tap that launches the app with the server's payload as JSON (D20).
        if let json = ProcessInfo.processInfo.environment["TT_NOTIFICATION"], let link = NotificationLink(json: json) {
            router.open(link)
        }
        #endif
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        SystemPushRegistration.shared.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        SystemPushRegistration.shared.didFail(error)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let link = NotificationLink(userInfo: response.notification.request.content.userInfo)
        completionHandler()
        guard let link else { return }
        Task { @MainActor in
            self.router.open(link)
        }
    }
}
