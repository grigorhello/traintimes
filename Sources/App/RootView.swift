import SwiftUI

/// Two tabs, Schedule and Alerts, and nothing else at the top level. Launch lands on Schedule with no prompt.
struct RootView: View {
    @State private var router: AppRouter
    @State private var schedule: ScheduleViewModel
    @Environment(\.colorScheme) private var colorScheme

    init(router: AppRouter = AppRouter(), schedule: ScheduleViewModel? = nil) {
        _router = State(initialValue: router)
        _schedule = State(initialValue: schedule ?? .fixtures())
        TabBarStyle.apply()
    }

    var body: some View {
        TabView(selection: $router.selectedTab) {
            NavigationStack(path: $router.schedulePath) {
                ScheduleView(
                    viewModel: schedule,
                    onSettings: { router.openSettings() },
                    onEditRoute: { router.present(.routeEdit) },
                    onOpenTrip: { _ in router.present(.tripDetails) }
                )
                    .navigationDestination(for: ScheduleRoute.self) { route in
                        switch route {
                        case .settings: SettingsView()
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
    }
}

/// Stand-in until the sheets land: route editing (TT-120), station search (TT-121), trip details (TT-118),
/// alert setup (TT-141) and line notices (TT-132).
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
