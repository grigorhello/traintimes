import Foundation
import Observation

/// The one-tap bell on each card and its glass capsule (TT-141, TT-191). With notifications allowed, a tap turns the card's
/// alert on; once it is saved the bell fills and the capsule says "Alert on · 7:32 AM" with Repeat. A second tap turns it
/// off ("Alert off · 7:32 AM" with Undo). Without permission, the tap opens the alert setup sheet instead (TT-142).
///
/// One alert per card (TT-189, D70): the bell shows and changes the alert that covers its train on that day
/// (`AlertRules.alert(for:on:)`), so a repeating alert fills the bell on each of its days, and a tap never adds a second one.
///
/// Nothing is half-kept (TT-191, D71): every change is saved through `AlertRules.commit(_:)`, so a new alert the server
/// cannot take leaves an outline bell and no alert, and a change it cannot take goes back to what was saved. The capsule is
/// the only place a failure shows ("Couldn't turn alert on · Try again"). Repeat makes the same alert repeat and grows the
/// capsule into the day panel, where every tile saves by itself.
@Observable @MainActor
final class AlertBellModel {
    enum Bell {
        case off
        /// The server has not confirmed the rule yet: the bell stays outlined and dimmed, and taps do nothing.
        case settingUp
        /// Filled in accent: the server stored the rule, the token is registered and notifications are allowed.
        case on
    }

    /// The glass capsule above the tab bar (TT-191, D71). One at a time: a new one takes the last one's place, its words
    /// cross-fading in, and restarts the time, 5 s with an action and 2.5 s without. Repeat grows it into the day panel,
    /// which stays until it is closed.
    struct Capsule: Equatable, Identifiable {
        enum Kind: Equatable {
            /// "Alert on · 7:32 AM" with Repeat; a repeating alert reads "Alert on · 7:32 AM, Mon to Fri", with no action.
            case on
            /// "Alert off · 7:32 AM" with Undo; a repeating alert, switched off on every day, reads "…, all days".
            case off
            /// "Couldn't turn alert on", "Couldn't change days" or "Couldn't turn alert off", with Try again.
            case failed(Failure)
            /// "Notifications are off" with Turn on, which opens the app's page in iOS Settings (TT-190 shows it).
            case notificationsOff
            /// "Tap the bell on a train", after the Alerts tab's "Add alert" (TT-143).
            case hint
        }

        enum Failure: Equatable {
            case turnOn
            case changeDays
            case turnOff
        }

        /// A new capsule has a new id.
        let id: Int
        let kind: Kind
        /// The train it speaks of, named by its scheduled departure (D9); nil for the hint.
        let trip: Trip?
        let route: Route?
        /// A repeating alert's days, which the words name; empty for a one-day alert.
        var repeats: [Int] = []
        /// The day panel: open while set, with the days lit. No day lit means that day only.
        var panelDays: [Int]?

        var isPanelOpen: Bool { panelDays != nil }

        /// Repeat (a one-day alert just turned on), Undo, Try again or Turn on.
        var hasAction: Bool {
            switch kind {
            case .on: repeats.isEmpty
            case .off, .failed, .notificationsOff: true
            case .hint: false
            }
        }
    }

    let rules: AlertRules
    private(set) var capsule: Capsule?
    /// Counts alerts turned on, for the light haptic.
    private(set) var enabledCount = 0
    /// Counts day tiles lit in the panel, for the selection haptic.
    private(set) var dayOnCount = 0
    private let actionDuration: Duration
    private let plainDuration: Duration
    private let hintDuration: Duration
    /// Trains whose tap is being handled, so repeated taps send one request.
    @ObservationIgnored private var busy: Set<TripKey> = []
    @ObservationIgnored private var capsuleCount = 0
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    /// What the capsule up offers: the alert Undo puts back, or the change Try again repeats.
    @ObservationIgnored private var undoRule: AlertRule?
    @ObservationIgnored private var retry: Retry?
    /// The alert the open day panel changes.
    @ObservationIgnored private var panelRuleID: AlertRule.ID?
    /// The latest days asked for in the panel, saved one change at a time by `daySaving`.
    @ObservationIgnored private var wanted: WantedDays?
    @ObservationIgnored private var daySaving: Task<Void, Never>?
    /// A one-day alert's delete on its way to the server: Undo waits for it, so its save lands after it.
    @ObservationIgnored private var offTask: Task<Void, Never>?

    private enum Retry {
        case turnOn(Trip, Route)
        case changeDays([Int], ruleID: AlertRule.ID, Trip, Route)
        case turnOff(Trip, Route)
    }

    private struct WantedDays: Equatable {
        let ruleID: AlertRule.ID
        let days: [Int]
        let trip: Trip
        let route: Route
    }

    /// A capsule with an action shows for 5 s, one without for 2.5 s (TT-191); the hint for 5 s.
    init(
        rules: AlertRules, actionDuration: Duration = .seconds(5), plainDuration: Duration = .milliseconds(2500),
        hintDuration: Duration = .seconds(5)
    ) {
        self.rules = rules
        self.actionDuration = actionDuration
        self.plainDuration = plainDuration
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
    /// the card, a repeating alert for the same usual train takes this day too, else a new This-trip alert is made. A bell
    /// tapped while the day panel is open closes it first. Returns the alert setup sheet to open when notifications are not
    /// allowed yet: on the first tap ever, or after the rider turned them off.
    func tap(_ trip: Trip, on route: Route) async -> AlertSetupRequest? {
        guard !busy.contains(trip.key) else { return nil }
        busy.insert(trip.key)
        defer { busy.remove(trip.key) }
        closePanel()

        let existing = rules.alert(for: trip, on: route)
        if let existing {
            switch rules.state(of: existing) {
            case .settingUp:
                return nil
            case .on where !existing.paused:
                await turnOff(existing, trip: trip, route: route)
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
        await turnOn(rule, trip: trip, route: route)
        return nil
    }

    // MARK: The capsule's actions

    /// Repeat on "Alert on" (TT-191): the same alert now repeats Mon to Fri (on a weekend train, that day alone) and the
    /// capsule grows into the day panel, which has no time limit.
    func repeatTapped() {
        guard var capsule, capsule.kind == .on, capsule.repeats.isEmpty, !capsule.isPanelOpen,
              let trip = capsule.trip, let route = capsule.route,
              let rule = rules.alert(for: trip, on: route), rule.kind == .thisTrip else { return }
        hideTask?.cancel()
        let days = AlertDays.repeatDays(for: trip.key.serviceDay)
        capsule.panelDays = days
        self.capsule = capsule
        panelRuleID = rule.id
        want(days, ruleID: rule.id, trip: trip, route: route)
    }

    /// A day tile: lit or not at once, then saved by itself. No day lit makes it an alert for the panel's train alone.
    func toggleDay(_ day: Int) {
        guard var capsule, var days = capsule.panelDays, let trip = capsule.trip, let route = capsule.route,
              let ruleID = panelRuleID else { return }
        if let index = days.firstIndex(of: day) {
            days.remove(at: index)
        } else {
            days = (days + [day]).sorted()
            dayOnCount += 1
        }
        capsule.panelDays = days
        self.capsule = capsule
        want(days, ruleID: ruleID, trip: trip, route: route)
    }

    /// The tick, a tap outside or a scroll: the panel leaves. Days still saving carry on.
    func closePanel() {
        guard capsule?.isPanelOpen == true else { return }
        dismissCapsule()
    }

    /// Undo on "Alert off": the alert back as it was, with the same id and days (TT-191).
    func undo() async {
        guard let capsule, capsule.kind == .off, let rule = undoRule, let trip = capsule.trip, let route = capsule.route,
              !busy.contains(trip.key) else { return }
        undoRule = nil
        busy.insert(trip.key)
        defer { busy.remove(trip.key) }
        if let offTask { await offTask.value }
        var back = rule
        back.paused = false
        await turnOn(back, trip: trip, route: route)
    }

    /// Try again on "Couldn't …": the same change once more. Returns the setup sheet when turning on needs permission.
    func tryAgain() async -> AlertSetupRequest? {
        guard let retry else { return nil }
        self.retry = nil
        switch retry {
        case let .turnOn(trip, route):
            guard !isWorking(trip, on: route) else { return dismiss() }
            return await tap(trip, on: route)
        case let .turnOff(trip, route):
            guard isWorking(trip, on: route) else { return dismiss() }
            return await tap(trip, on: route)
        case let .changeDays(days, ruleID, trip, route):
            hideTask?.cancel()
            wanted = WantedDays(ruleID: ruleID, days: days, trip: trip, route: route)
            guard await saveWantedDays(), let rule = rules.rules.first(where: { $0.id == ruleID }) else { return nil }
            show(.on, trip: trip, route: route, repeats: rule.kind == .repeating ? rule.weekdays : [])
            return nil
        }
    }

    /// A finger on the capsule holds it; lifted, its time starts again.
    func holdCapsule(_ holding: Bool) {
        guard let capsule, !capsule.isPanelOpen else { return }
        if holding {
            hideTask?.cancel()
        } else {
            scheduleHide(capsule)
        }
    }

    /// The hint the Alerts tab's "Add alert" leaves on Schedule, for 5 s.
    func showHint() {
        show(.hint, trip: nil, route: nil)
    }

    func dismissCapsule() {
        hideTask?.cancel()
        capsule = nil
        undoRule = nil
        retry = nil
        panelRuleID = nil
    }

    // MARK: Turning on and off

    /// A card with no alert (TT-189): the repeating alert for the same usual train takes this day too, so the train keeps
    /// one alert; otherwise a new This-trip alert.
    private func newAlert(for trip: Trip, on route: Route) -> AlertRule {
        guard var usual = rules.usualAlert(for: trip, on: route) else { return AlertRule(kind: .thisTrip, trip: trip, route: route) }
        usual.weekdays = Set(usual.weekdays).union([trip.key.serviceDay.isoWeekday]).sorted()
        return usual
    }

    /// Saves the alert switched on. A capsule already up stays through the wait, then the new one takes its place.
    private func turnOn(_ rule: AlertRule, trip: Trip, route: Route) async {
        hideTask?.cancel()
        guard await rules.commit(rule) else {
            show(.failed(.turnOn), trip: trip, route: route, retry: .turnOn(trip, route))
            return
        }
        guard let saved = rules.alert(for: trip, on: route), !saved.paused, rules.state(of: saved) == .on else {
            // Another save carries it and speaks for itself.
            if let capsule { scheduleHide(capsule) }
            return
        }
        enabledCount += 1
        show(.on, trip: trip, route: route, repeats: saved.kind == .repeating ? saved.weekdays : [])
    }

    /// Off keeps what you set up (TT-189): a one-day alert has nothing to keep and is deleted, at once on device (an
    /// unreachable server deletes it with the next call, so this never fails); a repeating one is switched off with its
    /// days, so the bell or its switch brings it back, and goes back on if the server cannot take that.
    private func turnOff(_ rule: AlertRule, trip: Trip, route: Route) async {
        hideTask?.cancel()
        switch rule.kind {
        case .thisTrip:
            // Gone on device now; the bell and Undo answer while the server's delete is on its way, and Undo waits for it.
            offTask = rules.deleteInBackground(rule.id)
            show(.off, trip: trip, route: route, undo: rule)
        case .repeating:
            var off = rule
            off.paused = true
            if await rules.commit(off) {
                show(.off, trip: trip, route: route, repeats: rule.weekdays, undo: rule)
            } else {
                show(.failed(.turnOff), trip: trip, route: route, retry: .turnOff(trip, route))
            }
        }
    }

    /// The train's alert is switched on and On.
    private func isWorking(_ trip: Trip, on route: Route) -> Bool {
        guard let alert = rules.alert(for: trip, on: route) else { return false }
        return !alert.paused && rules.state(of: alert) == .on
    }

    private func dismiss() -> AlertSetupRequest? {
        dismissCapsule()
        return nil
    }

    // MARK: Days

    private func want(_ days: [Int], ruleID: AlertRule.ID, trip: Trip, route: Route) {
        wanted = WantedDays(ruleID: ruleID, days: days, trip: trip, route: route)
        guard daySaving == nil else { return }
        daySaving = Task { [weak self] in
            _ = await self?.saveWantedDays()
            self?.daySaving = nil
        }
    }

    /// Saves the latest days asked for, one change at a time, until the alert has them. A change the server cannot take
    /// goes back to what was saved, and "Couldn't change days · Try again" takes the panel's place. True when saved.
    @discardableResult
    private func saveWantedDays() async -> Bool {
        while let asked = wanted {
            guard let rule = rules.rules.first(where: { $0.id == asked.ruleID }), !Self.rule(rule, has: asked.days, for: asked.trip) else {
                break
            }
            let candidate = AlertRule(
                id: rule.id, kind: asked.days.isEmpty ? .thisTrip : .repeating, trip: asked.trip, route: asked.route,
                weekdays: asked.days, paused: rule.paused
            )
            guard await rules.commit(candidate) else {
                wanted = nil
                show(
                    .failed(.changeDays), trip: asked.trip, route: asked.route,
                    retry: .changeDays(asked.days, ruleID: asked.ruleID, asked.trip, asked.route)
                )
                return false
            }
            // Nothing newer was asked while it saved.
            if wanted == asked { break }
        }
        wanted = nil
        return true
    }

    /// The alert repeats on exactly these days, or with none is the one-day alert for this train.
    private static func rule(_ rule: AlertRule, has days: [Int], for trip: Trip) -> Bool {
        days.isEmpty ? rule.kind == .thisTrip && rule.trip == trip.key : rule.kind == .repeating && rule.weekdays == days.sorted()
    }

    // MARK: Showing

    private func show(
        _ kind: Capsule.Kind, trip: Trip?, route: Route?, repeats: [Int] = [], undo: AlertRule? = nil, retry: Retry? = nil
    ) {
        capsuleCount += 1
        let next = Capsule(id: capsuleCount, kind: kind, trip: trip, route: route, repeats: repeats)
        capsule = next
        undoRule = undo
        self.retry = retry
        panelRuleID = nil
        scheduleHide(next)
    }

    private func scheduleHide(_ capsule: Capsule) {
        hideTask?.cancel()
        let duration = capsule.kind == .hint ? hintDuration : capsule.hasAction ? actionDuration : plainDuration
        let id = capsule.id
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self, let shown = self.capsule, shown.id == id, !shown.isPanelOpen else { return }
            self.dismissCapsule()
        }
    }
}

// MARK: Words

extension AlertBellModel.Capsule {
    /// The capsule's one line (the spec board's Words). A one-day alert for a train on another day than `today` names the
    /// day: "Alert on · Fri 7:32 AM".
    func words(_ formatter: some TimeFormatting, today: ServiceDay) -> String {
        let time = trip.map { formatter.time($0.scheduledDeparture) } ?? ""
        switch kind {
        case .on where !repeats.isEmpty:
            return String(format: String(localized: "capsule.on_repeating"), time, AlertDays.summary(of: repeats) ?? "")
        case .on:
            guard let day = trip?.key.serviceDay, day != today else { return String(format: String(localized: "capsule.on"), time) }
            let dayTime = String(format: String(localized: "capsule.day_time"), day.weekdayShort, time)
            return String(format: String(localized: "capsule.on"), dayTime)
        case .off where !repeats.isEmpty:
            return String(format: String(localized: "capsule.off_all_days"), time)
        case .off:
            return String(format: String(localized: "capsule.off"), time)
        case .failed(.turnOn):
            return String(localized: "capsule.failed_on")
        case .failed(.changeDays):
            return String(localized: "capsule.failed_days")
        case .failed(.turnOff):
            return String(localized: "capsule.failed_off")
        case .notificationsOff:
            return String(localized: "capsule.notifications_off")
        case .hint:
            return String(localized: "alerts.add_hint")
        }
    }

    /// The day panel's line: "7:32 AM · Mon to Fri"; with no day lit, "7:32 AM · Today only" (Tomorrow only, Fri 6 only).
    func panelWords(_ formatter: some TimeFormatting, today: ServiceDay) -> String {
        guard let trip else { return "" }
        let day = trip.key.serviceDay
        let days = AlertDays.summary(of: panelDays ?? []) ?? {
            if day == today { return String(localized: "alerts.today_only") }
            if day == today.adding(days: 1) { return String(localized: "alert.days.tomorrow_only") }
            return String(format: String(localized: "alert.days.date_only"), day.weekdayShort, day.day)
        }()
        return String(format: String(localized: "capsule.panel"), formatter.time(trip.scheduledDeparture), days)
    }

    /// The action's words: Repeat, Undo, Try again or Turn on.
    var actionKey: String? {
        guard hasAction else { return nil }
        return switch kind {
        case .on: "alert.repeat"
        case .off: "button.undo"
        case .failed: "button.try_again"
        case .notificationsOff: "capsule.turn_on"
        case .hint: nil
        }
    }
}
