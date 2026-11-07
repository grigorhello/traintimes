import SwiftUI

/// Two tabs, Schedule and Alerts, and nothing else at the top level. Launch lands on Schedule with no prompt.
struct RootView: View {
    @State private var router: AppRouter

    init(router: AppRouter = AppRouter()) {
        _router = State(initialValue: router)
        TabBarStyle.apply()
    }

    var body: some View {
        TabView(selection: $router.selectedTab) {
            NavigationStack(path: $router.schedulePath) {
                ScheduleView { router.openSettings() }
                    .navigationDestination(for: ScheduleRoute.self) { route in
                        switch route {
                        case .settings: SettingsView()
                        }
                    }
            }
            .tabItem {
                Label { Text("tab.schedule") } icon: { TabBarStyle.scheduleIcon }
            }
            .tag(AppTab.schedule)

            AlertsView()
                .tabItem {
                    Label { Text("tab.alerts") } icon: {
                        TabBarStyle.alertsIcon(showsDot: router.showsAlertsDot, isSelected: router.selectedTab == .alerts)
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
            .accessibilityIdentifier("sheet.\(sheet.rawValue)")
            .presentationDragIndicator(.visible)
    }
}

#Preview {
    RootView()
}
