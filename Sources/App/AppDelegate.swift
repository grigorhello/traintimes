import UIKit
import UserNotifications

/// Notification taps (TT-144) and the APNs device token (TT-141). It becomes the notification centre's delegate at launch,
/// so a tap that launches a closed app reaches it too, and hands each tap's link to the router, which RootView opens.
/// The token callbacks go to `SystemPushRegistration`, which the alert rules ask for the token. A ride the app was stopped
/// during is restored at launch, also when iOS relaunches the app in the background to continue it (TT-171), and its Live
/// Activity follows it from then on (TT-174). "Detect my train" starts its wake-ups again at launch, which is how a relaunch
/// for a wake-up reaches it, and the background question's answers arrive here (TT-176).
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// The app's one router; created on first use, so the delegate's init stays free of main-actor work.
    lazy var router = AppRouter()
    /// The app's one ride engine (On board, TT-171). Restoring asks for nothing: with no saved ride it does nothing.
    lazy var ride = RideEngine.app()
    /// The ride on the Lock Screen and in the Dynamic Island (TT-174); nil in fixture runs.
    lazy var liveActivity = RideLiveActivity.app(following: ride)
    /// "Detect my train" (TT-176); nil in fixture runs.
    lazy var detection = BackgroundDetection.app(ride: ride)

    func application(
        _ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().setNotificationCategories([DetectionNotice.notificationCategory])
        detection?.resume()
        Task {
            await ride.restore()
            liveActivity?.start()
        }
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
        // The background question (TT-176): Not me runs in the background, so it is kept on device before iOS suspends the
        // app again; Start On board and a tap open the app, which acts on them once it is active.
        if let train = DetectedTrain(userInfo: response.notification.request.content.userInfo) {
            let action = response.actionIdentifier
            if action == DetectionNotice.notMeAction { DetectionStore.recordNotMe(train, in: .standard, at: Date()) }
            completionHandler()
            Task { @MainActor in
                switch action {
                case DetectionNotice.startAction: self.router.open(train, startsRide: true)
                case UNNotificationDefaultActionIdentifier: self.router.open(train, startsRide: false)
                case DetectionNotice.notMeAction: self.detection?.refresh()
                default: break
                }
            }
            return
        }
        let link = NotificationLink(userInfo: response.notification.request.content.userInfo)
        // A tapped notification leaves Notification Center, so the Alerts tab's Recent updates keeps it here (TT-143).
        let update = AlertUpdate(response.notification)
        completionHandler()
        Task { @MainActor in
            if let update { AlertUpdates.record(update, in: .standard) }
            if let link { self.router.open(link) }
        }
    }

    /// A notification arriving while the app is open is not shown (D39), but Recent updates lists it (TT-143).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let update = AlertUpdate(notification)
        completionHandler([])
        guard let update else { return }
        Task { @MainActor in
            AlertUpdates.record(update, in: .standard)
        }
    }
}
