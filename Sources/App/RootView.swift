import Combine
import SwiftUI

/// Three icon-only tabs, Schedule, Alerts and Settings (D48, D49), and nothing else at the top level. Tapping the Schedule
/// tab while it shows scrolls the timeline back to Now (D49). Launch lands on Schedule with no
/// prompt: the remembered route after the Bloom splash, or on first use the welcome, your line and your station with no
/// tab bar (TT-206, D94). Recent routes are shared by Schedule, which
/// records them and lists them in its station picker (D48, D54). Puts the one time formatter in the
/// environment (TT-105); the app follows the iOS appearance (D84). Opens the trip or the Alerts tab for a tapped notification (TT-144).
struct RootView: View {
    @State private var router: AppRouter
    @State private var schedule: ScheduleViewModel
    @State private var settings: AppSettings
    @State private var settingsModel: SettingsViewModel
    /// The first launch (TT-206): the welcome and its two steps; after the first route, Schedule makes its own picker each
    /// time a station is tapped (D54).
    @State private var welcome: WelcomeViewModel
    /// Bloom on a cold start with a saved route, folding back into Schedule (TT-206); shown once per launch.
    @State private var showsSplash: Bool
    /// The splash still covers Schedule, until its mark begins to fade (TT-227).
    @State private var splashCovers: Bool
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
    /// A ride that started by itself with the app in front (TT-242, D120) whose ride mode has not opened yet: it opens at
    /// once, at rest, if Schedule shows with nothing over it. One that started in the background opens at the next arrival,
    /// as every running ride does (TT-256, D130).
    @State private var opensAutoRide: AutoRideWatch.Started?
    /// The ride opening by itself each time the app opens or comes back (TT-256, D130); Schedule reports to it.
    @State private var rideOpening = RideOpening()
    /// The app has just launched or has been in the background since the last arrival: the next time it is active is an
    /// arrival (TT-256, D130). Back from Notification Centre or Control Centre is not one.
    @State private var arrives = true
    /// Schedule's Feedback button asking now and then (TT-228, D112); Settings opens the sheet through it too.
    @State private var feedbackNudge: FeedbackNudge
    /// Automatic direction's look (TT-234, D116): one per app, fed by Schedule.
    @State private var direction: DirectionLook
    /// The automatic ride's one-time strip on Schedule (TT-243, D120).
    @State private var autoRideStrip: AutoRideStrip
    private let liveActivity: RideLiveActivity?
    /// When the app is closed (TT-243, D120): its wake-ups start again when the app comes to the front; nil in fixture runs.
    private let autoRideWake: AutoRideWake?
    /// The wrong train warning's presenter (TT-250, D127, `AppDelegate.wrongTrain`); nil in previews and snapshots.
    private let wrongTrain: WrongTrain?
    /// The wrong train check (TT-251, D127, `AppDelegate.wrongTrainCheck`); nil in fixture runs, previews and snapshots.
    private let wrongTrainCheck: WrongTrainCheck?
    /// The widget file (TT-182, D107); nil in fixture runs. Kept in state so it stays the writer made beside the settings,
    /// alert rules and recent routes the screens change: SwiftUI makes `RootView` again now and then, and a writer made
    /// then held copies of its own that nothing changes, so a Time format change or a new alert wrote the same file
    /// until the next launch (TT-185, D117).
    @State private var widgetFile: WidgetFileWriter?
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
        alertsModel: AlertsViewModel? = nil,
        ride: RideEngine? = nil,
        nudge: ArrivalNudge? = nil,
        liveActivity: RideLiveActivity? = nil,
        autoRide: AutoRideWatch? = nil,
        autoRideWake: AutoRideWake? = nil,
        wrongTrain: WrongTrain? = nil,
        wrongTrainCheck: WrongTrainCheck? = nil,
        feedbackNudge: FeedbackNudge = .app(),
        direction: DirectionDependencies = .app()
    ) {
        let bells = bells ?? AlertBellModel(
            rules: alertDependencies.rules(settings: settings), actionDuration: alertDependencies.capsuleActionDuration,
            plainDuration: alertDependencies.capsulePlainDuration
        )
        let schedule = schedule ?? ScheduleViewModel(
            route: routeStore.route, repository: dependencies.repository, clock: dependencies.clock, routeStore: routeStore,
            recents: recents, dismissedNotices: dismissedNotices, watchedTrips: bells.rules, routeCount: RouteCount(),
            boardingShown: BoardingShown()
        )
        // Automatic direction (TT-234, D116): the look reads the location through its own reader, with Demo place over it
        // in TestFlight and Debug builds, and follows each route the rider chooses.
        let location: any DirectionLocating = BuildChannel.showsTesting
            ? DemoPlaceLocation(
                base: direction.location, stations: dependencies.stations, route: { [weak schedule] in schedule?.route }
            )
            : direction.location
        let look = DirectionLook(
            schedule: schedule, location: location, stations: dependencies.stations, store: direction.store,
            clock: dependencies.clock, ride: ride, track: direction.track,
            capsule: DirectionCapsuleModel(
                actionDuration: alertDependencies.capsuleActionDuration, plainDuration: alertDependencies.capsulePlainDuration
            ),
            quick: direction.quick
        )
        schedule.choices = look
        _direction = State(initialValue: look)
        // The arriving nudge (TT-173): the app engine's from `AppDelegate`, the demo ride's on its 6x clock; a started ride
        // asks for notifications through the alert rules, as the first bell tap does (D66). The automatic ride's watch
        // (TT-242) is `AppDelegate`'s; the demo's is On board's own.
        let rules = bells.rules
        // The automatic ride's "off", Not on it count and one-time strip (TT-243, D120): on device in the app and in UI
        // tests (which clear them with launch arguments), none in previews and the unit test host.
        let environment = ProcessInfo.processInfo.environment
        let autoRideStore = !ScheduleDependencies.isFixtureRun(environment) || environment["TT_FIXTURES"] != nil
            ? AutoRideStore(defaults: .standard) : nil
        let onBoard = OnBoard(
            app: ride, liveActivity: liveActivity,
            nudge: nudge, makeDemoNudge: { ArrivalNudge.demo() },
            requestNotifications: { await rules.requestPermission() },
            wishes: ArrivalWishes(defaults: .standard, haptics: TTHaptics.shared),
            declines: ScheduleDependencies.isFixtureRun(environment) ? nil : .standard,
            autoRide: autoRide,
            autoRideStore: autoRideStore,
            wrongTrain: wrongTrain
        )
        // The strip shows while Automatic ride reads on, as the Settings switch does.
        let strip = AutoRideStrip(store: autoRideStore) { [weak settings] in
            guard let autoRideStore else { return false }
            let demo = BuildChannel.showsTesting && settings?.demoAutoRide ?? .off != .off
            return location.readsOn(autoRideStore, demo: demo)
        }
        _autoRideStrip = State(initialValue: strip)
        _router = State(initialValue: router)
        _schedule = State(initialValue: schedule)
        _settings = State(initialValue: settings)
        // The alert rules' permission source, so a fixture run's `TT_NOTIFICATIONS` shows in Settings too (TT-142).
        // Its alert rules give the Notifications page the "My trains" count and the permission prompt (TT-168).
        _settingsModel = State(
            initialValue: SettingsViewModel(
                settings: settings, permissions: alertDependencies.permissions, clock: dependencies.clock, alerts: bells.rules,
                autoRideStore: autoRideStore, autoRideWake: autoRideWake, autoRideStrip: strip,
                direction: location, directionStore: direction.store, look: look,
                route: { [weak schedule] in schedule?.route }, autoRideCheck: { [weak onBoard] in onBoard?.autoRideCheck },
                wrongTrainCheck: { [weak wrongTrainCheck] in wrongTrainCheck?.lastCheck }
            )
        )
        _welcome = State(
            initialValue: WelcomeViewModel(stations: dependencies.stations, clock: dependencies.clock, recents: schedule.recents)
        )
        _showsSplash = State(initialValue: LaunchMotion.plays && LaunchMotion.exit(savedRoute: schedule.route) == .schedule)
        _splashCovers = State(initialValue: LaunchMotion.plays && LaunchMotion.exit(savedRoute: schedule.route) == .schedule)
        _alerts = State(initialValue: bells.rules)
        _bells = State(initialValue: bells)
        _alertsModel = State(
            initialValue: alertsModel ?? AlertsViewModel(
                rules: bells.rules,
                repository: dependencies.repository,
                nextTrains: schedule,
                clock: dependencies.clock,
                mayAlert: { [bells] trip, route in await bells.mayAlert(trip, on: route) },
                actionDuration: alertDependencies.capsuleActionDuration,
                plainDuration: alertDependencies.capsulePlainDuration
            )
        )
        _onBoard = State(initialValue: onBoard)
        _feedbackNudge = State(initialValue: feedbackNudge)
        self.liveActivity = liveActivity
        self.autoRideWake = autoRideWake
        self.wrongTrain = wrongTrain
        self.wrongTrainCheck = wrongTrainCheck
        _widgetFile = State(
            initialValue: dependencies.widgetData.flatMap {
                WidgetFileWriter.app(
                    data: $0, routeStore: routeStore, rules: rules, settings: settings, recents: schedule.recents,
                    direction: direction.store
                )
            }
        )
        stations = dependencies.stations
        repository = dependencies.repository
        clock = dependencies.clock
        TabBarStyle.apply()
    }

    var body: some View {
        writesWidgetFile(opensRideByItself(watchesAutoRide(followsRides(tabs))))
            // Each screen the rider sees, named by us (TT-208, D92): SwiftUI has no view controllers worth naming.
            .onChange(of: analyticsScreen, initial: true) { _, screen in Analytics.screen(screen) }
            // A before-departure card lives only while its alert is switched on (TT-240, D118): a bell turned off, an
            // alert removed or paused ends its card at the tap, and Undo brings it back. The automatic ride's watch stops
            // with its alert too (TT-242).
            .onChange(of: alerts.rules) {
                liveActivity?.alertsChanged()
                onBoard.autoRide?.alertsChanged(alerts)
            }
            // Schedule's time away is kept here, whichever tab is shown, so the Schedule tab coming back after more than
            // 10 min in the background goes back to Now (TT-222, TT-246). Not during the welcome, which has no Schedule.
            .onChange(of: scenePhase) { _, phase in
                if phase == .background, schedule.route != nil { schedule.wentToBackground() }
            }
    }

    /// The screen on top: the presented sheet, else the selected tab (the welcome or its route form until a route is saved).
    private var analyticsScreen: AnalyticsScreen {
        switch router.presentedSheet {
        case .tripDetails: return .tripDetails
        case .lineNotices: return .lineNotices
        case nil: break
        }
        switch router.selectedTab {
        case .schedule: return schedule.route == nil ? (welcome.step == .search ? .routeForm : .welcome) : .schedule
        case .alerts: return .alerts
        case .settings: return .settings
        }
    }

    /// The welcome until the first route, then the tabs; the splash over both on a cold start with a saved route.
    private var tabs: some View {
        ZStack {
            if schedule.route == nil {
                WelcomeFlowView(model: welcome, onRoute: { show($0) })
                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
            } else {
                tabView
                    .environment(\.launchCovers, splashCovers)
                    .environment(\.feedbackNudge, feedbackNudge)
                    .environment(\.directionLook, direction)
                    .environment(\.autoRideStrip, autoRideStrip)
                    .environment(\.rideOpening, rideOpening)
                    .environment(\.scheduleCovered, router.presentedSheet != nil || router.selectedTab != .schedule)
                    .environment(\.visibleTab, router.presentedSheet == nil ? router.selectedTab : nil)
                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
            }
        }
        .overlay {
            if showsSplash {
                LaunchSplash(onFold: { splashLifts() }, onFinish: { showsSplash = false })
            }
        }
        .sheet(item: $router.presentedSheet) { sheet in
            switch sheet {
            case .tripDetails:
                if let tripDetails {
                    // A new trip while the sheet is up (a notification tap) gets a fresh view, so it loads (TT-144).
                    TripDetailsView(viewModel: tripDetails, onClose: { router.dismissSheet() })
                        .id(ObjectIdentifier(tripDetails))
                }
            case .lineNotices:
                LineNoticeSheet(viewModel: schedule)
            }
        }
        // A tapped notification, also one that launched the app before this view appeared (TT-144).
        .onChange(of: router.pendingLink, initial: true) { _, link in
            guard let link else { return }
            let boards = router.pendingLinkBoards
            router.pendingLink = nil
            router.pendingLinkBoards = false
            let source = router.pendingLinkSource
            Task {
                await open(link, source: boards ? .departure : source)
                // Yes on the departure question's notification (TT-231): the ride starts as "I’m on board" does.
                if boards, case .trip(let key, _, _) = link { await board(key) }
            }
        }
        // The first route saved on device: Rail joint as the first trains land, 260 ms in (TT-215, D100); the station tap
        // that set it is silent.
        .onChange(of: schedule.route) { old, new in
            if old == nil, new != nil { TTHaptics.shared.play(.firstTrains) }
        }
        // Schedule leaves the open trip's feels to its sheet (TT-215).
        .onChange(of: openTripKey, initial: true) { _, key in schedule.openTrip = key }
        .environment(\.timeFormatter, settings.timeFormatter)
        // Demo trains (D49): the timeline shows the new scenario at once.
        .onChange(of: settings.demoTrains) { Task { await schedule.refresh() } }
        // Live data (TT-195), Board included (TT-233): the made-up feed shows at once too, not at the next poll.
        .onChange(of: settings.mockLive) { Task { await schedule.refresh() } }
        // Demo trains › Ride (TT-172) and › Departure (TT-177), while chosen, in TestFlight and Debug builds only: the demo
        // ride plays at once (TT-243: its question went with train detection); the demo departure plays from 5:01 PM.
        // Leaving Departure also stops the ride it handed over to.
        // Settings › Testing › Wrong train (TT-250): turned on or off while Ride is chosen, the demo ride starts again.
        .task(id: DemoPlay(trains: demoTrains, wrongTrain: demoWrongTrain)) {
            onBoard.setDemoDeparture(demoTrains == .departure)
            await onBoard.setDemo(demoTrains == .ride, wrongTrain: demoWrongTrain)
        }
        // Mock time (TT-158): the timeline starts again at the new present, as a relaunch would.
        .onChange(of: settings.mockTime) { Task { await schedule.restart() } }
        // Notifications may have been allowed or turned off in Settings while the app was away (TT-141), a rule may need
        // review and notifications may have arrived (TT-143). Back from the toast's Turn on with notifications on, the
        // bell that was tapped turns on (TT-190).
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            closeEndedRide()
            // A ride restored in the background gets its Live Activity now, with the app in front (TT-174).
            liveActivity?.sceneDidBecomeActive()
            // A ride that started by itself meanwhile makes the one-time strip due, and Always may have been taken back in
            // the Settings app (TT-243).
            autoRideStrip.refresh()
            autoRideWake?.resume()
            // A departure question the rider left unanswered goes once its 10 min are over (TT-231).
            await DepartureNotice.removeExpired()
            await refreshAlerts()
            await bells.cameBack()
        }
        // While another tab shows, the Alerts cards' trains are read again each minute, so the tab's dot follows a train
        // that turns late, is cancelled or leaves (TT-253, D129); the open tab polls by itself every 30 s.
        .task(id: scenePhase == .active && router.selectedTab != .alerts) {
            guard scenePhase == .active, router.selectedTab != .alerts else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: AlertsViewModel.backgroundPollInterval)
                guard !Task.isCancelled else { return }
                await alertsModel.load()
            }
        }
        // Before departure the Live Activity follows the alerted train, and the alert rules take its tokens to the alert
        // server (TT-178).
        .task {
            // The demo card's Not on it (TT-243) goes to the OnBoard this view keeps: set here, not in OnBoard's init, which
            // runs again for every RootView init SwiftUI makes and would point it at an OnBoard that was thrown away.
            let kept = onBoard
            liveActivity?.demoNotOnIt = { [weak kept] ride in kept?.demoCardNotOnIt(ride) }
            // The wrong train warning's "Trains from …" and its expiry end the ride here (TT-250, D127), the demo's too.
            wrongTrain?.endRide = { [weak kept] ride in kept?.endWrongTrain(ride) ?? false }
            liveActivity?.connect(reporter: alerts, wishes: onBoard) { departureForActivity() }
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
            case .wrong:
                // The wrong train warning's card (TT-250, D127): the app opens on the warning.
                openWrongTrain()
            case .end:
                // Like End ride on the sheet: the ride ends, and its Trip details closes if it is open.
                let ride = onBoard.activeRide
                onBoard.end()
                if router.presentedSheet == .tripDetails, let ride, tripDetails?.key == ride.tripKey {
                    router.dismissSheet()
                }
            case nil:
                // A widget's train or header (TT-182); a cold launch takes the pending-link path. A tap on a widget is
                // counted with what it opened (TT-183).
                guard let link = NotificationLink(url: url, today: ServiceDay(containing: clock.now)) else { break }
                if let widget = WidgetLink.widget(of: url) {
                    var opensTrip = false
                    if case .trip = link { opensTrip = true }
                    Analytics.track(.widgetOpened(widget, opensTrip: opensTrip))
                }
                router.open(link, source: .link)
            }
        }
        .onChange(of: onBoard.activeRide) {
            guard opensRide, onBoard.activeRide != nil else { return }
            Task { await openRideFromActivity() }
        }
        // The wrong train warning (TT-250, D127): "Trains from …", also from the notification's action on a cold start, and
        // a tap on its notification.
        .onChange(of: wrongTrain?.routeRequest, initial: true) { _, request in
            guard let request else { return }
            Task { await showWrongTrainRoute(request) }
        }
        .onChange(of: wrongTrain?.openRequest ?? 0) { openWrongTrain() }
        // Opening the Alerts tab turns its dot off and reads its trains again; leaving it lets the empty tab's suggestions go
        // and deletes one-day alerts switched off there (TT-253, D129).
        .onChange(of: router.selectedTab) { old, tab in
            if old == .alerts { alertsModel.leftTab() }
            guard tab == .alerts else { return }
            router.showsAlertsDot = false
            Task { await refreshAlerts() }
        }
    }

    private var tabView: some View {
        TabView(selection: tabSelection) {
            NavigationStack {
                ScheduleView(
                    viewModel: schedule,
                    stations: stations,
                    onOpenTrip: { openTrip($0) },
                    onOpenLineNotice: { router.present(.lineNotices) },
                    bells: bells,
                    onBoard: onBoard,
                    onOpenRide: { Task { await openRide() } }
                )
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
                onShowInSchedule: { showInSchedule($0) },
                onOpenTrip: { openAlertTrip($0) },
                onPickNewTrain: { pickNewTrain(replacing: $0) }
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
    }

    /// The ride's ending and the departure question, apart from `tabs` so each chain type-checks in reasonable time. A ride
    /// that ended at your stop, by Not on it or by itself (TT-243) closes its sheet.
    private func followsRides(_ content: some View) -> some View {
        content
            .onChange(of: onBoard.engine?.state?.phase) { _, phase in
                if phase == .ended { closeEndedRide() }
            }
            // The departure question (TT-231, D110): with the app in front on Schedule, its strip asks once the alerted
            // train has left; elsewhere nothing asks in the app.
            .task(id: asksOnSchedule) {
                guard asksOnSchedule else {
                    onBoard.updateDepartureAsk(nil, route: nil, isDemo: false)
                    return
                }
                while !Task.isCancelled {
                    let source = departureForActivity(askingDeclined: true)
                    onBoard.updateDepartureAsk(source?.live, route: source?.route, isDemo: onBoard.departureDemo != nil)
                    try? await Task.sleep(for: .seconds(1))
                }
            }
    }

    /// The ride that starts by itself (TT-242, D120), apart from `tabs` so each chain type-checks in reasonable time. While
    /// the app is in front, on any tab, the watch is offered the alerted trains on screen every few seconds (Schedule's and
    /// the departure card's); Settings › Testing's demo watch follows its setting; and a ride that started by itself opens
    /// ride mode once, at rest, on Schedule with nothing over it (an open Trip details on that train adopts it instead).
    private func watchesAutoRide(_ content: some View) -> some View {
        content
            .task(id: scenePhase) {
                // The wrong train check (TT-251, D127) is offered today's alerted trains beside the watch, outside its
                // `mayArm`: a train the watch did not arm for (a short ride, or one that left with the rider still at O).
                let watch = onBoard.autoRide
                guard scenePhase == .active, watch != nil || wrongTrainCheck != nil else { return }
                while !Task.isCancelled {
                    if let watch, watch.mayArm { await watch.consider(await autoRideCandidates()) }
                    await wrongTrainCheck?.consider()
                    try? await Task.sleep(for: .seconds(5))
                }
            }
            .task(id: demoAutoRide) { onBoard.setDemoAutoRide(demoAutoRide) }
            // Decided once in front: at once if Schedule is at rest, else the ride strip waits on Schedule; a start while the
            // app is inactive (Notification Centre or Control Centre over it), as it becomes active again. A start in the
            // background opens at the next arrival, as any running ride does (TT-256, D130, revising D120's next
            // foreground). Never later, so no sheet pops up mid-ride.
            .onChange(of: onBoard.autoRideStarted) { _, started in
                guard let started else { return }
                if router.presentedSheet == .tripDetails, let details = tripDetails, details.key == started.ride.tripKey {
                    details.adoptRide()
                    return
                }
                guard scenePhase != .background else { return }
                opensAutoRide = started
                if scenePhase == .active { openAutoRideIfAtRest() }
            }
    }

    /// The ride opens by itself (TT-256, D130, Card states board 13), apart from `tabs` so each chain type-checks in
    /// reasonable time: with a ride running, each time the app opens or comes back from the background, ride mode opens
    /// over Schedule, also after the rider closed it.
    private func opensRideByItself(_ content: some View) -> some View {
        content
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    // The arrival opens a ride that started by itself while the app was away.
                    arrives = true
                    opensAutoRide = nil
                } else if phase == .active {
                    openAutoRideIfAtRest()
                }
            }
            .task(id: scenePhase) {
                guard scenePhase == .active, arrives else { return }
                arrives = false
                await openRideOnArrival()
            }
    }

    /// An arrival: after a beat, once the launch splash has gone and a ride restored at launch is back (up to 3 s after
    /// the splash), ride mode opens if a ride runs, Schedule's tab is in front with nothing of the app's or of Schedule's
    /// own over it, no Live Activity tap is opening the ride already and nobody touched Schedule meanwhile.
    private func openRideOnArrival() async {
        rideOpening.arrived()
        try? await Task.sleep(for: RideOpening.beat)
        var deadline: ContinuousClock.Instant?
        while !Task.isCancelled {
            if !showsSplash {
                let until = deadline ?? ContinuousClock.now + RideOpening.rideWait
                deadline = until
                if onBoard.activeRide != nil || ContinuousClock.now >= until { break }
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard !Task.isCancelled else { return }
        let inFront = router.selectedTab == .schedule && router.presentedSheet == nil && schedule.route != nil
            && !showsSplash && !opensRide
        guard rideOpening.decide(rideRuns: onBoard.activeRide != nil, inFront: inFront),
              let ride = onBoard.activeRide else { return }
        await openRideInPlace(ride, risesIn: true)
    }

    /// Ride mode for the ride that started by itself when Schedule is at rest; otherwise it is let go.
    private func openAutoRideIfAtRest() {
        guard opensAutoRide != nil else { return }
        if autoRideAtRest {
            Task { await openAutoRide() }
        } else {
            opensAutoRide = nil
        }
    }

    /// Settings › Testing › Demo trains › Depart › Automatic ride, in a build that shows Settings › Testing.
    private var demoAutoRide: DemoAutoRide {
        BuildChannel.showsTesting ? settings.demoAutoRide : .off
    }

    /// A ride that started by itself opens ride mode only on Schedule in the foreground with nothing over it.
    private var autoRideAtRest: Bool {
        opensAutoRide != nil && scenePhase == .active && router.selectedTab == .schedule && router.presentedSheet == nil
            && schedule.route != nil
    }

    /// Ride mode for the ride that started by itself, once: drawn at rest, with no `trip_opened` (nobody tapped).
    private func openAutoRide() async {
        guard let started = opensAutoRide else { return }
        opensAutoRide = nil
        guard onBoard.activeRide == started.ride else { return }
        await openRideInPlace(started.ride, risesIn: false)
    }

    /// Ride mode that nobody tapped open (TT-242, TT-256): no `trip_opened`, counted as `ride_ended`'s `auto_opens`.
    /// `risesIn` false draws it at rest, as the automatic start's; an arrival's rows rise as the strip's tap does.
    private func openRideInPlace(_ ride: Ride, risesIn: Bool) async {
        guard let route = await onBoard.rideRoute(stations: stations), onBoard.activeRide == ride,
              router.presentedSheet == nil else { return }
        onBoard.screen.opensByItself(onBoard.engine)
        let details = TripDetailsViewModel(
            route: route, key: ride.tripKey, repository: repository, clock: clock, onBoard: onBoard, alerts: alerts,
            bells: bells.sibling(), boardingShown: BoardingShown(), ridesInPlace: !risesIn
        )
        followAlertCard(of: details)
        tripDetails = details
        router.present(.tripDetails)
    }

    /// The alerted trains the watch may arm for (TT-242, D120): Schedule's alerted train today, and the departure card's
    /// train where it is another (an alert on another route), each only while an alert stands behind it.
    private func autoRideCandidates() async -> [AutoRideWatch.Candidate] {
        var candidates: [AutoRideWatch.Candidate] = []
        let now = clock.now
        if let route = schedule.route, let live = schedule.activityDeparture(at: now),
           alerts.isAlerted(live.departure.trip, on: route) {
            candidates.append(AutoRideWatch.Candidate(route: route, departure: live.departure))
        }
        guard let card = liveActivity?.departureRide, !candidates.contains(where: { $0.ride == card }),
              let rule = alerts.rules.first(where: { $0.covers(card) }) else { return candidates }
        let route = Route(
            from: Station(id: rule.origin.id, name: rule.origin.name),
            to: Station(id: rule.destination.id, name: rule.destination.name),
            line: Line(id: rule.line, name: "", colorHex: nil)
        )
        let day = card.tripKey.serviceDay
        guard let trip = (try? await repository.trips(for: route, on: day))?.first(where: { $0.key == card.tripKey }),
              alerts.isAlerted(trip, on: route) else { return candidates }
        let live = (try? await repository.liveStatus(for: route, on: day)) ?? .empty
        let resolved = Departure.resolve([trip], live: live, freshness: Freshness(live, now: now), isToday: true)
        if let departure = resolved.first { candidates.append(AutoRideWatch.Candidate(route: route, departure: departure)) }
        return candidates
    }

    /// The widget file (TT-182, D107) is written at launch, each time the app comes to the front (a widget placed or edited
    /// meanwhile gets its route, TT-183), after a route, alert, Time format or timetable change, and when the app goes to
    /// the background; the widgets reload only when its bytes changed. Coming to the front also counts the placed widgets
    /// (`widgets_placed`), in real runs only.
    private func writesWidgetFile(_ content: some View) -> some View {
        content
            .task { widgetFile?.update() }
            .onChange(of: schedule.route) { widgetFile?.update() }
            .onChange(of: alerts.rules) { widgetFile?.update() }
            .onChange(of: settings.timeFormat) { widgetFile?.update() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .inactive { widgetFile?.update() }
            }
            .task(id: scenePhase) {
                guard scenePhase == .active, widgetFile != nil, let placed = await SystemPlacedWidgets().widgets() else { return }
                WidgetsPlacedCount().report(placed)
            }
            .onReceive(NotificationCenter.default.publisher(for: .timetableImported)) { _ in widgetFile?.update() }
    }

    /// The trip whose Trip details is open.
    private var openTripKey: TripKey? {
        router.presentedSheet == .tripDetails ? tripDetails?.key : nil
    }

    /// Tapping the Schedule tab while Schedule shows scrolls the timeline back to Now, on today (D49): there is no Now
    /// button. SwiftUI calls the setter on every tap of a tab, also the selected one.
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { router.selectedTab },
            set: { tab in
                // A tab tap, and Schedule tapped again to go back to Now, tick (Grigor, 2026-11-18; TT-215, D100). Another
                // tab tapped again changes nothing and stays silent.
                if tab != router.selectedTab || tab == .schedule { TTHaptics.shared.play(.tab) }
                if tab == .schedule, router.selectedTab == .schedule {
                    Analytics.track(.backToNow(.tab))
                    Task { await schedule.backToNow() }
                }
                router.selectedTab = tab
            }
        )
    }

    /// The rules' states and the Alerts cards' trains.
    private func refreshAlerts() async {
        await alertsModel.refresh()
    }

    /// An Alerts card's "See trains" (TT-253, D129): Schedule on the alert's route and its train's day, nothing over it, as
    /// one train's link (the route stays until swapped), landing on the card itself with the train before it above, and the
    /// card swells once with its bell's pop (TT-255).
    private func showInSchedule(_ jump: AlertsViewModel.Jump) {
        router.dismissSheet()
        schedule.expectLanding()
        router.showSchedule()
        Task {
            let link = NotificationLink.trip(jump.key, originId: jump.originId, destinationId: jump.destinationId)
            guard let route = await link.route(stations: stations, saved: schedule.route) else { return }
            await schedule.land(.card(jump.key), on: route, day: jump.key.serviceDay)
        }
    }

    /// A tap on an Alerts card: its train's Trip details on the alert's route (`trip_opened`, source `alerts`).
    private func openAlertTrip(_ jump: AlertsViewModel.Jump) {
        Task {
            let link = NotificationLink.trip(jump.key, originId: jump.originId, destinationId: jump.destinationId)
            guard let route = await link.route(stations: stations, saved: schedule.route) else { return }
            openTrip(jump.key, on: route, source: .alerts, alertID: jump.alertID)
        }
    }

    /// "Pick a new train" on a Time changed card (TT-193): Schedule on that alert's route and the next day it rings, at the
    /// old time's place (TT-255), with "Tap the bell of your new train · Cancel"; the bell tapped next takes over its days.
    private func pickNewTrain(replacing rule: AlertRule) {
        if rule.trip != nil { schedule.expectLanding() }
        router.showSchedule()
        bells.pickNewTrain(replacing: rule)
        guard let key = rule.trip else { return }
        Task {
            let link = NotificationLink.trip(key, originId: rule.origin.id, destinationId: rule.destination.id)
            guard let route = await link.route(stations: stations, saved: schedule.route) else { return }
            let day = rule.nextRingDay(today: schedule.today, now: clock.now)
            await schedule.land(.time(rule.scheduledDeparture), on: route, day: day)
        }
    }

    /// `alertID`: the Alerts card's alert, whose Time changed card has no train to look it up by (TT-254).
    private func openTrip(
        _ key: TripKey, on route: Route? = nil, source: TripOpenSource = .schedule, alertID: AlertRule.ID? = nil
    ) {
        guard let route = route ?? schedule.route else { return }
        Analytics.track(.tripOpened(source: source, isToday: key.serviceDay == ServiceDay(containing: clock.now)))
        // The sheet's own bell model on the same alert rules (TT-192): "Alert me" turns the alert on in place, and its
        // capsule shows in the sheet, never on Schedule under it.
        let details = TripDetailsViewModel(
            route: route, key: key, repository: repository, clock: clock, onBoard: onBoard, alerts: alerts,
            bells: bells.sibling(), boardingShown: BoardingShown(), alertID: alertID
        )
        followAlertCard(of: details)
        tripDetails = details
        router.present(.tripDetails)
    }

    /// The alert card's Remove alert and Pick a new train close the sheet (TT-254, D129). Removed from the Alerts tab, the
    /// tab says "Alert removed · Undo" (`alerts_tab`); from anywhere else Schedule does (`trip_details`).
    private func followAlertCard(of details: TripDetailsViewModel) {
        details.onRemoveAlert = { [weak details] rule in
            router.dismissSheet()
            if router.selectedTab == .alerts {
                alertsModel.remove(rule.id)
            } else {
                bells.remove(rule, trip: details?.departure?.trip, route: details?.route)
            }
        }
        details.onPickNewTrain = { rule in
            router.dismissSheet()
            pickNewTrain(replacing: rule)
        }
    }

    /// The ride Trip details follows ended on its own at your stop (2 min after it, D103), also while the app was away: the
    /// sheet closes, so no ride screen is left for a ride that is over (TT-221, D98). The arrival wish left by `auto`. The
    /// same for a ride Not on it or the undo by itself ended (TT-243).
    private func closeEndedRide() {
        guard router.presentedSheet == .tripDetails, let details = tripDetails else { return }
        // Not on it on the card, or the undo by itself (TT-243, D120): the sheet goes with the ride, no wish.
        if details.rideWasUndone { return router.dismissSheet() }
        guard details.isRiding, onBoard.endedAtYourStop(details.key) else { return }
        onBoard.wishes.closed(.auto)
        router.dismissSheet()
    }

    /// Demo trains, in a build that shows Settings › Testing (an App Store build ignores a stored value).
    private var demoTrains: DemoTrains {
        BuildChannel.showsTesting ? settings.demoTrains : .off
    }

    /// Settings › Testing › Demo trains › Ride › Wrong train (TT-250), in a build that shows Settings › Testing.
    private var demoWrongTrain: Bool {
        BuildChannel.showsTesting && settings.demoWrongTrain
    }

    /// What the demo plays: its task starts again when either changes.
    private struct DemoPlay: Equatable {
        let trains: DemoTrains
        let wrongTrain: Bool
    }

    /// The wrong train warning's card or notification was tapped (TT-250, D127): ride mode while a ride runs, where the
    /// warning stands in the hero's place; else Schedule with nothing over it, where the strip shows it.
    private func openWrongTrain() {
        guard onBoard.activeRide != nil else {
            router.dismissSheet()
            router.showSchedule()
            return
        }
        opensRide = true
        Task {
            await openRideFromActivity()
            try? await Task.sleep(for: .seconds(15))
            opensRide = false
        }
    }

    /// "Trains from …" (TT-250, D127): as a widget's route link does, nothing over Schedule, the route from X's next stop
    /// to the rider's stop when a train still leaves today, else back to where they got on, at Today and Now. Shown as a
    /// train's link is: kept as a choice by hand, so Automatic direction does not turn it back.
    private func showWrongTrainRoute(_ request: WrongTrainRouteRequest) async {
        wrongTrain?.routeHandled(request)
        router.dismissSheet()
        router.showSchedule()
        guard let route = await WrongTrainRoute.route(
            for: request, stations: stations, repository: repository, now: clock.now
        ) else { return }
        await schedule.show(route, chosen: .trainLink)
        await schedule.backToNow()
    }

    /// The Live Activity's train before it leaves (TT-178): the demo departure's while it plays, else Schedule's alerted train
    /// today, on the app's clock to the second. Once it has left, none for a train declined today (TT-231), unless
    /// `askingDeclined` (Schedule's strip checks that itself, also for the demo).
    private func departureForActivity(askingDeclined: Bool = false) -> DepartureActivitySource? {
        let source: DepartureActivitySource
        if let demo = onBoard.departureDemo {
            let now = demo.now
            guard let departure = demo.departure(at: now), let live = LiveDeparture(departure, now: now) else { return nil }
            source = DepartureActivitySource(live: live, route: demo.route, now: now)
        } else {
            let now = clock.now
            guard let route = schedule.route, let live = schedule.activityDeparture(at: now) else { return nil }
            source = DepartureActivitySource(live: live, route: route, now: now)
        }
        if !askingDeclined, source.live.phase == .departed,
           onBoard.isDeclined(DepartureAsk(live: source.live, route: source.route, isDemo: onBoard.departureDemo != nil)) {
            return nil
        }
        return source
    }

    /// Schedule shows in the foreground with a route: where the departure question asks in the app (TT-231).
    private var asksOnSchedule: Bool {
        scenePhase == .active && router.selectedTab == .schedule && schedule.route != nil
    }

    /// The departure activity's tap: its train's Trip details; its "I’m on board" also starts the ride, in the sheet's own
    /// button window (from 20 min before departure, D63) and unless the first-ride sheet has to come first (the rider then
    /// taps "I’m on board" there).
    private func openDepartureFromActivity(boards: Bool) async {
        let key: TripKey
        if let demo = onBoard.departureDemo {
            // The demo departure's activity is the one showing (Schedule has no countdown strip since TT-205): its link
            // opens the demo's train, in fixture runs too, where the app has no Live Activity of its own.
            key = demo.key
            router.showSchedule()
            openTrip(key, on: demo.route, source: .departure)
        } else {
            guard let ride = liveActivity?.departureRide else { return }
            key = ride.tripKey
            await open(.trip(key, originId: ride.originId, destinationId: ride.destinationId), source: .departure)
        }
        guard boards else { return }
        // Yes on the card's question (TT-231, D110; the card has no other link to boarding).
        Analytics.track(.departureQuestionAnswered(yes: true, surface: .card))
        await board(key)
    }

    /// Yes on the departure question, on the card or its notification: in the open Trip details, the ride starts as
    /// "I’m on board" does, in the sheet's button window (from 20 min before departure until arrival, D63) and unless the
    /// first-ride sheet has to come first (the rider then taps "I’m on board" there).
    private func board(_ key: TripKey) async {
        guard let details = tripDetails, details.key == key else { return }
        await details.load()
        guard details.showsOnBoardButton, !details.needsLocationIntro else { return }
        _ = await details.startRide(source: .departure)
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
        openTrip(ride.tripKey, on: route, source: .ride)
    }

    /// A notification tap: Trip details for its trip and service date, over the timeline of the alert's route and day, so
    /// closing the sheet shows the next trains; the Alerts tab for a past service date or a rule to review (rule 10).
    private func open(_ link: NotificationLink, source: TripOpenSource = .notification) async {
        switch link.target(today: ServiceDay(containing: clock.now)) {
        case .alerts:
            router.showAlerts()
        case .schedule:
            // A widget's header (TT-182): nothing over Schedule, its route at Today and Now; no stations, the tab only.
            router.dismissSheet()
            router.showSchedule()
            guard link.hasStations, let route = await link.route(stations: stations, saved: schedule.route) else { return }
            // A widget's route is not the rider's choice by hand: Automatic direction may still turn it (TT-234, D116).
            if schedule.route.map({ !$0.isSameDirection(as: route) }) ?? true {
                await schedule.show(route, chosen: .widgetRoute)
            }
            await schedule.backToNow()
        case .trip(let key):
            guard let route = await link.route(stations: stations, saved: schedule.route) else { return }
            router.showSchedule()
            // The sheet first; the timeline behind it follows without holding it up.
            openTrip(key, on: route, source: source)
            await showTrainRoute(route)
            // A service date before Schedule's Today (a late train's alert between 12:00 and 3:00 AM, D52) is not in the strip.
            if schedule.selectedDay != key.serviceDay, key.serviceDay >= schedule.today { await schedule.select(key.serviceDay) }
        }
    }

    /// The splash's mark begins to fade over Schedule (TT-227): Schedule's entrance plays, and whether its trains were
    /// already there is counted.
    private func splashLifts() {
        splashCovers = false
        Analytics.track(.launchSplashEnded(scheduleReady: schedule.content != .loading, full: LaunchMotion.pace == .full))
    }

    /// One train's link (a notification, the Live Activity, a widget's train row, "Pick a new train") puts its route on
    /// Schedule: Automatic direction keeps it as it keeps a choice by hand and ends this visit's look, also when the route
    /// already shows (TT-234, D116).
    private func showTrainRoute(_ route: Route) async {
        if schedule.route.map({ !$0.isSameDirection(as: route) }) ?? true {
            await schedule.show(route, chosen: .trainLink)
        } else {
            direction.chose(route, by: .trainLink)
        }
    }

    /// "Show trains" on first use: the rider's own choice.
    private func show(_ route: Route) {
        Task { await schedule.show(route) }
    }
}

#Preview {
    RootView()
}
