import SwiftUI

/// Three icon-only tabs, Schedule, Alerts and Settings (D48, D49), and nothing else at the top level. Tapping the Schedule
/// tab while it shows scrolls the timeline back to Now (D49). Launch lands on Schedule with no
/// prompt: the remembered route, or the route form on first use (TT-120). Recent routes are shared by Schedule, which
/// records them and lists them in its station picker (D48, D54). Applies the Appearance setting and puts the one time formatter in the
/// environment (TT-105). Opens the trip or the Alerts tab for a tapped notification (TT-144).
struct RootView: View {
    @State private var router: AppRouter
    @State private var schedule: ScheduleViewModel
    @State private var settings: AppSettings
    @State private var settingsModel: SettingsViewModel
    /// The first-use form; after the first route, Schedule makes its own picker each time a station is tapped (D54).
    @State private var routeForm: RouteFormViewModel
    /// The trip the details sheet shows, set each time a card is tapped (TT-118).
    @State private var tripDetails: TripDetailsViewModel?
    /// The alert rules (TT-141), shared by the bells, the alert setup sheet, the Alerts tab and the watched-trip strip.
    @State private var alerts: AlertRules
    @State private var bells: AlertBellModel
    /// The alert setup sheet for a train (TT-142), made each time it opens.
    @State private var alertSetup: AlertSetupViewModel?
    /// From opening the alert setup sheet until it is gone: a bell whose alert it changed pops after it (TT-166).
    @State private var holdsBellPop = false
    /// The Alerts tab (TT-143): the rules, recent updates and the saved route's line notices.
    @State private var alertsModel: AlertsViewModel
    /// On board (TT-172): the app's ride engine, or the demo ride's; shared by Trip details and the ride strip.
    @State private var onBoard: OnBoard
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
        ride: RideEngine? = nil
    ) {
        let bells = bells ?? AlertBellModel(
            rules: alertDependencies.rules(settings: settings), toastDuration: alertDependencies.bellToastDuration,
            hintDuration: alertDependencies.toastDuration
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
                settings: settings, permissions: alertDependencies.permissions, clock: dependencies.clock, alerts: bells.rules
            )
        )
        _routeForm = State(
            initialValue: RouteFormViewModel(route: nil, repository: dependencies.stations, recents: schedule.recents)
        )
        _alerts = State(initialValue: bells.rules)
        _bells = State(initialValue: bells)
        _alertsModel = State(
            initialValue: AlertsViewModel(
                rules: bells.rules,
                updates: alertUpdates ?? alertDependencies.updates(clock: dependencies.clock),
                notices: schedule,
                clock: dependencies.clock,
                toastDuration: alertDependencies.toastDuration
            )
        )
        _onBoard = State(initialValue: OnBoard(app: ride))
        stations = dependencies.stations
        repository = dependencies.repository
        clock = dependencies.clock
        TabBarStyle.apply()
    }

    var body: some View {
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
                        onAlertSetup: { openAlertSetup($0) },
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
                onAddAlert: { addAlert() },
                onOpenRule: { openAlertSetup($0) },
                onOpenUpdate: { link in Task { await open(link) } },
                onOpenLineNotice: { router.present(.lineNotices) }
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
        // A sheet that replaces another (Trip details, then Alert setup) dismisses the first while the second is up.
        .sheet(item: $router.presentedSheet, onDismiss: { if router.presentedSheet == nil { holdsBellPop = false } }) { sheet in
            switch sheet {
            case .tripDetails:
                if let tripDetails {
                    // A new trip while the sheet is up (a notification tap) gets a fresh view, so it loads (TT-144).
                    TripDetailsView(viewModel: tripDetails, onAlert: { openAlertSetup(for: tripDetails) })
                        .id(ObjectIdentifier(tripDetails))
                }
            case .alertSetup:
                if let alertSetup {
                    AlertSetupView(viewModel: alertSetup, onDelete: { router.dismissSheet() })
                        .id(ObjectIdentifier(alertSetup))
                }
            case .lineNotices:
                LineNoticeSheet(viewModel: schedule)
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
        .environment(\.holdsBellPop, holdsBellPop)
        // Demo trains (D49): the timeline shows the new scenario at once.
        .onChange(of: settings.demoTrains) { Task { await schedule.refresh() } }
        // Demo trains › Ride (TT-172) and › Departure (TT-177): the demo ride plays from 5:32 PM, the demo departure from
        // 5:01 PM, while chosen, in TestFlight and Debug builds only. Leaving Departure also stops the ride it handed over to.
        .task(id: demoTrains) {
            onBoard.setDemoDeparture(demoTrains == .departure)
            await onBoard.setDemo(demoTrains == .ride)
        }
        // Mock time (TT-158): the timeline starts again at the new present, as a relaunch would.
        .onChange(of: settings.mockTime) { Task { await schedule.restart() } }
        .preferredColorScheme(settings.appearance.colorScheme)
        // Notifications may have been allowed or turned off in Settings while the app was away (TT-141), a rule may need
        // review and notifications may have arrived (TT-143).
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await refreshAlerts()
        }
        // Opening the Alerts tab turns its dot off, and leaving it keeps it off for what the rider saw there (TT-143).
        .onChange(of: router.selectedTab) { old, tab in
            if old == .alerts { alertsModel.markReviewsSeen() }
            guard tab == .alerts else { return }
            router.showsAlertsDot = false
            alertsModel.markReviewsSeen()
            Task { await refreshAlerts() }
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

    /// The Alerts tab's "Add alert": the Schedule tab with "Tap the bell on a train" for 5 s.
    private func addAlert() {
        router.showSchedule()
        bells.showHint()
    }

    /// The alert setup sheet for a train (TT-142).
    private func openAlertSetup(_ request: AlertSetupRequest) {
        alertSetup = AlertSetupViewModel(request: request, rules: alerts)
        holdsBellPop = true
        router.present(.alertSetup)
    }

    /// Trip details' "Alert me" or "Manage alert": the sheet for that train, on its alert's kind (This trip when it has
    /// none), so Manage opens the train's one alert (TT-189).
    private func openAlertSetup(for details: TripDetailsViewModel) {
        // The demo departure's train is made up: its bell sets nothing.
        guard details.demoDeparture == nil, let trip = details.departure?.trip else { return }
        let kind = alerts.alert(for: trip, on: details.route)?.kind ?? .thisTrip
        openAlertSetup(AlertSetupRequest(route: details.route, trip: trip, kind: kind))
    }

    private func openTrip(_ key: TripKey, on route: Route? = nil) {
        guard let route = route ?? schedule.route else { return }
        tripDetails = TripDetailsViewModel(
            route: route, key: key, repository: repository, clock: clock, onBoard: onBoard, alerts: alerts
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

#Preview {
    RootView()
}
