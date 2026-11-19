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
    /// The ride's arriving nudge (TT-173): it follows the engine from launch, before a saved ride is restored, also when
    /// iOS relaunches the app in the background, so a moved estimate moves the notifications with no screen showing.
    lazy var nudge = ArrivalNudge.system()
    /// The ride on the Lock Screen and in the Dynamic Island (TT-174); nil in fixture runs.
    lazy var liveActivity = RideLiveActivity.app(following: ride)
    /// "Detect my train" (TT-176); nil in fixture runs.
    lazy var detection = BackgroundDetection.app(ride: ride)

    func application(
        _ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Anonymous product analytics (TT-208, D92): PostHog in TestFlight and App Store builds with a token, else nothing.
        Analytics.tracker = PostHogAnalytics.start()
        // A route saved before this install sent analytics counts once, so the install shows as activated (TT-217).
        RouteCount().launched(with: UserDefaultsRouteStore().route)
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().setNotificationCategories([
            DetectionNotice.notificationCategory, DepartureNotice.notificationCategory,
        ])
        // No on the departure question's card (TT-231, D110): iOS runs the intent here, which ended the card.
        DeclineDepartureIntent.declined = { [weak self] train in self?.declined(train, surface: .card) }
        nudge.follow(ride)
        detection?.follow(ride)
        detection?.resume()
        Task {
            await ride.restore()
            // A ride ended before it was restored (the Live Activity's End ride) leaves no notifications behind.
            nudge.restoreFinished()
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
                let name = switch action {
                case DetectionNotice.startAction: "start"
                case DetectionNotice.notMeAction: "not_me"
                default: "open"
                }
                Analytics.track(.notificationOpened(kind: "detection", action: name))
                switch action {
                case DetectionNotice.startAction: self.router.open(train, startsRide: true)
                case UNNotificationDefaultActionIdentifier: self.router.open(train, startsRide: false)
                case DetectionNotice.notMeAction:
                    // Tap, felt only with the app open (TT-215, D100).
                    TTHaptics.shared.play(.undo)
                    self.detection?.refresh()
                default: break
                }
            }
            return
        }
        let link = NotificationLink(userInfo: response.notification.request.content.userInfo)
        // The departure question (TT-231): Yes opens the app and starts the ride, No declines the train in the background,
        // a tap opens its Trip details.
        if response.notification.request.content.categoryIdentifier == DepartureNotice.category,
           case .trip(let key, let from, let to) = link {
            let action = response.actionIdentifier
            completionHandler()
            Task { @MainActor in
                switch action {
                case DepartureNotice.yesAction:
                    Analytics.track(.notificationOpened(kind: DepartureNotice.kind, action: "yes"))
                    Analytics.track(.departureQuestionAnswered(yes: true, surface: .notification))
                    if let link { self.router.open(link, boards: true) }
                case DepartureNotice.noAction:
                    Analytics.track(.notificationOpened(kind: DepartureNotice.kind, action: "no"))
                    let train = DeclinedDeparture(
                        tripId: key.tripId, serviceDate: key.serviceDay.dateKey, originId: from ?? "", destinationId: to ?? ""
                    )
                    self.declined(train, surface: .notification)
                default:
                    Analytics.track(.notificationOpened(kind: DepartureNotice.kind, action: "open"))
                    if let link { self.router.open(link) }
                }
            }
            return
        }
        // A tapped notification leaves Notification Center, so the Alerts tab's Recent updates keeps it here (TT-143).
        let update = AlertUpdate(response.notification)
        completionHandler()
        Task { @MainActor in
            if let update { AlertUpdates.record(update, in: .standard) }
            Analytics.track(.notificationOpened(kind: link == nil ? "other" : "alert"))
            if let link { self.router.open(link) }
        }
    }

    /// No on the departure question, on the card or its notification (TT-231, D110): the train is not asked about again
    /// today (nor by train detection), the answer is counted, and the alert server sends nothing more for it.
    private func declined(_ train: DeclinedDeparture, surface: DepartureQuestion.Surface) {
        let key = TripKey(serviceDay: ServiceDay(dateKey: train.serviceDate), tripId: train.tripId)
        DepartureQuestion.decline(key, in: .standard, surface: surface)
        liveActivity?.declined(train)
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
