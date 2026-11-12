import SwiftUI

/// Three icon-only tabs, Schedule, Alerts and Settings (D48, D49), and nothing else at the top level. Tapping the Schedule
/// tab while it shows scrolls the timeline back to Now (D49). Launch lands on Schedule with no
/// prompt: the remembered route, or the route form on first use (TT-120). Recent routes are shared by Schedule, which
/// records them and lists them in its station picker (D48, D54). Puts the one time formatter in the
/// environment (TT-105); the app follows the iOS appearance (D84). Opens the trip or the Alerts tab for a tapped notification (TT-144).
struct RootView: View {
    @State private var router: AppRouter
    @State private var schedule: ScheduleViewModel
    @State private var settings: AppSettings
    @State private var settingsModel: SettingsViewModel
    /// The first-use form; after the first route, Schedule makes its own picker each time a station is tapped (D54).
    @State private var routeForm: RouteFormViewModel
    /// The trip the details sheet shows, set each time a card is tapped (TT-118).
    @State private var tripDetails: TripDetailsViewModel?
    /// The alert rules (TT-141), shared by the bells, Trip details, the Alerts tab and the watched-trip strip.
    @State private var alerts: AlertRules
    @State private var bells: AlertBellModel
    /// The Alerts tab (TT-143): the rules, recent updates and the saved route's line notices.
    @State private var alertsModel: AlertsViewModel
    /// On board (TT-172): the app's ride engine, or the demo ride's; shared by Trip details and the ride strip.
    @State private var onBoard: OnBoard
    /// The ride's Live Activity was tapped before the ride was restored at launch: its Trip details opens once it is.
    @State private var opensRide = false
    private let liveActivity: RideLiveActivity?
    /// "Detect my train" (TT-176): the offer after the first completed ride and the Settings switch; nil in fixture runs.
    private let backgroundDetection: BackgroundDetection?
    private let stations: any StationRepository
    private let repository: any ScheduleRepository
    private let clock: any AppClock
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    init(
        router: AppRouter = AppRouter(),
        schedule: ScheduleViewModel? = nil,
        settings: AppSettings = AppSettings(),
        dependencies: ScheduleDependencies = .app(),
        routeStore: any RouteStoring = UserDefaultsRouteStore(),
        recents: RecentRoutes = RecentRoutes(),
        dismissedNotices: DismissedNotices = DismissedNotices(),
        alertDependencies: AlertDependencies = .app(),
        bells: AlertBellModel? = nil,
        alertUpdates: AlertUpdates? = nil,
        alertsModel: AlertsViewModel? = nil,
        ride: RideEngine? = nil,
        nudge: ArrivalNudge? = nil,
        liveActivity: RideLiveActivity? = nil,
        detection: BackgroundDetection? = nil
    ) {
        let bells = bells ?? AlertBellModel(
            rules: alertDependencies.rules(settings: settings), actionDuration: alertDependencies.capsuleActionDuration,
            plainDuration: alertDependencies.capsulePlainDuration
        )
        let schedule = schedule ?? ScheduleViewModel(
            route: routeStore.route, repository: dependencies.repository, clock: dependencies.clock, routeStore: routeStore,
            recents: recents, dismissedNotices: dismissedNotices, watchedTrips: bells.rules
        )
        _router = State(initialValue: router)
        _schedule = State(initialValue: schedule)
        _settings = State(initialValue: settings)
        // The alert rules' permission source, so a fixture run's `TT_NOTIFICATIONS` shows in Settings too (TT-142).
        // Its alert rules give the Notifications page the "My alerts" count and the permission prompt (TT-168).
        _settingsModel = State(
            initialValue: SettingsViewModel(
                settings: settings, permissions: alertDependencies.permissions, clock: dependencies.clock, alerts: bells.rules,
                detection: detection
            )
        )
        _routeForm = State(
            initialValue: RouteFormViewModel(route: nil, repository: dependencies.stations, recents: schedule.recents)
        )
        _alerts = State(initialValue: bells.rules)
        _bells = State(initialValue: bells)
        _alertsModel = State(
            initialValue: alertsModel ?? AlertsViewModel(
                rules: bells.rules,
                updates: alertUpdates ?? alertDependencies.updates(clock: dependencies.clock),
                nextTrains: schedule,
                clock: dependencies.clock,
                actionDuration: alertDependencies.capsuleActionDuration,
                plainDuration: alertDependencies.capsulePlainDuration
            )
        )
        // The arriving nudge (TT-173): the app engine's from `AppDelegate`, the demo ride's on its 6x clock; a started ride
        // asks for notifications through the alert rules, as the first bell tap does (D66).
        let rules = bells.rules
        _onBoard = State(
            initialValue: OnBoard(
                app: ride, detector: TrainDetector.app(dependencies), liveActivity: liveActivity,
                nudge: nudge, makeDemoNudge: { ArrivalNudge.demo() },
                requestNotifications: { await rules.requestPermission() }
            )
        )
        self.liveActivity = liveActivity
        backgroundDetection = detection
        stations = dependencies.stations
        repository = dependencies.repository
        clock = dependencies.clock
        TabBarStyle.apply()
    }

    var body: some View {
        detectsTrains(tabs)
    }

    private var tabs: some View {
        TabView(selection: tabSelection) {
            NavigationStack {
                if schedule.route == nil {
                    RouteFormView(viewModel: routeForm, onShowTrains: { show($0) })
                } else {
                    ScheduleView(
                        viewModel: schedule,
                        stations: stations,
                        onOpenTrip: { openTrip($0) },
                        onOpenLineNotice: { router.present(.lineNotices) },
                        bells: bells,
                        onBoard: onBoard,
                        onOpenRide: { Task { await openRide() } },
                        onOpenDeparture: { openDeparture($0) }
                    )
                }
            }
            .tabItem {
                TabBarStyle.icon(
                    "tram.fill", label: String(localized: "tab.schedule"), isSelected: router.selectedTab == .schedule,
                    colorScheme: colorScheme
                )
                .accessibilityLabel(Text("tab.schedule"))
            }
            .tag(AppTab.schedule)

            AlertsView(
                viewModel: alertsModel,
                bells: bells,
                onSeeTrains: { router.showSchedule() },
                onPickNewTrain: { pickNewTrain(replacing: $0) },
                onOpenUpdate: { link in Task { await open(link) } }
            )
            .tabItem {
                let isSelected = router.selectedTab == .alerts
                TabBarStyle.icon(
                    "bell.fill", label: String(localized: "tab.alerts"), isSelected: isSelected,
                    dot: alertsModel.tabDot(isSelected: isSelected, hasNewUpdate: router.showsAlertsDot), colorScheme: colorScheme
                )
                .accessibilityLabel(Text("tab.alerts"))
            }
            .tag(AppTab.alerts)

            SettingsView(viewModel: settingsModel, onShowAlerts: { router.showAlerts() })
                .tabItem {
                    TabBarStyle.icon(
                        "gearshape.fill", label: String(localized: "tab.settings"), isSelected: router.selectedTab == .settings,
                        colorScheme: colorScheme
                    )
                    .accessibilityLabel(Text("tab.settings"))
                }
                .tag(AppTab.settings)
        }
        .sheet(item: $router.presentedSheet) { sheet in
            switch sheet {
            case .tripDetails:
                if let tripDetails {
                    // A new trip while the sheet is up (a notification tap) gets a fresh view, so it loads (TT-144).
                    TripDetailsView(viewModel: tripDetails)
                        .id(ObjectIdentifier(tripDetails))
                }
            case .lineNotices:
                LineNoticeSheet(viewModel: schedule)
            case .detectOffer:
                DetectOfferSheet(onTurnOn: { Task { await turnOnDetection() } }, onNotNow: { router.dismissSheet() })
            }
        }
        // A tapped notification, also one that launched the app before this view appeared (TT-144).
        .onChange(of: router.pendingLink, initial: true) { _, link in
            guard let link else { return }
            router.pendingLink = nil
            Task { await open(link) }
        }
        // The first route saved on device, with a light haptic (TT-120).
        .sensoryFeedback(.impact(weight: .light), trigger: schedule.route) { old, new in old == nil && new != nil }
        .environment(\.timeFormatter, settings.timeFormatter)
        // Demo trains (D49): the timeline shows the new scenario at once.
        .onChange(of: settings.demoTrains) { Task { await schedule.refresh() } }
        // Demo trains › Ride (TT-172) and › Departure (TT-177), while chosen, in TestFlight and Debug builds only: the demo
        // ride asks its question first (TT-175) and plays from the Yes; the demo departure plays from 5:01 PM. Leaving
        // Departure also stops the ride it handed over to.
        .task(id: demoTrains) {
            onBoard.setDemoDeparture(demoTrains == .departure)
            await onBoard.setDemo(demoTrains == .ride)
        }
        // Train detection (TT-175) watches only while Schedule (or Trip details over it) is open in the foreground.
        .task(id: detection) {
            guard let route = detection.route else { return }
            await onBoard.detect(on: route, demo: detection.demo)
        }
        // Mock time (TT-158): the timeline starts again at the new present, as a relaunch would.
        .onChange(of: settings.mockTime) { Task { await schedule.restart() } }
        // Notifications may have been allowed or turned off in Settings while the app was away (TT-141), a rule may need
        // review and notifications may have arrived (TT-143). Back from the toast's Turn on with notifications on, the
        // bell that was tapped turns on (TT-190).
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            // A ride restored in the background gets its Live Activity now, with the app in front (TT-174).
            liveActivity?.sceneDidBecomeActive()
            // Schedule's detection takes over from a background check, and a Not me tapped meanwhile counts (TT-176).
            backgroundDetection?.appDidBecomeActive()
            backgroundDetection?.refresh()
            await refreshAlerts()
            await bells.cameBack()
        }
        // Before departure the Live Activity follows the alerted train, and the alert rules take its tokens to the alert
        // server (TT-178).
        .task {
            liveActivity?.connect(reporter: alerts) { departureForActivity() }
        }
        // The ride's Live Activity (TT-174): a tap opens Trip details on the ride, the expanded island's button ends it.
        // Before departure (TT-178) a tap opens the train's Trip details and "I’m on board" starts the ride there.
        .onOpenURL { url in
            switch RideActivityLink(url) {
            case .departure:
                Task { await openDepartureFromActivity(boards: false) }
            case .board:
                Task { await openDepartureFromActivity(boards: true) }
            case .open:
                opensRide = true
                Task {
                    await openRideFromActivity()
                    // A tap on an activity whose ride is not coming back opens nothing later on.
                    try? await Task.sleep(for: .seconds(15))
                    opensRide = false
                }
            case .end:
                // Like End ride on the sheet: the ride ends, and its Trip details closes if it is open.
                let ride = onBoard.activeRide
                onBoard.end()
                if router.presentedSheet == .tripDetails, let ride, tripDetails?.key == ride.tripKey {
                    router.dismissSheet()
                }
            case nil:
                break
            }
        }
        .onChange(of: onBoard.activeRide) {
            guard opensRide, onBoard.activeRide != nil else { return }
            Task { await openRideFromActivity() }
        }
        // Opening the Alerts tab turns its dot off, and leaving it keeps it off for what the rider saw there (TT-143).
        .onChange(of: router.selectedTab) { old, tab in
            if old == .alerts {
                alertsModel.markReviewsSeen()
                alertsModel.leftTab()
            }
            guard tab == .alerts else { return }
            router.showsAlertsDot = false
            alertsModel.markReviewsSeen()
            Task { await refreshAlerts() }
        }
    }

    /// "Detect my train" (TT-176), apart from `tabs` so each chain type-checks in reasonable time. The first ride that
    /// reaches its stop makes the offer due; it shows over Schedule once nothing else is up, after a sheet that just closed
    /// has gone. Start On board, or a tap, on the background question is acted on once the app is active, so the ride's Live
    /// Activity can start.
    private func detectsTrains(_ content: some View) -> some View {
        content
            .onChange(of: onBoard.engine?.state?.phase) { _, phase in
                if phase == .atYourStop { backgroundDetection?.rideReachedYourStop() }
            }
            .task(id: offersDetection) {
                guard offersDetection else { return }
                try? await Task.sleep(for: .milliseconds(700))
                guard offersDetection, !Task.isCancelled else { return }
                backgroundDetection?.offerShown()
                router.present(.detectOffer)
            }
            .task(id: detectedRequest) {
                guard let request = detectedRequest else { return }
                router.detectedTrain = nil
                await openDetected(request)
            }
    }

    /// Tapping the Schedule tab while Schedule shows scrolls the timeline back to Now, on today (D49): there is no Now
    /// button. SwiftUI calls the setter on every tap of a tab, also the selected one.
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { router.selectedTab },
            set: { tab in
                if tab == .schedule, router.selectedTab == .schedule {
                    Task { await schedule.backToNow() }
                }
                router.selectedTab = tab
            }
        )
    }

    /// The rules' states and the recent updates; a rule needing review shown on the open Alerts tab is seen.
    private func refreshAlerts() async {
        await alertsModel.refresh()
        if router.selectedTab == .alerts { alertsModel.markReviewsSeen() }
    }

    /// "Pick a new train" on a Time changed row (TT-193): Schedule on that alert's route, with "Tap the bell of your new
    /// train · Cancel"; the bell tapped next takes over its days.
    private func pickNewTrain(replacing rule: AlertRule) {
        router.showSchedule()
        bells.pickNewTrain(replacing: rule)
        guard let key = rule.trip else { return }
        Task {
            let link = NotificationLink.trip(key, originId: rule.origin.id, destinationId: rule.destination.id)
            guard let route = await link.route(stations: stations, saved: schedule.route) else { return }
            if schedule.route.map({ !$0.isSameDirection(as: route) }) ?? true { await schedule.show(route) }
            if schedule.selectedDay != schedule.today { await schedule.select(schedule.today) }
        }
    }

    private func openTrip(_ key: TripKey, on route: Route? = nil) {
        guard let route = route ?? schedule.route else { return }
        // The sheet's own bell model on the same alert rules (TT-192): "Alert me" turns the alert on in place, and its
        // capsule shows in the sheet, never on Schedule under it.
        tripDetails = TripDetailsViewModel(
            route: route, key: key, repository: repository, clock: clock, onBoard: onBoard, alerts: alerts,
            bells: bells.sibling()
        )
        router.present(.tripDetails)
    }

    /// Demo trains, in a build that shows Settings › Testing (an App Store build ignores a stored value).
    private var demoTrains: DemoTrains {
        BuildChannel.showsTesting ? settings.demoTrains : .off
    }

    /// The countdown strip (TT-177): the alerted train's Trip details, or the demo departure's on its own route.
    private func openDeparture(_ key: TripKey) {
        if let demo = onBoard.departureDemo, demo.key == key {
            openTrip(key, on: demo.route)
        } else {
            openTrip(key)
        }
    }

    /// The Live Activity's train before it leaves (TT-178): the demo departure's while it plays, else Schedule's alerted train
    /// today, on the app's clock to the second.
    private func departureForActivity() -> DepartureActivitySource? {
        if let demo = onBoard.departureDemo {
            let now = demo.now
            guard let departure = demo.departure(at: now), let live = LiveDeparture(departure, now: now) else { return nil }
            return DepartureActivitySource(live: live, route: demo.route, now: now, hasPlatformSource: true)
        }
        let now = clock.now
        guard let route = schedule.route, let live = schedule.activityDeparture(at: now) else { return nil }
        return DepartureActivitySource(live: live, route: route, now: now, hasPlatformSource: schedule.hasPlatformSource)
    }

    /// The departure activity's tap: its train's Trip details; its "I’m on board" also starts the ride, in the sheet's own
    /// button window (from 20 min before departure, D63) and unless the first-ride sheet has to come first (the rider then
    /// taps "I’m on board" there).
    private func openDepartureFromActivity(boards: Bool) async {
        guard let ride = liveActivity?.departureRide else { return }
        let key = ride.tripKey
        if let demo = onBoard.departureDemo, demo.key == key {
            router.showSchedule()
            openTrip(key, on: demo.route)
        } else {
            await open(.trip(key, originId: ride.originId, destinationId: ride.destinationId))
        }
        guard boards, let details = tripDetails, details.key == key else { return }
        await details.load()
        guard details.showsOnBoardButton, !details.needsLocationIntro else { return }
        _ = await details.startRide()
    }

    /// When train detection runs (TT-175): on the Schedule tab, in the foreground, with a route; and whether the demo's
    /// question plays.
    private var detection: DetectionRun {
        let watches = scenePhase == .active && router.selectedTab == .schedule
        return DetectionRun(route: watches ? schedule.route : nil, demo: playsDemoRide)
    }

    /// The "Detect my train" offer is due and Schedule shows in the foreground with nothing over it (TT-176).
    private var offersDetection: Bool {
        backgroundDetection?.offerDue == true && scenePhase == .active && router.selectedTab == .schedule
            && router.presentedSheet == nil && schedule.route != nil
    }

    /// The background question's answer, once the app is active.
    private var detectedRequest: DetectedTrainRequest? {
        scenePhase == .active ? router.detectedTrain : nil
    }

    /// Turn on, on the offer: iOS asks for Always, then for notifications if never asked (the question is one), and the
    /// sheet closes once they are answered.
    private func turnOnDetection() async {
        if await backgroundDetection?.turnOn() == true { await alerts.requestPermission() }
        router.dismissSheet()
    }

    /// Start On board: the ride on that train starts, with the app in front, and Trip details opens on it in ride mode; a
    /// tap opens the train's Trip details, where "I’m on board" is. The demo's train (a test push in Debug and TestFlight
    /// builds) plays the demo ride.
    private func openDetected(_ request: DetectedTrainRequest) async {
        let train = request.train
        if train.trip.tripId == DemoRide.tripId {
            guard BuildChannel.showsTesting, request.startsRide, await onBoard.startDemoRide() else { return }
            router.showSchedule()
            await openRide()
            return
        }
        let link = NotificationLink.trip(train.trip, originId: train.originId, destinationId: train.destinationId)
        guard let route = await link.route(stations: stations, saved: schedule.route) else { return }
        if request.startsRide, onBoard.activeRide == nil {
            _ = await onBoard.start(train.ride, on: route)
        }
        router.showSchedule()
        openTrip(train.trip, on: route)
    }

    /// Demo trains › Ride is on, in a build that shows Settings › Testing.
    private var playsDemoRide: Bool {
        demoTrains == .ride
    }

    /// The Live Activity's tap: Trip details on the ride, at once, or once a ride restored at launch is back (TT-174).
    private func openRideFromActivity() async {
        guard opensRide, onBoard.activeRide != nil else { return }
        opensRide = false
        router.showSchedule()
        await openRide()
    }

    /// The ride strip: Trip details for the ride's trip, in ride mode (TT-172).
    private func openRide() async {
        guard let ride = onBoard.activeRide, let route = await onBoard.rideRoute(stations: stations) else { return }
        openTrip(ride.tripKey, on: route)
    }

    /// A notification tap: Trip details for its trip and service date, over the timeline of the alert's route and day, so
    /// closing the sheet shows the next trains; the Alerts tab for a past service date or a rule to review (rule 10).
    private func open(_ link: NotificationLink) async {
        switch link.target(today: ServiceDay(containing: clock.now)) {
        case .alerts:
            router.showAlerts()
        case .trip(let key):
            guard let route = await link.route(stations: stations, saved: schedule.route) else { return }
            router.showSchedule()
            // The sheet first; the timeline behind it follows without holding it up.
            openTrip(key, on: route)
            if schedule.route.map({ !$0.isSameDirection(as: route) }) ?? true { await schedule.show(route) }
            // A service date before Schedule's Today (a late train's alert between 12:00 and 3:00 AM, D52) is not in the strip.
            if schedule.selectedDay != key.serviceDay, key.serviceDay >= schedule.today { await schedule.select(key.serviceDay) }
        }
    }

    /// "Show trains" on first use.
    private func show(_ route: Route) {
        Task { await schedule.show(route) }
    }
}

/// Train detection's run: the route while Schedule shows in the foreground (nil stops it), and Demo trains › Ride.
private struct DetectionRun: Hashable {
    let route: Route?
    let demo: Bool
}

#Preview {
    RootView()
}
