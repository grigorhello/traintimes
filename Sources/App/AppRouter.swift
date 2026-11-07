import Observation

enum AppTab: Hashable {
    case schedule, alerts
}

/// Screens pushed on the Schedule stack.
enum ScheduleRoute: Hashable {
    case settings
}

/// Everything that opens as a native `.sheet`, so the timetable is always one dismiss away.
enum AppSheet: String, Identifiable {
    case routeEdit, stationSearch, tripDetails, alertSetup, lineNotices
    var id: String { rawValue }
}

/// App-wide navigation state: selected tab, the Schedule stack, the one presented sheet and the Alerts tab dot.
@Observable @MainActor
final class AppRouter {
    var selectedTab: AppTab = .schedule
    var schedulePath: [ScheduleRoute] = []
    var presentedSheet: AppSheet?
    /// Accent dot on the Alerts tab icon (TT-143 sets it); never a number.
    var showsAlertsDot = false
    /// A tapped notification RootView has not opened yet (TT-144). A tap that launches the app arrives before the view.
    var pendingLink: NotificationLink?

    func openSettings() {
        selectedTab = .schedule
        schedulePath = [.settings]
    }

    func present(_ sheet: AppSheet) {
        presentedSheet = sheet
    }

    func dismissSheet() {
        presentedSheet = nil
    }

    /// A notification tap; RootView opens it once it is on screen.
    func open(_ link: NotificationLink) {
        pendingLink = link
    }

    /// The Alerts tab with nothing over it: a past trip's notification, or a rule that needs review (TT-144).
    func showAlerts() {
        presentedSheet = nil
        selectedTab = .alerts
    }

    /// The Schedule timeline with nothing pushed over it, for a trip opened from a notification.
    func showSchedule() {
        schedulePath = []
        selectedTab = .schedule
    }
}
