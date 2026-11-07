import SwiftUI

/// Two tabs, Schedule and Alerts, and nothing else at the top level. Launch lands on Schedule with no prompt.
/// Applies the Appearance setting and puts the one time formatter in the environment (TT-105).
struct RootView: View {
    @State private var router: AppRouter
    @State private var schedule: ScheduleViewModel
    @State private var settings: AppSettings
    @State private var settingsModel: SettingsViewModel
    @Environment(\.colorScheme) private var colorScheme

    init(router: AppRouter = AppRouter(), schedule: ScheduleViewModel? = nil, settings: AppSettings = AppSettings()) {
        _router = State(initialValue: router)
        _schedule = State(initialValue: schedule ?? .fixtures())
        _settings = State(initialValue: settings)
        _settingsModel = State(initialValue: SettingsViewModel(settings: settings))
        TabBarStyle.apply()
    }

    var body: some View {
        TabView(selection: $router.selectedTab) {
            NavigationStack(path: $router.schedulePath) {
                ScheduleView(
                    viewModel: schedule,
                    onSettings: { router.openSettings() },
                    onEditRoute: { router.present(.routeEdit) }
                )
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
            SheetPlaceholder(sheet: sheet)
        }
        .environment(\.timeFormatter, settings.timeFormatter)
        .preferredColorScheme(settings.appearance.colorScheme)
    }
}

/// Stand-in until the sheets land: route editing (TT-120), station search (TT-121), trip details (TT-118),
/// alert setup (TT-141) and line notices (TT-132).
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
