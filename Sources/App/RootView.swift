import SwiftUI

/// Two tabs, Schedule and Alerts, and nothing else at the top level. Launch lands on Schedule with no prompt: the
/// remembered route, or the route form on first use (TT-120). Favourites are shared by the Schedule star and the route form
/// (TT-122). Applies the Appearance setting and puts the one time formatter in the environment (TT-105).
struct RootView: View {
    @State private var router: AppRouter
    @State private var schedule: ScheduleViewModel
    @State private var settings: AppSettings
    @State private var settingsModel: SettingsViewModel
    /// The first-use form, replaced by a prefilled one each time the route sheet opens.
    @State private var routeForm: RouteFormViewModel
    /// The trip the details sheet shows, set each time a card is tapped (TT-118).
    @State private var tripDetails: TripDetailsViewModel?
    private let stations: any StationRepository
    private let repository: any ScheduleRepository
    private let clock: any AppClock
    @Environment(\.colorScheme) private var colorScheme

    init(
        router: AppRouter = AppRouter(),
        schedule: ScheduleViewModel? = nil,
        settings: AppSettings = AppSettings(),
        dependencies: ScheduleDependencies = .fixtures(),
        routeStore: any RouteStoring = UserDefaultsRouteStore(),
        favourites: Favourites = Favourites()
    ) {
        let schedule = schedule ?? ScheduleViewModel(
            route: routeStore.route, repository: dependencies.repository, clock: dependencies.clock, routeStore: routeStore,
            favourites: favourites
        )
        _router = State(initialValue: router)
        _schedule = State(initialValue: schedule)
        _settings = State(initialValue: settings)
        _settingsModel = State(initialValue: SettingsViewModel(settings: settings))
        _routeForm = State(
            initialValue: RouteFormViewModel(route: schedule.route, repository: dependencies.stations, favourites: schedule.favourites)
        )
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
                            onOpenTrip: { openTrip($0) }
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
                    TripDetailsView(viewModel: tripDetails, onAlert: { router.present(.alertSetup) })
                }
            default:
                SheetPlaceholder(sheet: sheet)
            }
        }
        // The first route saved on device, with a light haptic (TT-120).
        .sensoryFeedback(.impact(weight: .light), trigger: schedule.route) { old, new in old == nil && new != nil }
        .environment(\.timeFormatter, settings.timeFormatter)
        .preferredColorScheme(settings.appearance.colorScheme)
    }

    /// The prefilled route sheet; from the star at three favourites it opens with Manage favourites on (TT-122).
    private func editRoute(managingFavourites: Bool = false) {
        routeForm = RouteFormViewModel(
            route: schedule.route, repository: stations, favourites: schedule.favourites, isManagingFavourites: managingFavourites
        )
        router.present(.routeEdit)
    }

    private func openTrip(_ key: TripKey) {
        guard let route = schedule.route else { return }
        tripDetails = TripDetailsViewModel(route: route, key: key, repository: repository, clock: clock)
        router.present(.tripDetails)
    }

    private func show(_ route: Route) {
        router.dismissSheet()
        Task { await schedule.show(route) }
    }
}

/// Stand-in until the sheets land: station search (TT-121), alert setup (TT-141) and line notices (TT-132).
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
