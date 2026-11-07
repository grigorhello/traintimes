import SwiftUI

/// Two tabs, Schedule and Alerts, and nothing else at the top level. Launch lands on Schedule with no prompt: the
/// remembered route, or the route form on first use (TT-120). Applies the Appearance setting and puts the one time
/// formatter in the environment (TT-105).
struct RootView: View {
    @State private var router: AppRouter
    @State private var schedule: ScheduleViewModel
    @State private var settings: AppSettings
    @State private var settingsModel: SettingsViewModel
    /// The first-use form, replaced by a prefilled one each time the route sheet opens.
    @State private var routeForm: RouteFormViewModel
    private let stations: any StationRepository
    @Environment(\.colorScheme) private var colorScheme

    init(
        router: AppRouter = AppRouter(),
        schedule: ScheduleViewModel? = nil,
        settings: AppSettings = AppSettings(),
        dependencies: ScheduleDependencies = .fixtures(),
        routeStore: any RouteStoring = UserDefaultsRouteStore()
    ) {
        let schedule = schedule ?? ScheduleViewModel(
            route: routeStore.route, repository: dependencies.repository, clock: dependencies.clock, routeStore: routeStore
        )
        _router = State(initialValue: router)
        _schedule = State(initialValue: schedule)
        _settings = State(initialValue: settings)
        _settingsModel = State(initialValue: SettingsViewModel(settings: settings))
        _routeForm = State(initialValue: RouteFormViewModel(route: schedule.route, repository: dependencies.stations))
        stations = dependencies.stations
        TabBarStyle.apply()
    }

    var body: some View {
        TabView(selection: $router.selectedTab) {
            NavigationStack(path: $router.schedulePath) {
                Group {
                    if schedule.route == nil {
                        RouteFormView(viewModel: routeForm, onSettings: { router.openSettings() }, onShowTrains: { show($0) })
                    } else {
                        ScheduleView(viewModel: schedule, onSettings: { router.openSettings() }, onEditRoute: { editRoute() })
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
            default:
                SheetPlaceholder(sheet: sheet)
            }
        }
        // The first route saved on device, with a light haptic (TT-120).
        .sensoryFeedback(.impact(weight: .light), trigger: schedule.route) { old, new in old == nil && new != nil }
        .environment(\.timeFormatter, settings.timeFormatter)
        .preferredColorScheme(settings.appearance.colorScheme)
    }

    private func editRoute() {
        routeForm = RouteFormViewModel(route: schedule.route, repository: stations)
        router.present(.routeEdit)
    }

    private func show(_ route: Route) {
        router.dismissSheet()
        Task { await schedule.show(route) }
    }
}

/// Stand-in until the sheets land: station search (TT-121), trip details (TT-118), alert setup (TT-141) and
/// line notices (TT-132).
private struct SheetPlaceholder: View {
    let sheet: AppSheet

    var body: some View {
        TTColor.canvas
            .ignoresSafeArea()
            .accessibilityIdentifier("sheet.\(sheet.rawValue)")
            .presentationDragIndicator(.visible)
    }
}

#Preview {
    RootView()
}
