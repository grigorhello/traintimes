import SwiftUI

/// Two tabs, Schedule and Alerts, and nothing else at the top level. Launch lands on Schedule with no prompt: the
/// remembered route, or the route form on first use (TT-120). Favourites are shared by the Schedule star and the route form
/// (TT-122). Applies the Appearance setting and puts the one time formatter in the environment (TT-105). Opens the trip or
/// the Alerts tab for a tapped notification (TT-144).
struct RootView: View {
    @State private var router: AppRouter
    @State private var schedule: ScheduleViewModel
    @State private var settings: AppSettings
    @State private var settingsModel: SettingsViewModel
    /// The first-use form, replaced by a prefilled one each time the route sheet opens.
    @State private var routeForm: RouteFormViewModel
    /// The trip the details sheet shows, set each time a card is tapped (TT-118).
    @State private var tripDetails: TripDetailsViewModel?
    /// The alert rules (TT-141), shared by the bells, the alert setup sheet, the Alerts tab and the watched-trip strip.
    @State private var alerts: AlertRules
    @State private var bells: AlertBellModel
    /// The alert setup sheet for a train (TT-142), made each time it opens.
    @State private var alertSetup: AlertSetupViewModel?
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
        favourites: Favourites = Favourites(),
        dismissedNotices: DismissedNotices = DismissedNotices(),
        alertDependencies: AlertDependencies = .app(),
        bells: AlertBellModel? = nil
    ) {
        let bells = bells ?? AlertBellModel(rules: alertDependencies.rules(settings: settings))
        let schedule = schedule ?? ScheduleViewModel(
            route: routeStore.route, repository: dependencies.repository, clock: dependencies.clock, routeStore: routeStore,
            favourites: favourites, dismissedNotices: dismissedNotices, watchedTrips: bells.rules
        )
        _router = State(initialValue: router)
        _schedule = State(initialValue: schedule)
        _settings = State(initialValue: settings)
        // The alert rules' permission source, so a fixture run's `TT_NOTIFICATIONS` shows in Settings too (TT-142).
        _settingsModel = State(initialValue: SettingsViewModel(settings: settings, permissions: alertDependencies.permissions))
        _routeForm = State(
            initialValue: RouteFormViewModel(route: schedule.route, repository: dependencies.stations, favourites: schedule.favourites)
        )
        _alerts = State(initialValue: bells.rules)
        _bells = State(initialValue: bells)
        stations = dependencies.stations
        repository = dependencies.repository
        clock = dependencies.clock
        TabBarStyle.apply()
    }

    var body: some View {
        TabView(selection: $router.selectedTab) {
            NavigationStack(path: $router.schedulePath) {
                Group {
                    if schedule.route == nil {
                        RouteFormView(viewModel: routeForm, onSettings: { router.openSettings() }, onShowTrains: { show($0) })
                    } else {
                        ScheduleView(
                            viewModel: schedule,
                            onSettings: { router.openSettings() },
                            onEditRoute: { editRoute() },
                            onManageFavourites: { editRoute(managingFavourites: true) },
                            onOpenTrip: { openTrip($0) },
                            onOpenLineNotice: { router.present(.lineNotices) },
                            bells: bells,
                            onAlertSetup: { openAlertSetup($0) }
                        )
                    }
                }
                .navigationDestination(for: ScheduleRoute.self) { route in
                    switch route {
                    case .settings: SettingsView(viewModel: settingsModel)
                    }
                }
            }
            .tabItem {
                Label { Text("tab.schedule") } icon: {
                    TabBarStyle.icon("line.3.horizontal", isSelected: router.selectedTab == .schedule, colorScheme: colorScheme)
                }
            }
            .tag(AppTab.schedule)

            AlertsView()
                .tabItem {
                    Label { Text("tab.alerts") } icon: {
                        let isSelected = router.selectedTab == .alerts
                        TabBarStyle.icon(
                            isSelected ? "bell.fill" : "bell", isSelected: isSelected, showsDot: router.showsAlertsDot, colorScheme: colorScheme
                        )
                    }
                }
                .tag(AppTab.alerts)
        }
        .sheet(item: $router.presentedSheet) { sheet in
            switch sheet {
            case .routeEdit:
                RouteFormView(viewModel: routeForm, onShowTrains: { show($0) })
                    .presentationDragIndicator(.visible)
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
            default:
                SheetPlaceholder(sheet: sheet)
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
        .preferredColorScheme(settings.appearance.colorScheme)
        // Notifications may have been allowed or turned off in Settings while the app was away (TT-141).
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await alerts.refreshPermission()
        }
    }

    /// The alert setup sheet for a train (TT-142).
    private func openAlertSetup(_ request: AlertSetupRequest) {
        alertSetup = AlertSetupViewModel(request: request, rules: alerts)
        router.present(.alertSetup)
    }

    /// Trip details' "Alert me" or "Manage alert": the sheet for that train, on This trip.
    private func openAlertSetup(for details: TripDetailsViewModel) {
        guard let trip = details.departure?.trip else { return }
        openAlertSetup(AlertSetupRequest(route: details.route, trip: trip, kind: .thisTrip))
    }

    /// The prefilled route sheet; from the star at three favourites it opens with Manage favourites on (TT-122).
    private func editRoute(managingFavourites: Bool = false) {
        routeForm = RouteFormViewModel(
            route: schedule.route, repository: stations, favourites: schedule.favourites, isManagingFavourites: managingFavourites
        )
        router.present(.routeEdit)
    }

    private func openTrip(_ key: TripKey, on route: Route? = nil) {
        guard let route = route ?? schedule.route else { return }
        tripDetails = TripDetailsViewModel(
            route: route, key: key, repository: repository, clock: clock, hasAlert: alerts.thisTripRule(for: key, on: route) != nil
        )
        router.present(.tripDetails)
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
            if schedule.selectedDay != key.serviceDay { await schedule.select(key.serviceDay) }
        }
    }

    private func show(_ route: Route) {
        router.dismissSheet()
        Task { await schedule.show(route) }
    }
}

/// Stand-in for a sheet with no screen of its own yet (station search opens from the route form, TT-121).
private struct SheetPlaceholder: View {
    let sheet: AppSheet

    var body: some View {
        TTColor.canvas
            .ignoresSafeArea()
            .accessibilityElement()
            .accessibilityIdentifier("sheet.\(sheet.rawValue)")
            .presentationDragIndicator(.visible)
    }
}

#Preview {
    RootView()
}
