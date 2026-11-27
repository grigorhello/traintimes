import UIKit
import UserNotifications

/// Notification taps (TT-144) and the APNs device token (TT-141). It becomes the notification centre's delegate at launch,
/// so a tap that launches a closed app reaches it too, and hands each tap's link to the router, which RootView opens.
/// The token callbacks go to `SystemPushRegistration`, which the alert rules ask for the token. A ride the app was stopped
/// during is restored at launch, also when iOS relaunches the app in the background to continue it (TT-171), and its Live
/// Activity follows it from then on (TT-174). "When the app is closed" starts its wake-ups again at launch, which is how a
/// relaunch for a wake-up reaches it (TT-243, D120), and the card's No and Not on it arrive here.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// The app's one router; created on first use, so the delegate's init stays free of main-actor work.
    lazy var router = AppRouter()
    /// The phone's location for rides (TT-171) and the automatic ride's watch (TT-242, D120): one provider, so a ride the
    /// watch starts keeps its location session.
    lazy var location = SystemLocationProvider()
    /// The app's one ride engine (On board, TT-171). Restoring asks for nothing: with no saved ride it does nothing.
    lazy var ride = RideEngine.app(location: location)
    /// The ride's arriving nudge (TT-173): it follows the engine from launch, before a saved ride is restored, also when
    /// iOS relaunches the app in the background, so a moved estimate moves the notifications with no screen showing.
    lazy var nudge = ArrivalNudge.system()
    /// The ride on the Lock Screen and in the Dynamic Island (TT-174); nil in fixture runs.
    lazy var liveActivity = RideLiveActivity.app(following: ride)
    /// The ride that starts by itself on an alerted train (TT-242, D120); nil in fixture runs. It decides with the phone
    /// locked too, so it lives here rather than in `RootView`.
    lazy var autoRide = AutoRideWatch.app(
        ride: ride, location: location, liveActivity: liveActivity, nudge: nudge, wrongTrain: wrongTrainCheck
    )
    /// "When the app is closed" (TT-243, D120): the watch armed from a wake-up or the card's arrival; nil in fixture runs.
    lazy var autoRideWake = AutoRideWake.app(watch: autoRide, ride: ride)
    /// The wrong train warning's presenter (TT-250, D127), made in every run: fixture runs have no card and no notification,
    /// so the warning shows in the app only.
    lazy var wrongTrain = WrongTrain.app(card: liveActivity)
    /// The wrong train check (TT-251, D127): what raises the warning for real trains, with the phone locked too; nil in
    /// fixture runs, previews and the unit test host.
    lazy var wrongTrainCheck = WrongTrainCheck.app(presenter: wrongTrain, ride: ride, location: location)

    func application(
        _ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Anonymous product analytics (TT-208, D92): PostHog in TestFlight and App Store builds with a token, else nothing.
        Analytics.tracker = PostHogAnalytics.start()
        // A route saved before this install sent analytics counts once, so the install shows as activated (TT-217).
        RouteCount().launched(with: UserDefaultsRouteStore().route)
        UNUserNotificationCenter.current().delegate = self
        NotificationCategories.register()
        // No on the departure question's card (TT-231, D110): iOS runs the intent here, which ended the card.
        DeclineDepartureIntent.declined = { [weak self] train in self?.declined(train, surface: .card) }
        // Not on it on the ride's card (TT-243, D120): the same, before or after the launch's restore.
        NotOnTrainIntent.notOnIt = { [weak self] train in self?.notOnIt(train) }
        // "I’m fine" on the wrong train warning's card (TT-250, D127): the intent took the warning off the card.
        WrongTrainFineIntent.fine = { [weak self] train in self?.wrongTrain.fine(for: Ride(train), surface: .card) }
        nudge.follow(ride)
        wrongTrain.follow(ride)
        autoRide?.follow(ride)
        // The wrong train check (TT-251, D127) reads the watch's and the ride's fixes, follows the rides the rider starts,
        // and holds a ride's left-the-line end while it warns or follows another train. A warning with no ride declines
        // its train for the day once answered or run out.
        if let check = wrongTrainCheck {
            let engine = ride
            check.follow(engine)
            engine.fixTap = { [weak check] fix in check?.receive(fix) }
            autoRide?.fixTap = { [weak check] fix in check?.receive(fix) }
            engine.holdsEnding = { [weak check, weak engine] reason in
                reason == .leftTheLine && (check?.holdsLeftTheLine(of: engine?.ride) ?? false)
            }
        }
        wrongTrain.decline = { ride in DetectionStore.silence([ride.tripKey], in: .standard) }
        // The server's card for an alerted train arriving with the app in the background arms the watch (TT-243).
        liveActivity?.departureArrived = { [weak self] ride in
            Task { await self?.autoRideWake?.cardArrived(ride) }
        }
        autoRideWake?.resume()
        Task {
            await ride.restore()
            // A ride ended before it was restored (the Live Activity's End ride) leaves no notifications behind.
            nudge.restoreFinished()
            liveActivity?.start()
            // A watch the app was stopped during picks up its train, or ends (TT-242).
            await autoRide?.restore()
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
        let link = NotificationLink(userInfo: response.notification.request.content.userInfo)
        // The wrong train warning (TT-250, D127): a tap opens the app on the warning, "Trains from …" ends the ride and
        // turns Schedule to the way back, "I’m fine" takes the warning away in the background. Never T's Trip details.
        if response.notification.request.content.categoryIdentifier == WrongTrainNotice.category,
           let wrong = WrongTrainNotice.train(from: response.notification.request.content.userInfo) {
            let action = response.actionIdentifier
            completionHandler()
            Task { @MainActor in
                switch action {
                case WrongTrainNotice.trainsAction:
                    Analytics.track(.notificationOpened(kind: WrongTrainNotice.analyticsKind, action: "trains"))
                    self.wrongTrain.trains(
                        for: wrong.ride, nextStopId: wrong.nextStopId, originId: wrong.originId, surface: .notification
                    )
                case WrongTrainNotice.fineAction:
                    Analytics.track(.notificationOpened(kind: WrongTrainNotice.analyticsKind, action: "fine"))
                    self.wrongTrain.fine(for: wrong.ride, surface: .notification)
                default:
                    Analytics.track(.notificationOpened(kind: WrongTrainNotice.analyticsKind, action: "open"))
                    self.wrongTrain.openWarning()
                }
            }
            return
        }
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
    /// today, the answer is counted, and the alert server sends nothing more for it.
    private func declined(_ train: DeclinedDeparture, surface: DepartureQuestion.Surface) {
        let key = TripKey(serviceDay: ServiceDay(dateKey: train.serviceDate), tripId: train.tripId)
        DepartureQuestion.decline(key, in: .standard, surface: surface)
        liveActivity?.declined(train)
    }

    /// Not on it on the ride's card (`NotOnTrainIntent`, which ended the card; TT-243, D120): the ride ends, also before the
    /// launch's restore (the engine reads the saved ride then), its train is left alone today, and the tap counts toward two
    /// in 14 days. "Your stop is next" goes with the ride (`ArrivalNudge`; `restoreFinished()` before a restore). The demo
    /// ride's is `OnBoard`'s. Nothing is reported to the server: the card was handed off.
    private func notOnIt(_ train: DeclinedDeparture) {
        let shown = Ride(train)
        if shown.tripId == DemoRide.tripId {
            liveActivity?.demoNotOnIt?(shown)
            return
        }
        if let running = ride.ride, running != shown { return }
        guard ride.end(.notOnIt, surface: .card) != nil else { return }
        AutoRideStore(defaults: .standard).recordNotOnIt(at: Date())
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

extension WrongTrain {
    /// The app's presenter: the ride's card, the notification (none in fixture runs), "I’m fine" kept on device, the Time
    /// format the rider chose, and background time for the demo.
    static func app(
        card: (any WrongTrainShowing)?, environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> WrongTrain {
        WrongTrain(
            card: card,
            notifier: ScheduleDependencies.isFixtureRun(environment) ? nil : SystemWrongTrainNotifier(),
            store: WrongTrainStore(defaults: .standard),
            haptics: TTHaptics.shared,
            isActive: { UIApplication.shared.applicationState == .active },
            formatter: {
                let stored = UserDefaults.standard.string(forKey: AppSettings.timeFormatKey).flatMap(TimeFormat.init(rawValue:))
                return TimeFormatter(format: stored ?? .device)
            },
            background: SystemBackgroundTime()
        )
    }
}
