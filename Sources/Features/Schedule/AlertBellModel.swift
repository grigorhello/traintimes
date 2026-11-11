import Foundation
import Observation

/// The one-tap bell on each card and its toast (TT-141). With notifications allowed, a tap arms a This-trip alert at once:
/// "Setting up" while the server stores it, then the filled bell and "Alert on for the 7:32 AM train · Repeat" for 2.5 s
/// (TT-166); a second tap turns it off ("Alert off"). Without permission, the tap opens the alert setup sheet instead (TT-142).
///
/// One alert per card (TT-189, D70): the bell shows and changes the alert that covers its train on that day
/// (`AlertRules.alert(for:on:)`), so a repeating alert fills the bell on each of its days, and a tap never adds a second one.
@Observable @MainActor
final class AlertBellModel {
    enum Bell {
        case off
        /// The server has not confirmed the rule yet: the bell stays outlined and dimmed, and taps do nothing.
        case settingUp
        /// Filled in accent: the server stored the rule, the token is registered and notifications are allowed.
        case on
    }

    /// The toast above the tab bar. A new one replaces the last and restarts its 2.5 s.
    struct AlertToast: Equatable, Identifiable {
        enum Kind: Equatable {
            case settingUp
            /// "Alert on for the 7:32 AM train" with Repeat, named by the scheduled departure (D9).
            case on
            case off
            /// "Could not save" with Try again.
            case couldNotSave
        }

        let id: Int
        let kind: Kind
        let trip: Trip
        let route: Route
    }

    let rules: AlertRules
    private(set) var toast: AlertToast?
    /// Counts alerts turned on, for the light haptic.
    private(set) var enabledCount = 0
    /// "Tap the bell on a train" for 5 s, after the Alerts tab's "Add alert" (TT-143).
    private(set) var showsHint = false
    private let toastDuration: Duration
    private let hintDuration: Duration
    /// Trains whose tap is being handled, so repeated taps send one request.
    @ObservationIgnored private var busy: Set<TripKey> = []
    @ObservationIgnored private var toastCount = 0
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var hintTask: Task<Void, Never>?

    /// A toast shows for 2.5 s (TT-166, the Motion board), the hint for 5 s.
    init(rules: AlertRules, toastDuration: Duration = .milliseconds(2500), hintDuration: Duration = .seconds(5)) {
        self.rules = rules
        self.toastDuration = toastDuration
        self.hintDuration = hintDuration
    }

    /// The card's alert (TT-189). A rule paused on the Alerts tab (TT-143) or by the bell sends nothing, so its bell is outlined.
    func bell(for trip: Trip, on route: Route) -> Bell {
        guard let rule = rules.alert(for: trip, on: route), !rule.paused else { return .off }
        return switch rules.state(of: rule) {
        case .on: .on
        case .settingUp: .settingUp
        case .notificationsOff, .couldNotSave, .reviewNeeded: .off
        }
    }

    /// Turns the card's alert off or on (TT-189): an alert that is on goes off (a one-day alert is deleted, a repeating one
    /// is switched off and keeps its days); one that is off, paused or not saved is switched on again. With no alert on
    /// the card, a repeating alert for the same usual train takes this day too, else a new This-trip alert is made. Returns
    /// the alert setup sheet to open when notifications are not allowed yet: on the first tap ever, or after the rider
    /// turned them off.
    func tap(_ trip: Trip, on route: Route) async -> AlertSetupRequest? {
        guard !busy.contains(trip.key) else { return nil }
        busy.insert(trip.key)
        defer { busy.remove(trip.key) }

        let existing = rules.alert(for: trip, on: route)
        if let existing {
            switch rules.state(of: existing) {
            case .settingUp:
                return nil
            case .on where !existing.paused:
                await turnOff(existing)
                show(.off, trip: trip, route: route)
                return nil
            case .on, .notificationsOff, .couldNotSave, .reviewNeeded:
                break
            }
        }
        await rules.refreshPermission()
        guard rules.permission == .allowed else {
            return AlertSetupRequest(route: route, trip: trip, kind: existing?.kind ?? .thisTrip)
        }
        var rule = existing ?? newAlert(for: trip, on: route)
        rule.paused = false
        show(.settingUp, trip: trip, route: route)
        await rules.save(rule)
        switch rules.state(of: rule) {
        case .on:
            enabledCount += 1
            show(.on, trip: trip, route: route)
        case .couldNotSave:
            show(.couldNotSave, trip: trip, route: route)
        case .settingUp, .notificationsOff, .reviewNeeded:
            dismissToast()
        }
        return nil
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

    func dismissToast() {
        hideTask?.cancel()
        toast = nil
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
