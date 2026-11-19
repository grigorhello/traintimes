import Observation

enum AppTab: Hashable {
    case schedule, alerts, settings
}

/// Everything that opens as a native `.sheet`, so the timetable is always one dismiss away.
enum AppSheet: String, Identifiable {
    /// `detectOffer`: "Detect my train next time?", once, after the first completed ride (TT-176).
    case tripDetails, lineNotices, detectOffer
    var id: String { rawValue }
}

/// App-wide navigation state: selected tab, the one presented sheet and the Alerts tab dot.
@Observable @MainActor
final class AppRouter {
    var selectedTab: AppTab = .schedule
    var presentedSheet: AppSheet?
    /// Accent dot on the Alerts tab icon (TT-143 sets it); never a number.
    var showsAlertsDot = false
    /// A tapped notification RootView has not opened yet (TT-144). A tap that launches the app arrives before the view.
    var pendingLink: NotificationLink?
    /// Where the pending link came from: a notification, or a `traintimes://` link (a widget, TT-182).
    private(set) var pendingLinkSource: TripOpenSource = .notification
    /// The background question's answer (TT-176), until RootView acts on it with the app in front: Start On board rides
    /// the train, a tap on the notification opens its Trip details.
    var detectedTrain: DetectedTrainRequest?

    /// The Settings tab (D48).
    func openSettings() {
        selectedTab = .settings
    }

    func present(_ sheet: AppSheet) {
        presentedSheet = sheet
    }

    func dismissSheet() {
        presentedSheet = nil
    }

    /// The pending link came from Yes on the departure question's notification (TT-231): its ride starts too.
    var pendingLinkBoards = false

    /// A notification tap, or a widget's link; RootView opens it once it is on screen. `boards`: Yes on the departure
    /// question.
    func open(_ link: NotificationLink, source: TripOpenSource = .notification, boards: Bool = false) {
        pendingLinkSource = source
        pendingLinkBoards = boards
        pendingLink = link
    }

    /// Start On board, or a tap, on the background question; RootView opens it once the app is active.
    func open(_ train: DetectedTrain, startsRide: Bool) {
        detectedTrain = DetectedTrainRequest(train: train, startsRide: startsRide)
    }

    /// The Alerts tab with nothing over it: a past trip's notification, or a rule that needs review (TT-144).
    func showAlerts() {
        presentedSheet = nil
        selectedTab = .alerts
    }

    /// The Schedule timeline, for a trip opened from a notification or the Alerts tab's "Add alert".
    func showSchedule() {
        selectedTab = .schedule
    }
}

/// The background question's answer, as the notification's handler hands it over (TT-176).
struct DetectedTrainRequest: Equatable, Sendable {
    let train: DetectedTrain
    /// Start On board; false for a tap on the notification.
    let startsRide: Bool
}
