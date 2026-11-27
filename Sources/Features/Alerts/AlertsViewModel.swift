import Foundation
import Observation

/// The Alerts tab as cards (TT-253, D129; D78 before it): each alert is Schedule's train card for its next train, under its
/// route said once as Schedule's marks, with a fourth row of the days it rings and "See trains". The bell switches the alert
/// off and on in place (`AlertRules.commit(_:)`, the same id); a card whose usual train changed offers "Pick a new train".
/// The tab reads each alert's trains itself, through the same repository as Schedule, with live status for today's, on its
/// own load and 30 s poll while it shows. With no alert, the next three trains of Schedule's route stand in as plain cards
/// with their real bells, until the rider leaves the tab.
@Observable @MainActor
final class AlertsViewModel {
    /// Where an alert's next train stands.
    enum Run: Equatable {
        /// Its next train: today's until it has left by `BoardingRule`, else the next day the alert rings.
        case train(NextRun)
        /// A one-day alert whose train has left: the card leaves the tab.
        case left
        /// No train on any of its days in the next week.
        case noTrain
        /// The timetable could not be read: the card from the alert alone.
        case failed
    }

    struct NextRun: Equatable {
        let departure: Departure
        /// The alert's route: its stations and line, as the rule keeps them.
        let route: Route
        let isToday: Bool
        let freshness: Freshness
        let hasPlatformSource: Bool

        var day: ServiceDay { departure.trip.key.serviceDay }
    }

    /// One of the days row's seven dots, Monday first.
    enum Dot: Equatable {
        case off
        /// A day it rings.
        case on
        /// A one-day alert's own day ("Once").
        case ring
    }

    /// A route said once above its cards: the origin ring, the name, the dots, the pin, the destination, the line tile.
    struct Section: Identifiable {
        let id: String
        let from: String
        let to: String
        let line: Line?
        let cards: [Item]
    }

    /// One alert's card.
    struct Item: Identifiable {
        enum Body {
            /// Schedule's card for its next train (rows 1 to 3).
            case train(DepartureCard, trip: Trip, route: Route)
            /// No timetable yet: the time and bell from the alert, rows 2 and 3 as skeleton bars.
            case pending
            /// No train on its days in the next week: the time, the bell and "No train today".
            case noTrain
            /// The server found its usual train changed: the time struck in grey, "Time changed", "Pick a new train".
            case changed
        }

        let id: AlertRule.ID
        let body: Body
        /// The alert's scheduled time, for the cards drawn from the alert alone.
        let time: String
        let dots: [Dot]
        /// "Mon to Fri", "Every Fri", "4 days", "Once", "Off"; nil on a changed card.
        let words: String?
        let isOn: Bool
        /// The bell's face; nil on a changed card, which has none.
        let bell: BellFace?
        /// For UI tests: "alerts.rule.LW-0732-20261105".
        let testID: String

        /// The days row in grey: switched off, or its train changed.
        var greysDays: Bool { !isOn || bell == nil }
    }

    /// One of the empty tab's next trains, a plain card; once its bell has an alert, with that alert's fourth row.
    struct Suggestion: Identifiable {
        let card: DepartureCard
        let trip: Trip
        let route: Route
        let alert: AlertRule?
        let dots: [Dot]
        let words: String?

        var id: TripKey { trip.key }
    }

    /// What "See trains" or a tap on a card opens: the train's key (its day) between the alert's stations.
    struct Jump: Equatable {
        let key: TripKey
        let originId: String
        let destinationId: String
    }

    /// The tab's glass capsule: "Alert removed · Undo", "Couldn't … · Try again" or "Notifications are on".
    struct Capsule: Equatable, Identifiable {
        enum Kind: Equatable {
            case removed
            case failed(AlertBellModel.Capsule.Failure)
            case notificationsOn
        }

        let id: Int
        let kind: Kind

        var hasAction: Bool { kind != .notificationsOn }
    }

    /// Schedule's 30 s live poll.
    static let pollInterval: Duration = .seconds(30)
    /// While another tab shows: enough for the tab's dot.
    static let backgroundPollInterval: Duration = .seconds(60)
    /// Every card counts the minutes from 60 min before its train leaves.
    static let countdownLead: TimeInterval = 60 * 60
    /// A one-day alert further away than this names its date ("Fri 6"), not its weekday.
    static let weekdayReach = 6

    let rules: AlertRules
    private(set) var capsule: Capsule?
    /// Counts taps on a bell while notifications are off: each one nudges the notifications-off card's button.
    private(set) var nudges = 0
    /// Each alert's next train, from the last load.
    private(set) var runs: [AlertRule.ID: Run] = [:]
    /// The first load is in: until then a card is drawn from its alert alone.
    private(set) var hasLoaded = false
    /// The moment of the last load or tick, for the countdowns.
    private(set) var now: Date
    /// The empty tab's suggestions stay up, a card with a new alert growing its fourth row, until the rider leaves the tab.
    private(set) var holdsSuggestions = false
    /// Bells tapped whose save is in flight: the bell shows its new face and waits.
    private var switching: [AlertRule.ID: Bool] = [:]
    @ObservationIgnored private var busy: Set<AlertRule.ID> = []

    private let repository: any ScheduleRepository
    private let nextTrains: any NextTrainsProviding
    private let clock: any AppClock
    private let mayAlert: @MainActor (Trip, Route) async -> Bool
    private let actionDuration: Duration
    private let plainDuration: Duration
    private let notificationsOnDelay: Duration
    @ObservationIgnored private var tripCache: [String: [Trip]] = [:]
    @ObservationIgnored private var cacheDay: ServiceDay?
    @ObservationIgnored private var liveCache: [String: LiveSnapshot] = [:]
    @ObservationIgnored private var loadCount = 0
    @ObservationIgnored private var capsuleCount = 0
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var notificationsOnTask: Task<Void, Never>?
    /// The alert Undo puts back, and its delete on its way to the server (Undo waits for it).
    @ObservationIgnored private(set) var removed: AlertRule?
    @ObservationIgnored private var removeTask: Task<Void, Never>?
    @ObservationIgnored private var retry: Retry?

    private enum Retry {
        case setOn(Bool, AlertRule.ID)
        case restore(AlertRule)
    }

    /// The bell's Rail joint and Tap, See trains' Tick, Remove's Drop, Undo's and Try again's Tap, a failed save's Fail, Done
    /// when notifications are back (TT-214, TT-215).
    private let haptics: any HapticPlaying

    /// A capsule with an action shows for 5 s, one without for 2.5 s (D71). `mayAlert` is the bell's permission rule
    /// (`AlertBellModel.mayAlert`, TT-190): turning an alert on asks for notifications first, and a refusal shakes the bell.
    init(
        rules: AlertRules, repository: any ScheduleRepository, nextTrains: any NextTrainsProviding = NoNextTrains(),
        clock: any AppClock, mayAlert: @escaping @MainActor (Trip, Route) async -> Bool = { _, _ in true },
        actionDuration: Duration = .seconds(5), plainDuration: Duration = .milliseconds(2500),
        notificationsOnDelay: Duration = .milliseconds(300), haptics: any HapticPlaying = TTHaptics.shared
    ) {
        self.rules = rules
        self.repository = repository
        self.nextTrains = nextTrains
        self.clock = clock
        self.mayAlert = mayAlert
        self.actionDuration = actionDuration
        self.plainDuration = plainDuration
        self.notificationsOnDelay = notificationsOnDelay
        self.haptics = haptics
        now = clock.now
    }

    // MARK: Cards

    /// No alert on the tab.
    var isEmpty: Bool { listedRules.isEmpty }

    /// The empty tab's next trains show: no alert, or the rider set the first one from them and has not left the tab.
    var showsSuggestions: Bool { holdsSuggestions || isEmpty }

    /// Every listed alert as a card, grouped under its route: routes in the order of their earliest train, cards in time of
    /// day, so a card never jumps when its state changes.
    func sections(_ formatter: some TimeFormatting) -> [Section] {
        var sections: [Section] = []
        for rule in listedRules.sorted(by: Self.timeOfDay) {
            let key = "\(rule.origin.id)>\(rule.destination.id)"
            let item = item(for: rule, formatter)
            if let index = sections.firstIndex(where: { $0.id == key }) {
                let section = sections[index]
                sections[index] = Section(id: key, from: section.from, to: section.to, line: section.line, cards: section.cards + [item])
            } else {
                sections.append(Section(
                    id: key, from: rule.origin.name, to: rule.destination.name,
                    line: rule.line.isEmpty ? nil : Line(id: rule.line, name: "", colorHex: nil), cards: [item]
                ))
            }
        }
        return sections
    }

    /// The next three trains of Schedule's route today, while the empty tab shows them; none with no route or no more
    /// trains today.
    func suggestions(_ formatter: some TimeFormatting) -> (route: Route, trains: [Suggestion])? {
        guard let source = nextTrains.nextTrains else { return nil }
        let now = clock.now
        let trains = source.departures
            .filter { $0.isUsable && !$0.hasLeft(at: now) }
            .prefix(3)
            .map { departure in
                var card = DepartureCard(departure, isNext: false, isBoarding: departure.isBoarding(at: now), now: now, formatter: formatter)
                card.relativeTime = Self.countdown(departure, hasPlatform: card.hasPlatform, now: now, formatter: formatter)
                let alert = rules.alert(for: departure.trip, on: source.route)
                return Suggestion(
                    card: card, trip: departure.trip, route: source.route, alert: alert, dots: alert.map(Self.dots) ?? [],
                    words: alert.map { words(for: $0, isOn: !$0.paused) }
                )
            }
        return trains.isEmpty ? nil : (source.route, Array(trains))
    }

    /// The stored alert behind a card.
    func rule(_ id: AlertRule.ID) -> AlertRule? {
        rules.rules.first { $0.id == id }
    }

    /// Today's late or cancelled offline line: "Offline · last updated 6:52 AM", while today's live status is offline.
    func offlineLine(_ formatter: some TimeFormatting) -> String? {
        for rule in listedRules {
            guard case .train(let run)? = runs[rule.id], run.isToday, case .offline(let updated) = run.freshness else { continue }
            return updated.map { String(format: String(localized: "freshness.offline"), formatter.time($0)) }
                ?? String(localized: "schedule.offline")
        }
        return nil
    }

    // MARK: Loading

    /// While the tab shows: the first load, then the live poll every 30 s, which also moves the countdowns on. An empty tab
    /// keeps its suggestions until the rider leaves it.
    func run() async {
        if isEmpty { holdsSuggestions = true }
        await load()
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.pollInterval)
            guard !Task.isCancelled else { return }
            await load()
        }
    }

    /// Reads each alert's next train: its days from today, the trips of its route on each (kept for the day), the first the
    /// alert covers, with live status when it is today's. Today's train that has left (`BoardingRule`) hands over to the
    /// next day the alert rings; a one-day alert's is over.
    func load() async {
        loadCount += 1
        let mine = loadCount
        let now = clock.now
        let today = ServiceDay(containing: now)
        if cacheDay != today {
            tripCache = [:]
            cacheDay = today
        }
        liveCache = [:]
        var next: [AlertRule.ID: Run] = [:]
        for rule in rules.rules where rule.isCurrent(on: today) && rules.state(of: rule) != .reviewNeeded {
            next[rule.id] = await run(of: rule, today: today, now: now)
        }
        // A later load started meanwhile (a poll, a change of alerts): it has the newer answer.
        guard mine == loadCount else { return }
        self.now = now
        runs = next
        hasLoaded = true
    }

    private func run(of rule: AlertRule, today: ServiceDay, now: Date) async -> Run {
        let route = Self.route(of: rule)
        let days: [ServiceDay] = switch rule.kind {
        case .thisTrip: rule.trip.map { [$0.serviceDay] } ?? []
        case .repeating: (0...7).map(today.adding).filter { rule.weekdays.contains($0.isoWeekday) }
        }
        var failed = false
        for day in days {
            guard let trips = await trips(of: route, on: day) else {
                failed = true
                continue
            }
            guard let trip = trips.first(where: { rule.covers($0, on: route) }) else { continue }
            let isToday = day == today
            let live = isToday ? await liveStatus(of: route, on: day) : .empty
            let freshness = isToday ? Freshness(live, now: now) : .scheduledOnly
            guard let departure = Departure.resolve([trip], live: live, freshness: freshness, isToday: isToday).first else { continue }
            if departure.hasLeft(at: now) {
                if rule.kind == .thisTrip { return .left }
                continue
            }
            return .train(NextRun(
                departure: departure, route: route, isToday: isToday, freshness: freshness,
                hasPlatformSource: isToday && live.hasPlatformSource
            ))
        }
        return failed ? .failed : .noTrain
    }

    private func trips(of route: Route, on day: ServiceDay) async -> [Trip]? {
        let key = "\(route.from.id)>\(route.to.id)@\(day)"
        if let trips = tripCache[key] { return trips }
        guard let trips = try? await repository.trips(for: route, on: day) else { return nil }
        tripCache[key] = trips
        return trips
    }

    private func liveStatus(of route: Route, on day: ServiceDay) async -> LiveSnapshot {
        let key = "\(route.from.id)>\(route.to.id)"
        if let live = liveCache[key] { return live }
        let live = (try? await repository.liveStatus(for: route, on: day)) ?? .empty
        liveCache[key] = live
        return live
    }

    // MARK: The bell

    /// The card's bell: an alert switched on goes off in place (a one-day one too: it stays, grey, until the rider leaves
    /// the tab), one switched off goes on again after the permission rule; both save the same id through `commit`. The
    /// bell shows its new face at once. While notifications are off, a tap nudges the warning card's button instead.
    @discardableResult
    func tapBell(_ id: AlertRule.ID) -> Task<Void, Never>? {
        guard let rule = rule(id), !busy.contains(id), rules.state(of: rule) != .reviewNeeded else { return nil }
        if warnsNotificationsOff {
            nudge()
            return nil
        }
        busy.insert(id)
        let turnsOn = rule.paused
        if !turnsOn { switching[id] = false }
        return Task {
            defer { busy.remove(id) }
            if turnsOn {
                let train = self.train(of: rule)
                guard await mayAlert(train.trip, train.route) else { return }
                switching[id] = true
            }
            await setOn(turnsOn, for: id)
        }
    }

    /// A tap on a bell while notifications are off: the card's button nudges.
    func nudge() {
        nudges += 1
    }

    private func setOn(_ isOn: Bool, for id: AlertRule.ID) async {
        guard var rule = rule(id) else {
            switching[id] = nil
            return
        }
        rule.paused = !isOn
        switching[id] = isOn
        let saved = await rules.commit(rule)
        switching[id] = nil
        if saved {
            haptics.play(isOn ? HapticFeel.railJoint : HapticFeel.tap)
        } else {
            show(.failed(isOn ? .turnOn : .turnOff), retry: .setOn(isOn, id))
        }
    }

    // MARK: Opening

    /// "See trains": Schedule on the alert's route and its train's day, with Tick, as a tab change plays it. Sends
    /// `alert_shown_in_schedule`.
    func seeTrains(_ id: AlertRule.ID) -> Jump? {
        guard let rule = rule(id) else { return nil }
        let key = trainKey(of: rule)
        let shown = nextTrains.shownRoute
        let routeChanged = shown.map { $0.from.id != rule.origin.id || $0.to.id != rule.destination.id } ?? true
        haptics.play(.tab)
        Analytics.track(.alertShownInSchedule(isToday: key.serviceDay == today, routeChanged: routeChanged, isOn: !rule.paused))
        return Jump(key: key, originId: rule.origin.id, destinationId: rule.destination.id)
    }

    /// A tap on a card: its train's Trip details; none while the card is drawn from the alert alone.
    func trip(_ id: AlertRule.ID) -> Jump? {
        guard let rule = rule(id), case .train(let run)? = runs[id] else { return nil }
        return Jump(key: run.departure.trip.key, originId: rule.origin.id, destinationId: rule.destination.id)
    }

    // MARK: Remove and Undo (Trip details' Remove alert, TT-254)

    /// "Remove alert": the alert is deleted on device and on the server, and "Alert removed · Undo" shows for 5 s.
    @discardableResult
    func remove(_ id: AlertRule.ID) -> Task<Void, Never>? {
        guard let rule = rule(id) else { return nil }
        let task = rules.deleteInBackground(id)
        haptics.play(.remove)
        Analytics.track(.alertRemoved(source: .alertsTab))
        show(.removed)
        removed = rule
        removeTask = task
        return task
    }

    /// Undo on "Alert removed": the alert back with the same id, days and switch, once its delete is done.
    func undo() async {
        guard capsule?.kind == .removed, let rule = removed else { return }
        haptics.play(.undo)
        dismissCapsule()
        await removeTask?.value
        await restore(rule)
    }

    /// Try again on "Couldn't …": the same change once more.
    func tryAgain() async {
        guard let retry else { return }
        haptics.play(.undo)
        dismissCapsule()
        switch retry {
        case let .setOn(isOn, id):
            await setOn(isOn, for: id)
        case let .restore(rule):
            await restore(rule)
        }
    }

    func dismissCapsule() {
        hideTask?.cancel()
        capsule = nil
        removed = nil
        retry = nil
    }

    /// The rider left the tab: the suggestions go, and a one-day alert switched off goes (it has nothing to keep).
    func leftTab() {
        holdsSuggestions = false
        for rule in rules.rules where rule.kind == .thisTrip && rule.paused && switching[rule.id] == nil && !busy.contains(rule.id) {
            _ = rules.deleteInBackground(rule.id)
        }
    }

    /// The permission, the server's rule states and the trains, at every foreground and when the tab opens. When the rider
    /// has turned notifications on since the warning showed, "Notifications are on" says so (TT-169).
    func refresh() async {
        let warned = warnsNotificationsOff
        await rules.refresh()
        tripCache = [:]
        await load()
        if warned, rules.permission == .allowed { showNotificationsOn() }
    }

    // MARK: Notifications off (TT-169, D58)

    /// Alerts switched on, as the tab lists them: switched-off ones and one-day alerts whose train has left do not count.
    var switchedOnCount: Int {
        listedRules.filter { !$0.paused }.count
    }

    /// iOS notifications are off while an alert is switched on: the card tops the tab, every bell is crossed and the tab
    /// icon wears a red dot. A permission never asked does not count, and neither do switched-off alerts.
    var warnsNotificationsOff: Bool {
        rules.permission == .off && switchedOnCount > 0
    }

    /// Settings › Notifications' card body: "Your 2 alerts are saved, but they can't reach you."
    static func offDetail(count: Int) -> String {
        count == 1
            ? String(localized: "alerts.off.detail") : String(format: String(localized: "alerts.off.detail_plural"), count)
    }

    /// The Alerts tab card's one line: "3 alerts can’t reach you."; "1 alert can’t reach you."
    static func offLine(count: Int) -> String {
        count == 1 ? String(localized: "alerts.off.line") : String(format: String(localized: "alerts.off.line_plural"), count)
    }

    private func showNotificationsOn() {
        notificationsOnTask?.cancel()
        let delay = notificationsOnDelay
        notificationsOnTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.haptics.play(.confirmed)
            self.show(.notificationsOn)
        }
    }

    // MARK: Tab dot

    /// The dot on the Alerts tab icon while another tab shows: red while the notifications-off warning shows, which wins
    /// over the accent dot; accent while a switched-on alert's train today is late or cancelled (or the router noted
    /// something new). None while Alerts is open: what it says is on the screen.
    func tabDot(isSelected: Bool, hasNewUpdate: Bool) -> TabBarStyle.Dot? {
        guard !isSelected else { return nil }
        if warnsNotificationsOff { return .warning }
        return hasNewUpdate || hasChangedTrain ? .accent : nil
    }

    /// A switched-on alert's train today is late or cancelled, as its card says.
    var hasChangedTrain: Bool {
        listedRules.contains { rule in
            guard !rule.paused, case .train(let run)? = runs[rule.id], run.isToday, !run.departure.hasLeft(at: clock.now) else {
                return false
            }
            return switch run.departure.status {
            case .delayed, .cancelled, .stopSkipped: true
            default: false
            }
        }
    }

    // MARK: Private

    /// The service day on the app clock (mock time included).
    var today: ServiceDay { ServiceDay(containing: clock.now) }

    /// Every alert still to ring: a one-day alert leaves once its train has left, by the feed and the train's position
    /// (`BoardingRule`), not at its scheduled time; with no train read yet, by its own time on the clock.
    private var listedRules: [AlertRule] {
        let today = self.today
        let now = clock.now
        return rules.rules.filter { rule in
            guard rule.kind == .thisTrip else { return true }
            guard let key = rule.trip, key.serviceDay >= today else { return false }
            switch runs[rule.id] {
            case .left?: return false
            case .train(let run)?: return !run.departure.hasLeft(at: now)
            case .noTrain?, .failed?, nil: return !Self.departure(of: rule).hasLeft(at: now)
            }
        }
    }

    private func item(for rule: AlertRule, _ formatter: some TimeFormatting) -> Item {
        let isOn = switching[rule.id] ?? !rule.paused
        let changed = rules.state(of: rule) == .reviewNeeded
        let bell: BellFace? = if changed {
            nil
        } else if warnsNotificationsOff || (isOn && rules.state(of: rule) == .notificationsOff) {
            .crossed
        } else {
            isOn ? .on : .off
        }
        let body: Item.Body
        if changed {
            body = .changed
        } else {
            switch runs[rule.id] {
            case .train(let run)?: body = .train(card(run, rule: rule, isOn: isOn, formatter), trip: run.departure.trip, route: run.route)
            case .noTrain?: body = .noTrain
            case .failed?, .left?, nil: body = .pending
            }
        }
        return Item(
            id: rule.id, body: body, time: formatter.time(rule.scheduledDeparture), dots: Self.dots(of: rule),
            words: changed ? nil : words(for: rule, isOn: isOn), isOn: isOn, bell: bell, testID: "alerts.rule.\(rule.tripId)"
        )
    }

    /// Schedule's card for the alert's train, its countdown slot saying when it runs.
    private func card(_ run: NextRun, rule: AlertRule, isOn: Bool, _ formatter: some TimeFormatting) -> DepartureCard {
        let departure = run.departure
        let isBoarding = run.isToday && departure.isBoarding(at: now)
        let awaits = run.isToday
            && departure.awaitsPlatform(isNext: true, now: now, freshness: run.freshness, hasPlatformSource: run.hasPlatformSource)
        var card = DepartureCard(departure, isNext: false, awaitsPlatform: awaits, isBoarding: isBoarding, now: now, formatter: formatter)
        card.relativeTime = run.isToday ? Self.countdown(departure, hasPlatform: card.hasPlatform, now: now, formatter: formatter) : nil
        card.dayWord = card.relativeTime == nil ? Self.dayWord(run.day, today: today, isOneDay: rule.kind == .thisTrip) : nil
        card.isQuiet = !isOn
        return card
    }

    /// "Off", "Once", else the days in words.
    private func words(for rule: AlertRule, isOn: Bool) -> String {
        if !isOn { return String(localized: "alerts.days.off") }
        if rule.kind == .thisTrip { return String(localized: "alerts.days.once") }
        return AlertDays.cardWords(of: rule.weekdays) ?? String(localized: "alerts.days.once")
    }

    /// The card's train for the permission rule: the one read, else one made from the alert.
    private func train(of rule: AlertRule) -> (trip: Trip, route: Route) {
        if case .train(let run)? = runs[rule.id] { return (run.departure.trip, run.route) }
        return (Self.departure(of: rule).trip, Self.route(of: rule))
    }

    /// The day "See trains" opens: the card's train's, else the alert's own day (a repeating one's next day from today).
    private func trainKey(of rule: AlertRule) -> TripKey {
        if case .train(let run)? = runs[rule.id] { return run.departure.trip.key }
        let today = self.today
        let day = switch rule.kind {
        case .thisTrip: rule.trip?.serviceDay ?? today
        case .repeating: (0...7).map(today.adding).first { rule.weekdays.contains($0.isoWeekday) } ?? today
        }
        return TripKey(serviceDay: day, tripId: rule.tripId)
    }

    private func restore(_ rule: AlertRule) async {
        if !(await rules.commit(rule)) { show(.failed(.turnOn), retry: .restore(rule)) }
    }

    private func show(_ kind: Capsule.Kind, retry: Retry? = nil) {
        if case .failed = kind { haptics.play(.fail) }
        capsuleCount += 1
        let next = Capsule(id: capsuleCount, kind: kind)
        capsule = next
        removed = nil
        self.retry = retry
        hideTask?.cancel()
        let duration = next.hasAction ? actionDuration : plainDuration
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self, self.capsule?.id == next.id else { return }
            self.dismissCapsule()
        }
    }

    private static func timeOfDay(_ lhs: AlertRule, _ rhs: AlertRule) -> Bool {
        (ServiceDay.minutesIntoServiceDay(lhs.scheduledDeparture), lhs.id) < (ServiceDay.minutesIntoServiceDay(rhs.scheduledDeparture), rhs.id)
    }

    /// The alert's route as the rule keeps it: its stations and its line, which a repeating alert's train must match.
    static func route(of rule: AlertRule) -> Route {
        Route(
            from: Station(id: rule.origin.id, name: rule.origin.name), to: Station(id: rule.destination.id, name: rule.destination.name),
            line: rule.line.isEmpty ? nil : Line(id: rule.line, name: "", colorHex: nil)
        )
    }

    /// The alert's own train, scheduled, as the rule saved it.
    static func departure(of rule: AlertRule) -> Departure {
        let trip = Trip(
            key: rule.trip ?? TripKey(serviceDay: ServiceDay(containing: rule.scheduledDeparture), tripId: rule.tripId),
            scheduledDeparture: rule.scheduledDeparture, scheduledArrival: rule.scheduledDeparture, platform: .pending, tags: []
        )
        return Departure(trip: trip, status: .scheduled, expectedDeparture: nil, expectedArrival: nil)
    }

    /// The seven dots, Monday first: the days a repeating alert rings, a one-day alert's own day as a ring.
    static func dots(of rule: AlertRule) -> [Dot] {
        AlertDays.week.map { day -> Dot in
            switch rule.kind {
            case .repeating: return rule.weekdays.contains(day) ? .on : .off
            case .thisTrip: return rule.trip?.serviceDay.isoWeekday == day ? .ring : .off
            }
        }
    }

    /// "in 11 min" (or "Departing") from 60 min before a usable train leaves, once its platform is posted (D125); else nil.
    static func countdown(_ departure: Departure, hasPlatform: Bool, now: Date, formatter: some TimeFormatting) -> String? {
        guard departure.isUsable, hasPlatform, departure.departureTime.timeIntervalSince(now) <= countdownLead else { return nil }
        return formatter.relative(until: departure.departureTime, now: now)
    }

    /// When the card's train runs: "Today", "Tomorrow", the weekday in full ("Monday"), or for a one-day alert more than six
    /// days away its date ("Fri 6").
    static func dayWord(_ day: ServiceDay, today: ServiceDay, isOneDay: Bool) -> String {
        if day == today { return String(localized: "alerts.when.today") }
        if day == today.adding(days: 1) { return String(localized: "alerts.when.tomorrow") }
        if isOneDay, today.days(to: day) > weekdayReach {
            return String(format: String(localized: "alerts.when.date"), day.weekdayShort, day.day)
        }
        return day.weekdayName
    }
}

/// Today's trains on Schedule's route, for the empty Alerts tab's cards (TT-193, TT-253), and the route Schedule shows,
/// for "See trains"' `route_changed`.
@MainActor
protocol NextTrainsProviding: AnyObject {
    var nextTrains: (route: Route, departures: [Departure])? { get }
    var shownRoute: Route? { get }
}

/// No route: the empty tab shows "See trains".
@MainActor
final class NoNextTrains: NextTrainsProviding {
    init() {}
    var nextTrains: (route: Route, departures: [Departure])? { nil }
    var shownRoute: Route? { nil }
}

extension ScheduleViewModel: NextTrainsProviding {
    /// The route's trains for today with their live status; nil with no route or while another day shows.
    var nextTrains: (route: Route, departures: [Departure])? {
        guard let route, selectedDay == today else { return nil }
        return (route, departures)
    }

    var shownRoute: Route? { route }
}

extension ScheduleViewModel: LineNoticesProviding {}
