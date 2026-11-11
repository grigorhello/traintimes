import Foundation
import Observation
import UIKit

/// The one-tap bell on each card and its glass capsule (TT-141, TT-191). A tap turns the card's alert on: the bell pops and
/// waits at half strength while the server stores it, then goes solid and the capsule says "Alert on · 7:32 AM" with Repeat.
/// A second tap turns it off ("Alert off · 7:32 AM" with Undo).
///
/// Permission from the bell (TT-190, D72): the first tap ever is the request, with no sheet of ours first. The bell holds
/// while iOS asks; Allow turns the alert on, Don't Allow saves nothing. With notifications off a tap saves nothing either:
/// the bell shakes and the capsule says "Notifications are off · Turn on", whose Turn on opens the app's page in iOS
/// Settings; back with notifications on, the bell that was tapped turns on.
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
    /// The bell's faces (`BellFace`, TT-190): outline, the hold while iOS asks, waiting at half strength while the alert is
    /// saved (taps do nothing), filled, and crossed while notifications are off (a tap explains, never deletes).
    typealias Bell = BellFace

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
            /// "Notifications are off" with Turn on, which opens the app's page in iOS Settings: a bell tapped after Don't
            /// Allow, or with notifications off (TT-190).
            case notificationsOff
            /// "Notifications are on", with the tick, once they are back on (TT-190 shows it).
            case notificationsOn
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
            case .notificationsOn, .hint: false
            }
        }
    }

    /// The app's page in the Settings app, where notifications are turned back on (the capsule's Turn on).
    static let notificationSettingsURL = URL(string: UIApplication.openNotificationSettingsURLString)!

    let rules: AlertRules
    private(set) var capsule: Capsule?
    /// Counts alerts turned on, for the light haptic.
    private(set) var enabledCount = 0
    /// Counts day tiles lit in the panel, for the selection haptic.
    private(set) var dayOnCount = 0
    /// Counts refusals (notifications off, or a save that failed), for the warning haptic (TT-190).
    private(set) var refusedCount = 0
    /// The train whose bell asked iOS, while the dialog is up (TT-190).
    private(set) var asking: TripKey?
    /// The train whose alert is being saved after its tap: its bell waits, also before the save is in flight.
    private var saving: TripKey?
    /// Each train's refusals: its bell shakes on each one (TT-190).
    private var shakeCounts: [TripKey: Int] = [:]
    /// The bell whose capsule's Turn on went to iOS Settings: it turns on when the app is back with notifications on.
    @ObservationIgnored private var turnsOnWhenBack: (trip: Trip, route: Route)?
    /// Between the bell's shake and the capsule that explains it (the Motion board's Refused: 120 ms).
    private let refusalDelay: Duration
    /// After iOS's answer: until the app is active again and 0.15 s more, so the pop or the shake is seen (TT-190).
    private let afterPrompt: @MainActor () async -> Void
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

    /// A capsule with an action shows for 5 s, one without for 2.5 s (TT-191); the hint for 5 s. Tests pass no
    /// `refusalDelay` and an `afterPrompt` that returns at once (TT-190).
    init(
        rules: AlertRules, actionDuration: Duration = .seconds(5), plainDuration: Duration = .milliseconds(2500),
        hintDuration: Duration = .seconds(5), refusalDelay: Duration = .milliseconds(120),
        afterPrompt: @escaping @MainActor () async -> Void = AlertBellModel.waitUntilActive
    ) {
        self.rules = rules
        self.actionDuration = actionDuration
        self.plainDuration = plainDuration
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
        // A day change from the panel keeps the bell on while it saves: the alert was on before and stays on (or goes
        // back to what was saved, still on).
        case .settingUp: wanted?.ruleID == rule.id ? .on : .waiting
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
    /// the card, a repeating alert for the same usual train takes this day too, else a new This-trip alert is made. A bell
    /// tapped while the day panel is open closes it first. Turning on asks for permission first (`mayAlert`, TT-190).
    func tap(_ trip: Trip, on route: Route) async {
        guard !busy.contains(trip.key) else { return }
        busy.insert(trip.key)
        defer { busy.remove(trip.key) }
        closePanel()
        // A day change from the panel still saving for this alert (its bell shows on meanwhile): the tap acts once it has
        // settled, on what was saved.
        if let saving = daySaving, let id = rules.alert(for: trip, on: route)?.id, wanted?.ruleID == id { await saving.value }

        let existing = rules.alert(for: trip, on: route)
        if let existing {
            switch rules.state(of: existing) {
            case .settingUp:
                return
            case .on where !existing.paused:
                await turnOff(existing, trip: trip, route: route)
                return
            case .on, .notificationsOff, .couldNotSave, .reviewNeeded:
                break
            }
        }
        guard await mayAlert(trip, on: route) else { return }
        // Again after the wait for permission: the alert may have changed meanwhile.
        var rule = rules.alert(for: trip, on: route) ?? newAlert(for: trip, on: route)
        rule.paused = false
        await turnOn(rule, trip: trip, route: route)
    }

    /// The permission rule (TT-190, D72), in this model so Trip details reuses it (TT-192): true while notifications are
    /// allowed. Not asked yet, iOS asks now, the train's bell holding until the app is active again. Refused, now or
    /// before, nothing is saved: the bell shakes with the warning haptic and the capsule follows. A caller that gets true
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

    /// Trip details' Repeat (TT-192, D77): the day panel for the train's alert, with no capsule before it. A one-day alert
    /// starts repeating as the capsule's Repeat makes it (Mon to Fri, on a weekend train that day alone); a repeating one
    /// opens on its days. Tapped again while it is open, the panel closes.
    func togglePanel(for trip: Trip, on route: Route) {
        if capsule?.isPanelOpen == true { return closePanel() }
        guard let rule = rules.alert(for: trip, on: route), !rule.paused else { return }
        hideTask?.cancel()
        let repeats = rule.kind == .repeating ? rule.weekdays : []
        let days = repeats.isEmpty ? AlertDays.repeatDays(for: trip.key.serviceDay) : repeats
        capsuleCount += 1
        capsule = Capsule(id: capsuleCount, kind: .on, trip: trip, route: route, repeats: repeats, panelDays: days)
        undoRule = nil
        retry = nil
        panelRuleID = rule.id
        if repeats.isEmpty { want(days, ruleID: rule.id, trip: trip, route: route) }
    }

    /// Another model on the same alert rules and timings, with a capsule of its own: Trip details' (TT-192), so its
    /// capsule and panel never show on Schedule under the sheet.
    func sibling() -> AlertBellModel {
        AlertBellModel(
            rules: rules, actionDuration: actionDuration, plainDuration: plainDuration, hintDuration: hintDuration,
            refusalDelay: refusalDelay, afterPrompt: afterPrompt
        )
    }

    /// The capsule's Turn on: the capsule goes and the bell is remembered, so it turns on when the rider comes back from
    /// iOS Settings with notifications on (`cameBack()`). The view opens `notificationSettingsURL`.
    func turnOnInSettings() {
        guard let capsule, capsule.kind == .notificationsOff else { return }
        if let trip = capsule.trip, let route = capsule.route { turnsOnWhenBack = (trip, route) }
        dismissCapsule()
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

    /// Waits until the app is active again after the iOS dialog, then 0.15 s, so the bell finishes where the rider sees it
    /// (the Motion board's First tap ever).
    static func waitUntilActive() async {
        while UIApplication.shared.applicationState != .active {
            try? await Task.sleep(for: .milliseconds(50))
        }
        try? await Task.sleep(for: .milliseconds(150))
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

    /// Try again on "Couldn't …": the same change once more.
    func tryAgain() async {
        guard let retry else { return }
        self.retry = nil
        switch retry {
        case let .turnOn(trip, route):
            guard !isWorking(trip, on: route) else { return dismissCapsule() }
            await tap(trip, on: route)
        case let .turnOff(trip, route):
            guard isWorking(trip, on: route) else { return dismissCapsule() }
            await tap(trip, on: route)
        case let .changeDays(days, ruleID, trip, route):
            hideTask?.cancel()
            let shown = capsule?.id
            // Through the one save loop, so it never runs beside a panel's.
            want(days, ruleID: ruleID, trip: trip, route: route)
            if let saving = daySaving { await saving.value }
            // Something newer took the capsule's place meanwhile (a failure that came back says so itself): leave it.
            guard capsule?.id == shown else { return }
            guard let rule = rules.rules.first(where: { $0.id == ruleID }), Self.rule(rule, has: days, for: trip) else {
                // The alert went or changed elsewhere meanwhile: nothing left to try again.
                return dismissCapsule()
            }
            show(.on, trip: trip, route: route, repeats: rule.kind == .repeating ? rule.weekdays : [])
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

    /// "Notifications are off" with Turn on, or "Notifications are on", with no train.
    func showNotifications(on: Bool) {
        show(on ? .notificationsOn : .notificationsOff, trip: nil, route: nil)
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

    /// Saves the alert switched on, the bell waiting at half strength until the server has it. A capsule already up stays
    /// through the wait, then the new one takes its place. A save that fails shakes the bell (TT-190).
    private func turnOn(_ rule: AlertRule, trip: Trip, route: Route) async {
        hideTask?.cancel()
        saving = trip.key
        let committed = await rules.commit(rule)
        saving = nil
        guard committed else {
            await refuse(.failed(.turnOn), trip: trip, route: route, retry: .turnOn(trip, route))
            return
        }
        if let alert = rules.alert(for: trip, on: route), !alert.paused, rules.state(of: alert) == .notificationsOff {
            // Turned off in iOS Settings while it saved.
            await refuse(.notificationsOff, trip: trip, route: route)
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

    /// The bell shakes with the warning haptic and the capsule says why 120 ms later (the Motion board's Refused).
    private func refuse(_ kind: Capsule.Kind, trip: Trip, route: Route, retry: Retry? = nil) async {
        shakeCounts[trip.key, default: 0] += 1
        refusedCount += 1
        dismissCapsule()
        if refusalDelay > .zero { try? await Task.sleep(for: refusalDelay) }
        show(kind, trip: trip, route: route, retry: retry)
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
                // The alert went back to what was saved. What counts now is the latest ask, which may be newer than the
                // one that failed.
                let latest = wanted ?? asked
                wanted = nil
                guard latest.ruleID == asked.ruleID else {
                    // Another alert's panel asked meanwhile: carry on with it.
                    wanted = latest
                    continue
                }
                if let saved = rules.rules.first(where: { $0.id == latest.ruleID }), Self.rule(saved, has: latest.days, for: latest.trip) {
                    // The rider took the change back before it failed: what was saved is what they want.
                    return true
                }
                show(
                    .failed(.changeDays), trip: latest.trip, route: latest.route,
                    retry: .changeDays(latest.days, ruleID: latest.ruleID, latest.trip, latest.route)
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

extension AlertBellModel.Capsule.Kind {
    /// The glyph at the capsule's start: the filled bell, the outline, the exclamation mark, the crossed bell or the tick.
    var glyph: CapsuleGlyph {
        switch self {
        case .on: .bellOn
        case .off, .hint: .bellOff
        case .failed: .failed
        case .notificationsOff: .notificationsOff
        case .notificationsOn: .confirmed
        }
    }
}

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
        case .notificationsOn:
            return String(localized: "alerts.notifications_on")
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

    /// Trip details shows only what its bar cannot say (TT-192): a refusal, a failed save and the day panel. The bar itself
    /// says Alert on and off.
    var showsInTripDetails: Bool {
        switch kind {
        case .failed, .notificationsOff: true
        case .on: isPanelOpen
        case .off, .notificationsOn, .hint: false
        }
    }

    /// The action's words: Repeat, Undo, Try again or Turn on.
    var actionKey: String? {
        guard hasAction else { return nil }
        return switch kind {
        case .on: "alert.repeat"
        case .off: "button.undo"
        case .failed: "button.try_again"
        case .notificationsOff: "capsule.turn_on"
        case .notificationsOn, .hint: nil
        }
    }
}
