import Foundation
import Observation
import UIKit

/// The one-tap bell on each card and its toast (TT-141). A tap turns the card's alert on: the bell pops and waits at half
/// strength while the server stores it, then goes solid with "Alert on for the 7:32 AM train · Repeat" (TT-166); a second
/// tap turns it off ("Alert off").
///
/// One alert per card (TT-189, D70): the bell shows and changes the alert that covers its train on that day
/// (`AlertRules.alert(for:on:)`), so a repeating alert fills the bell on each of its days, and a tap never adds a second one.
///
/// Permission from the bell (TT-190, D72): the first tap ever is the request, with no sheet of ours first. The bell holds
/// while iOS asks; Allow turns the alert on, Don't Allow saves nothing. With notifications off a tap saves nothing either:
/// the bell shakes and the toast says "Notifications are off · Turn on", whose Turn on opens the app's page in iOS Settings;
/// back with notifications on, the bell that was tapped turns on.
@Observable @MainActor
final class AlertBellModel {
    /// The bell's faces (`BellFace`, TT-190): outline, the hold while iOS asks, waiting at half strength while the alert is
    /// saved (was Setting up; taps do nothing), filled, and crossed while notifications are off (a tap explains, never
    /// deletes).
    typealias Bell = BellFace

    /// The toast above the tab bar. A new one replaces the last and restarts its 2.5 s.
    struct AlertToast: Equatable, Identifiable {
        enum Kind: Equatable {
            /// "Alert on for the 7:32 AM train" with Repeat, named by the scheduled departure (D9).
            case on
            case off
            /// "Could not save" with Try again.
            case couldNotSave
            /// "Notifications are off" with Turn on: a bell tapped after Don't Allow, or with notifications off (TT-190).
            case notificationsOff
        }

        let id: Int
        let kind: Kind
        let trip: Trip
        let route: Route
    }

    /// The app's page in the Settings app, where notifications are turned back on (the toast's Turn on).
    static let notificationSettingsURL = URL(string: UIApplication.openNotificationSettingsURLString)!

    let rules: AlertRules
    private(set) var toast: AlertToast?
    /// Counts alerts turned on, for the light haptic.
    private(set) var enabledCount = 0
    /// Counts refusals (notifications off, or a save that failed), for the warning haptic (TT-190).
    private(set) var refusedCount = 0
    /// "Tap the bell on a train" for 5 s, after the Alerts tab's "Add alert" (TT-143).
    private(set) var showsHint = false
    /// The train whose bell asked iOS, while the dialog is up (TT-190).
    private(set) var asking: TripKey?
    /// The train whose alert is being saved after its tap: its bell waits, also before the save is in flight.
    private var saving: TripKey?
    /// Each train's refusals: its bell shakes on each one (TT-190).
    private var shakeCounts: [TripKey: Int] = [:]
    /// The bell whose toast's Turn on went to iOS Settings: it turns on when the app is back with notifications on.
    @ObservationIgnored private var turnsOnWhenBack: (trip: Trip, route: Route)?
    private let toastDuration: Duration
    private let hintDuration: Duration
    /// Between the bell's shake and the toast that explains it (the Motion board's Refused: 120 ms).
    private let refusalDelay: Duration
    /// After iOS's answer: until the app is active again and 0.15 s more, so the pop or the shake is seen (TT-190).
    private let afterPrompt: @MainActor () async -> Void
    /// Trains whose tap is being handled, so repeated taps send one request.
    @ObservationIgnored private var busy: Set<TripKey> = []
    @ObservationIgnored private var toastCount = 0
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var hintTask: Task<Void, Never>?

    /// A toast shows for 2.5 s (TT-166, the Motion board), the hint for 5 s. Tests pass no `refusalDelay` and an
    /// `afterPrompt` that returns at once.
    init(
        rules: AlertRules,
        toastDuration: Duration = .milliseconds(2500),
        hintDuration: Duration = .seconds(5),
        refusalDelay: Duration = .milliseconds(120),
        afterPrompt: @escaping @MainActor () async -> Void = AlertBellModel.waitUntilActive
    ) {
        self.rules = rules
        self.toastDuration = toastDuration
        self.hintDuration = hintDuration
        self.refusalDelay = refusalDelay
        self.afterPrompt = afterPrompt
    }

    /// The card's face (TT-189, TT-190). A rule paused on the Alerts tab (TT-143) or by the bell sends nothing, so its bell
    /// is outlined; one that is switched on but cannot reach the rider is crossed.
    func bell(for trip: Trip, on route: Route) -> Bell {
        if asking == trip.key { return .asking }
        if saving == trip.key { return .waiting }
        guard let rule = rules.alert(for: trip, on: route), !rule.paused else { return .off }
        return switch rules.state(of: rule) {
        case .on: .on
        case .settingUp: .waiting
        case .notificationsOff: .crossed
        case .couldNotSave, .reviewNeeded: .off
        }
    }

    /// How many times this train's bell has shaken: it shakes again each time the number grows.
    func shakes(for trip: Trip) -> Int {
        shakeCounts[trip.key] ?? 0
    }

    /// Turns the card's alert off or on (TT-189): an alert that is on goes off (a one-day alert is deleted, a repeating one
    /// is switched off and keeps its days); one that is off, paused or not saved is switched on again. With no alert on
    /// the card, a repeating alert for the same usual train takes this day too, else a new This-trip alert is made.
    /// Turning on asks for permission first (`mayAlert`, TT-190).
    func tap(_ trip: Trip, on route: Route) async {
        guard !busy.contains(trip.key) else { return }
        busy.insert(trip.key)
        defer { busy.remove(trip.key) }

        if let existing = rules.alert(for: trip, on: route) {
            switch rules.state(of: existing) {
            case .settingUp:
                return
            case .on where !existing.paused:
                await turnOff(existing)
                show(.off, trip: trip, route: route)
                return
            case .on, .notificationsOff, .couldNotSave, .reviewNeeded:
                break
            }
        }
        guard await mayAlert(trip, on: route) else { return }
        await turnOn(trip, on: route)
    }

    /// The permission rule (TT-190, D72), in this model so Trip details reuses it (TT-192): true while notifications are
    /// allowed. Not asked yet, iOS asks now, the train's bell holding until the app is active again. Refused, now or
    /// before, nothing is saved: the bell shakes with the warning haptic and the toast follows. A caller that gets true
    /// saves at once, in the same turn of the main actor, so the hold runs straight into the bell's wait.
    func mayAlert(_ trip: Trip, on route: Route) async -> Bool {
        await rules.refreshPermission()
        if rules.permission == .notAsked {
            asking = trip.key
            await rules.requestPermission()
            await afterPrompt()
            asking = nil
        }
        guard rules.permission == .allowed else {
            await refuse(.notificationsOff, trip: trip, route: route)
            return false
        }
        return true
    }

    /// The toast's Turn on: the toast goes and the bell is remembered, so it turns on when the rider comes back from iOS
    /// Settings with notifications on (`cameBack()`). The view opens `notificationSettingsURL`.
    func turnOnInSettings() {
        guard let toast, toast.kind == .notificationsOff else { return }
        turnsOnWhenBack = (toast.trip, toast.route)
        dismissToast()
    }

    /// The app is active again: the bell whose Turn on went to iOS Settings turns on if notifications are now on, and is
    /// forgotten either way. RootView calls it on every return to the foreground.
    func cameBack() async {
        guard let back = turnsOnWhenBack else { return }
        turnsOnWhenBack = nil
        await rules.refreshPermission()
        guard rules.permission == .allowed, bell(for: back.trip, on: back.route) == .off else { return }
        await tap(back.trip, on: back.route)
    }

    /// The toast's Repeat: the setup sheet on Repeat for the same train.
    func repeatRequest() -> AlertSetupRequest? {
        guard let toast else { return nil }
        dismissToast()
        return AlertSetupRequest(route: toast.route, trip: toast.trip, kind: .repeating)
    }

    /// The hint the Alerts tab's "Add alert" leaves on Schedule, for 5 s.
    func showHint() {
        showsHint = true
        hintTask?.cancel()
        let duration = hintDuration
        hintTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self else { return }
            self.showsHint = false
        }
    }

    func dismissToast() {
        hideTask?.cancel()
        toast = nil
    }

    /// Waits until the app is active again after the iOS dialog, then 0.15 s, so the bell finishes where the rider sees it
    /// (the Motion board's First tap ever).
    static func waitUntilActive() async {
        while UIApplication.shared.applicationState != .active {
            try? await Task.sleep(for: .milliseconds(50))
        }
        try? await Task.sleep(for: .milliseconds(150))
    }

    // MARK: Private

    /// Switches the card's alert on, the bell waiting at half strength until the server has it.
    private func turnOn(_ trip: Trip, on route: Route) async {
        var rule = rules.alert(for: trip, on: route) ?? newAlert(for: trip, on: route)
        rule.paused = false
        saving = trip.key
        await rules.save(rule)
        saving = nil
        switch rules.state(of: rule) {
        case .on:
            enabledCount += 1
            show(.on, trip: trip, route: route)
        case .couldNotSave:
            // Nothing half-kept: the outline bell shakes and the toast offers Try again.
            await refuse(.couldNotSave, trip: trip, route: route)
        case .notificationsOff:
            // Turned off in iOS Settings while it saved.
            await refuse(.notificationsOff, trip: trip, route: route)
        case .settingUp, .reviewNeeded:
            dismissToast()
        }
    }

    /// A card with no alert (TT-189): the repeating alert for the same usual train takes this day too, so the train keeps
    /// one alert; otherwise a new This-trip alert.
    private func newAlert(for trip: Trip, on route: Route) -> AlertRule {
        guard var usual = rules.usualAlert(for: trip, on: route) else { return AlertRule(kind: .thisTrip, trip: trip, route: route) }
        usual.weekdays = Set(usual.weekdays).union([trip.key.serviceDay.isoWeekday]).sorted()
        return usual
    }

    /// Off keeps what you set up (TT-189): a one-day alert has nothing to keep and is deleted; a repeating one is switched
    /// off with its days, so the bell or its switch brings it back.
    private func turnOff(_ rule: AlertRule) async {
        switch rule.kind {
        case .thisTrip:
            await rules.delete(rule.id)
        case .repeating:
            var paused = rule
            paused.paused = true
            await rules.save(paused)
        }
    }

    /// The bell shakes with the warning haptic and the toast says why 120 ms later (the Motion board's Refused).
    private func refuse(_ kind: AlertToast.Kind, trip: Trip, route: Route) async {
        shakeCounts[trip.key, default: 0] += 1
        refusedCount += 1
        dismissToast()
        if refusalDelay > .zero { try? await Task.sleep(for: refusalDelay) }
        show(kind, trip: trip, route: route)
    }

    private func show(_ kind: AlertToast.Kind, trip: Trip, route: Route) {
        toastCount += 1
        let id = toastCount
        toast = AlertToast(id: id, kind: kind, trip: trip, route: route)
        hideTask?.cancel()
        let duration = toastDuration
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self, self.toast?.id == id else { return }
            self.toast = nil
        }
    }
}
