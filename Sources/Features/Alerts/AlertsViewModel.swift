import Foundation
import Observation

/// The Alerts tab as one list (TT-193, D77; TT-143 before it): the title and one card of alarm-style rows, the time, one
/// line and a switch, in time order. A row opens in place to its day tiles and "Remove alert"; a row whose usual train
/// changed offers "Pick a new train". Recent shows up to three notifications from the last 7 days. With no alert, the next
/// three trains of the route stand in, each with its real bell. Every change saves the same alert (same id) through
/// `AlertRules.commit(_:)`, so nothing is half-kept, and a failure shows as the glass capsule with Try again.
@Observable @MainActor
final class AlertsViewModel {
    struct Row: Identifiable, Equatable {
        enum Note: Equatable {
            case none
            /// The server found the usual train changed: amber "Time changed", the switch off; opened, "Pick a new train".
            case timeChanged
            /// A holiday with no matching train: quiet "No train today".
            case noTrainToday
        }

        let id: AlertRule.ID
        /// "7:32 AM".
        let time: String
        /// "Oakville to Union · Mon to Fri"; "· Today only", "· Tomorrow only", "· Fri 6 only"; "· Time changed".
        let line: String
        let note: Note
        let isOn: Bool
        /// A switch change is saving: the switch waits.
        let isSaving: Bool
        /// The day tiles lit, ISO weekdays; none for a one-day alert, which opens with "Repeat on" over unlit tiles.
        let days: [Int]
        /// For UI tests: "alerts.rule.LW-0732-20261105" (the same when a one-day alert starts to repeat).
        let testID: String

        var isOneDay: Bool { days.isEmpty }
    }

    /// One of the next trains the empty tab offers, with its bell.
    struct NextTrain: Identifiable, Equatable {
        let trip: Trip
        let route: Route
        /// "7:32 AM".
        let time: String
        /// "Oakville to Union · in 11 min".
        let line: String
        var id: TripKey { trip.key }
    }

    struct RecentRow: Identifiable, Equatable {
        let id: AlertUpdate.ID
        let kind: AlertUpdate.Kind
        /// "7:32 AM train delayed 9 min".
        let title: String
        /// "7:29 AM" today, "Yesterday", else "Mon".
        let when: String
        /// Trip details for that trip and service date; nil once that service day has passed.
        let link: NotificationLink?
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

    let rules: AlertRules
    /// The row open in place; one at a time.
    private(set) var openID: AlertRule.ID?
    private(set) var capsule: Capsule?
    /// Counts taps on a disabled switch: each one nudges the notifications-off card's button.
    private(set) var nudges = 0
    /// Counts day tiles lit, for the selection haptic.
    private(set) var dayOnCount = 0
    /// Counts taps on the last lit day, which cannot be cleared here: the tile presses and settles back.
    private(set) var lastDayTaps: [AlertRule.ID: Int] = [:]
    /// Switches flipped whose save is in flight: the switch shows its new place and waits.
    private var switching: [AlertRule.ID: Bool] = [:]
    /// Days asked for in an open row, shown at once and saved one change at a time.
    private var wantedDays: [AlertRule.ID: [Int]] = [:]
    /// The rules needing review the rider has seen on the tab; any other turns the tab dot on.
    private var seenReviews: Set<AlertRule.ID> = []

    private let updates: AlertUpdates
    private let nextTrains: any NextTrainsProviding
    private let clock: any AppClock
    private let actionDuration: Duration
    private let plainDuration: Duration
    private let notificationsOnDelay: Duration
    @ObservationIgnored private var capsuleCount = 0
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var notificationsOnTask: Task<Void, Never>?
    /// The alert Undo puts back, and its delete on its way to the server (Undo waits for it).
    @ObservationIgnored private(set) var removed: AlertRule?
    @ObservationIgnored private var removeTask: Task<Void, Never>?
    @ObservationIgnored private var dayTask: Task<Void, Never>?
    @ObservationIgnored private var retry: Retry?

    private enum Retry {
        case setOn(Bool, AlertRule.ID)
        case days([Int], AlertRule.ID)
        case restore(AlertRule)
    }

    /// A capsule with an action shows for 5 s, one without for 2.5 s (D71).
    init(
        rules: AlertRules, updates: AlertUpdates, nextTrains: any NextTrainsProviding = NoNextTrains(), clock: any AppClock,
        actionDuration: Duration = .seconds(5), plainDuration: Duration = .milliseconds(2500),
        notificationsOnDelay: Duration = .milliseconds(300)
    ) {
        self.rules = rules
        self.updates = updates
        self.nextTrains = nextTrains
        self.clock = clock
        self.actionDuration = actionDuration
        self.plainDuration = plainDuration
        self.notificationsOnDelay = notificationsOnDelay
    }

    // MARK: Rows

    /// No alert to list: the next trains show instead.
    var isEmpty: Bool { listedRules.isEmpty }

    /// Every listed alert in time of day, so a row never jumps when it changes.
    func rows(_ formatter: some TimeFormatting) -> [Row] {
        let today = self.today
        return listedRules
            .sorted { (ServiceDay.minutesIntoServiceDay($0.scheduledDeparture), $0.id) < (ServiceDay.minutesIntoServiceDay($1.scheduledDeparture), $1.id) }
            .map { rule in
                let timeChanged = rules.state(of: rule) == .reviewNeeded
                let days = wantedDays[rule.id] ?? (rule.kind == .repeating ? rule.weekdays : [])
                let note: Row.Note
                let detail: String
                if timeChanged {
                    note = .timeChanged
                    detail = String(localized: "alerts.time_changed")
                } else if rule.kind == .repeating, rules.hasNoMatchingTrain(rule, on: today) {
                    note = .noTrainToday
                    detail = String(localized: "alerts.no_train")
                } else {
                    note = .none
                    detail = AlertDays.summary(of: days) ?? Self.oneDay(rule.trip?.serviceDay ?? today, today: today)
                }
                return Row(
                    id: rule.id,
                    time: formatter.time(rule.scheduledDeparture),
                    line: String(format: String(localized: "alerts.rule.title"), routeName(rule), detail),
                    note: note,
                    isOn: !timeChanged && (switching[rule.id] ?? !rule.paused),
                    isSaving: switching[rule.id] != nil,
                    days: days,
                    testID: "alerts.rule.\(rule.tripId)"
                )
            }
    }

    /// The next three trains of the route today, while the tab is empty; none with no route or no more trains today.
    func nextTrainRows(_ formatter: some TimeFormatting) -> [NextTrain] {
        guard let source = nextTrains.nextTrains else { return [] }
        let now = clock.now
        return source.trips
            .filter { $0.scheduledDeparture > now }
            .sorted { $0.scheduledDeparture < $1.scheduledDeparture }
            .prefix(3)
            .map { trip in
                NextTrain(
                    trip: trip, route: source.route, time: formatter.time(trip.scheduledDeparture),
                    line: String(
                        format: String(localized: "alerts.rule.title"),
                        String(format: String(localized: "schedule.route_title"), source.route.from.name, source.route.to.name),
                        Self.countdown(to: trip.scheduledDeparture, now: now)
                    )
                )
            }
    }

    /// Up to three notifications from the last 7 days, newest first.
    func recentRows(_ formatter: some TimeFormatting) -> [RecentRow] {
        let now = clock.now
        let today = self.today
        return updates.updates
            .filter { now.timeIntervalSince($0.deliveredAt) < AlertUpdates.window }
            .prefix(3)
            .map { update in
                RecentRow(
                    id: update.id, kind: update.kind, title: update.title, when: Self.when(update.deliveredAt, now: now, formatter: formatter),
                    link: update.link.flatMap { $0.target(today: today) == .alerts ? nil : $0 }
                )
            }
    }

    /// The stored alert behind a row, for "Pick a new train".
    func rule(_ id: AlertRule.ID) -> AlertRule? {
        rules.rules.first { $0.id == id }
    }

    // MARK: Opening

    /// A tap on a row opens it in place, closing any other; a tap on the open one closes it.
    func toggleOpen(_ id: AlertRule.ID) {
        openID = openID == id ? nil : id
    }

    /// A tap outside the card, or leaving the tab.
    func closeRow() {
        if openID != nil { openID = nil }
    }

    // MARK: Changes

    /// The switch: the alert switched on or off, saved under its id; the row stays where it is, grey when off. A change the
    /// server cannot take goes back, and "Couldn't turn alert on/off · Try again" shows.
    @discardableResult
    func setOn(_ isOn: Bool, for id: AlertRule.ID) -> Task<Void, Never>? {
        guard var rule = rule(id), rule.paused == isOn, switching[id] == nil else { return nil }
        rule.paused = !isOn
        switching[id] = isOn
        return Task {
            let saved = await rules.commit(rule)
            switching[id] = nil
            if !saved { show(.failed(isOn ? .turnOn : .turnOff), retry: .setOn(isOn, id)) }
        }
    }

    /// A day tile in an open row: lit or not at once, then saved by itself. The last lit day cannot be cleared here (Remove
    /// alert is right below); lighting a day on a one-day alert makes it repeat on that day.
    @discardableResult
    func toggleDay(_ day: Int, for id: AlertRule.ID) -> Task<Void, Never>? {
        guard let rule = rule(id), rules.state(of: rule) != .reviewNeeded else { return nil }
        var days = wantedDays[id] ?? (rule.kind == .repeating ? rule.weekdays : [])
        if let index = days.firstIndex(of: day) {
            guard days.count > 1 else {
                lastDayTaps[id, default: 0] += 1
                return nil
            }
            days.remove(at: index)
        } else {
            days = (days + [day]).sorted()
            dayOnCount += 1
        }
        wantedDays[id] = days
        return saveDays(id)
    }

    /// "Remove alert": the row fades and shuts at once, the alert is deleted on device and on the server, and "Alert removed
    /// · Undo" shows for 5 s.
    @discardableResult
    func remove(_ id: AlertRule.ID) -> Task<Void, Never>? {
        guard let rule = rule(id) else { return nil }
        openID = nil
        wantedDays[id] = nil
        let task = rules.deleteInBackground(id)
        show(.removed)
        removed = rule
        removeTask = task
        return task
    }

    /// Undo on "Alert removed": the alert back with the same id, days and switch, once its delete is done.
    func undo() async {
        guard capsule?.kind == .removed, let rule = removed else { return }
        dismissCapsule()
        await removeTask?.value
        await restore(rule)
    }

    /// Try again on "Couldn't …": the same change once more.
    func tryAgain() async {
        guard let retry else { return }
        dismissCapsule()
        switch retry {
        case let .setOn(isOn, id):
            await setOn(isOn, for: id)?.value
        case let .days(days, id):
            wantedDays[id] = days
            await saveDays(id).value
        case let .restore(rule):
            await restore(rule)
        }
    }

    /// A tap on a switch while notifications are off: the card's button nudges.
    func nudge() {
        nudges += 1
    }

    func dismissCapsule() {
        hideTask?.cancel()
        capsule = nil
        removed = nil
        retry = nil
    }

    /// The rider left the tab: the open row closes, and a one-day alert switched off goes (it has nothing to keep).
    func leftTab() {
        closeRow()
        for rule in rules.rules where rule.kind == .thisTrip && rule.paused && switching[rule.id] == nil {
            _ = rules.deleteInBackground(rule.id)
        }
    }

    /// The permission, the server's rule states and the notifications delivered since the last look. When the rider has
    /// turned notifications on since the warning showed, "Notifications are on" says so (TT-169).
    func refresh() async {
        let warned = warnsNotificationsOff
        await rules.refresh()
        await updates.refresh()
        if warned, rules.permission == .allowed { showNotificationsOn() }
    }

    // MARK: Notifications off (TT-169, D58)

    /// Alerts switched on, as the tab lists them: paused ones and one-day alerts whose train has left do not count.
    var switchedOnCount: Int {
        listedRules.filter { !$0.paused }.count
    }

    /// iOS notifications are off while an alert is switched on: the card tops the tab, the switches are disabled and the tab
    /// icon wears a red dot. A permission never asked does not count, and neither do paused alerts.
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
            self.show(.notificationsOn)
        }
    }

    // MARK: Tab dot

    /// The dot on the Alerts tab icon while another tab shows: red while the notifications-off warning shows, which wins
    /// over the accent dot; accent while something is new, a notification the router noted (`hasNewUpdate`) or a time
    /// change the rider has not seen. None while Alerts is open: what it says is on the screen.
    func tabDot(isSelected: Bool, hasNewUpdate: Bool) -> TabBarStyle.Dot? {
        guard !isSelected else { return nil }
        if warnsNotificationsOff { return .warning }
        return hasNewUpdate || showsTabDot ? .accent : nil
    }

    /// The accent dot on the Alerts tab icon: a row reads Time changed that the rider has not seen on the tab yet.
    var showsTabDot: Bool {
        !reviewIDs.isSubset(of: seenReviews)
    }

    /// The rider opened the tab: the time changes now are seen.
    func markReviewsSeen() {
        let ids = reviewIDs
        if ids != seenReviews { seenReviews = ids }
    }

    // MARK: Private

    /// The service day on the app clock (mock time included).
    var today: ServiceDay { ServiceDay(containing: clock.now) }

    /// Every alert except one-day alerts whose train has left.
    private var listedRules: [AlertRule] {
        let now = clock.now
        return rules.rules.filter { $0.kind == .repeating || $0.scheduledDeparture > now }
    }

    private var reviewIDs: Set<AlertRule.ID> {
        Set(listedRules.filter { rules.state(of: $0) == .reviewNeeded }.map(\.id))
    }

    private func routeName(_ rule: AlertRule) -> String {
        String(format: String(localized: "schedule.route_title"), rule.origin.name, rule.destination.name)
    }

    /// Saves the latest days asked for, after any day change still saving.
    private func saveDays(_ id: AlertRule.ID) -> Task<Void, Never> {
        let previous = dayTask
        let task = Task {
            await previous?.value
            await saveWantedDays(id)
        }
        dayTask = task
        return task
    }

    private func saveWantedDays(_ id: AlertRule.ID) async {
        guard let days = wantedDays[id], var rule = rule(id) else {
            wantedDays[id] = nil
            return
        }
        guard rule.kind != .repeating || rule.weekdays != days else {
            wantedDays[id] = nil
            return
        }
        rule.kind = .repeating
        rule.weekdays = days
        let saved = await rules.commit(rule)
        // A newer ask while it saved is saved by the next turn.
        if wantedDays[id] == days || !saved { wantedDays[id] = nil }
        if !saved { show(.failed(.changeDays), retry: .days(days, id)) }
    }

    private func restore(_ rule: AlertRule) async {
        if !(await rules.commit(rule)) { show(.failed(.turnOn), retry: .restore(rule)) }
    }

    private func show(_ kind: Capsule.Kind, retry: Retry? = nil) {
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

    /// "Today only", "Tomorrow only", else "Fri 6 only".
    static func oneDay(_ day: ServiceDay, today: ServiceDay) -> String {
        if day == today { return String(localized: "alerts.today_only") }
        if day == today.adding(days: 1) { return String(localized: "alert.days.tomorrow_only") }
        return String(format: String(localized: "alert.days.date_only"), day.weekdayShort, day.day)
    }

    /// "in 11 min", "in 1 h".
    static func countdown(to date: Date, now: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        return minutes < 60
            ? String(format: String(localized: "schedule.in_minutes"), minutes)
            : String(format: String(localized: "alerts.in_hours"), minutes / 60)
    }

    /// "7:29 AM" today, "Yesterday", else "Mon", by the calendar day in Toronto.
    static func when(_ date: Date, now: Date, formatter: some TimeFormatting) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = goTimeZone
        if calendar.isDate(date, inSameDayAs: now) { return formatter.time(date) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "alerts.yesterday")
        }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return ServiceDay(year: parts.year ?? 0, month: parts.month ?? 1, day: parts.day ?? 1).weekdayShort
    }
}

/// Today's trains on the saved route, for the empty Alerts tab's "Next trains" (TT-193): Schedule's, while it shows today.
@MainActor
protocol NextTrainsProviding: AnyObject {
    var nextTrains: (route: Route, trips: [Trip])? { get }
}

/// No route: the empty tab shows "See trains".
@MainActor
final class NoNextTrains: NextTrainsProviding {
    init() {}
    var nextTrains: (route: Route, trips: [Trip])? { nil }
}

extension ScheduleViewModel: NextTrainsProviding {
    /// The route's trains for today, without cancelled ones; nil with no route or while another day shows.
    var nextTrains: (route: Route, trips: [Trip])? {
        guard let route, selectedDay == today else { return nil }
        let trains = departures.filter { departure in
            if case .cancelled = departure.status { return false }
            return true
        }
        return (route, trains.map(\.trip))
    }
}

extension ScheduleViewModel: LineNoticesProviding {}
