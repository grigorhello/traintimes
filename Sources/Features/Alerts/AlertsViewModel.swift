import Foundation
import Observation

/// The Alerts tab (TT-143): every rule with its true state first, then the train updates delivered in the last 7 days,
/// then today's line notices, kept apart so a notice never reads as a trip update. Rules, saving and the server live in
/// `AlertRules` (TT-141); this model orders and words the rows, and pauses, deletes and restores rules.
@Observable @MainActor
final class AlertsViewModel {
    /// A rule's state as its row shows it (the requirements' rule state table).
    typealias RowState = AlertSetupViewModel.SheetState

    struct RuleRow: Identifiable, Equatable {
        enum Accessory: Equatable {
            /// On, Paused or Setting up: the switch pauses or resumes the rule; it waits while Setting up.
            case toggle(isOn: Bool, isEnabled: Bool)
            /// Review needed, Could not save or Notifications off: the row opens Alert setup.
            case chevron
        }

        let id: AlertRule.ID
        /// "7:32 AM · Oakville to Union".
        let title: String
        /// "Mon to Fri", "Today only" or "Fri, Nov 6"; "Mon to Fri · No matching train today" on such a day.
        let days: String
        let state: RowState
        let accessory: Accessory
        /// For UI tests: "alerts.rule.trip.LW-0732-20261105".
        let testID: String
    }

    struct UpdateRow: Identifiable, Equatable {
        let id: AlertUpdate.ID
        let kind: AlertUpdate.Kind
        /// "7:32 AM train delayed 9 min".
        let title: String
        let body: String
        /// "Today, 7:29 AM".
        let time: String
        /// Trip details for that trip and service date; nil once that service day has passed.
        let link: NotificationLink?
    }

    struct NoticeRow: Identifiable, Equatable {
        let id: String
        /// "Lakeshore West".
        let line: String
        /// "Delays of up to 15 min near Port Credit, as reported at 7:12 AM."
        let summary: String
        /// "Today, 7:12 AM".
        let time: String
    }

    let rules: AlertRules
    /// The rule just deleted, for the undo toast's 5 s; its row is hidden at once.
    private(set) var deleted: AlertRule?
    /// Switches flipped whose save is in flight: the row reads Setting up with the switch at its new place.
    private var switching: [AlertRule.ID: Bool] = [:]
    /// The rules needing review the rider has seen on the tab; any other turns the tab dot on.
    private var seenReviews: Set<AlertRule.ID> = []

    private let updates: AlertUpdates
    private let notices: any LineNoticesProviding
    private let clock: any AppClock
    private let toastDuration: Duration
    @ObservationIgnored private var deletedIndex = 0
    @ObservationIgnored private var deleteTask: Task<Void, Never>?
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    init(
        rules: AlertRules, updates: AlertUpdates, notices: any LineNoticesProviding, clock: any AppClock,
        toastDuration: Duration = .seconds(5)
    ) {
        self.rules = rules
        self.updates = updates
        self.notices = notices
        self.clock = clock
        self.toastDuration = toastDuration
    }

    // MARK: Rows

    /// No rule to list: the empty state shows.
    var isEmpty: Bool { listedRules.isEmpty }

    func ruleRows(_ formatter: some TimeFormatting) -> [RuleRow] {
        let today = self.today
        return listedRules.enumerated()
            .map { index, rule in (index, rule, rowState(rule)) }
            .sorted { ($0.2.rank, $0.0) < ($1.2.rank, $1.0) }
            .map { _, rule, state in
                let isOn = switching[rule.id] ?? !rule.paused
                let accessory: RuleRow.Accessory = switch state {
                case .on, .paused, .settingUp: .toggle(isOn: isOn, isEnabled: state != .settingUp)
                case .reviewNeeded, .couldNotSave, .notificationsOff: .chevron
                }
                return RuleRow(
                    id: rule.id,
                    title: String(format: String(localized: "alerts.rule.title"), formatter.time(rule.scheduledDeparture), routeName(rule)),
                    days: days(rule, today: today),
                    state: state,
                    accessory: accessory,
                    testID: "alerts.rule.\(rule.kind.rawValue).\(rule.tripId)"
                )
            }
    }

    func updateRows(_ formatter: some TimeFormatting) -> [UpdateRow] {
        let now = clock.now
        let today = self.today
        return updates.updates
            .filter { now.timeIntervalSince($0.deliveredAt) < AlertUpdates.window }
            .map { update in
                let link = update.link.flatMap { $0.target(today: today) == .alerts ? nil : $0 }
                return UpdateRow(
                    id: update.id, kind: update.kind, title: update.title, body: update.body,
                    time: Self.stamp(update.deliveredAt, now: now, formatter: formatter), link: link
                )
            }
    }

    func noticeRows(_ formatter: some TimeFormatting) -> [NoticeRow] {
        let now = clock.now
        return notices.lineNotices.map { notice in
            NoticeRow(
                id: notice.id,
                line: notice.lineName,
                summary: String(format: String(localized: "alerts.notice.summary"), notice.text, formatter.time(notice.reportedAt)),
                time: Self.stamp(notice.reportedAt, now: now, formatter: formatter)
            )
        }
    }

    // MARK: Actions

    /// The switch: pauses or resumes the rule on device and on the server (Setting up, then Paused or On).
    @discardableResult
    func setOn(_ isOn: Bool, for id: AlertRule.ID) -> Task<Void, Never>? {
        guard var rule = rules.rules.first(where: { $0.id == id }), rule.paused == isOn else { return nil }
        rule.paused = !isOn
        switching[id] = isOn
        return Task { [rule] in
            await rules.save(rule)
            switching[id] = nil
        }
    }

    /// A row that needs action opens Alert setup for its rule.
    func setupRequest(for id: AlertRule.ID) -> AlertSetupRequest? {
        rules.rules.first { $0.id == id }?.setupRequest
    }

    /// Swipe to delete: the row goes at once, the rule is deleted on device and on the server, and "Alert deleted · Undo"
    /// shows for 5 s.
    @discardableResult
    func delete(_ id: AlertRule.ID) -> Task<Void, Never>? {
        guard let index = rules.rules.firstIndex(where: { $0.id == id }) else { return nil }
        deleted = rules.rules[index]
        deletedIndex = index
        let previous = deleteTask
        let task = Task {
            await previous?.value
            await rules.delete(id)
        }
        deleteTask = task
        hideToast(after: toastDuration)
        return task
    }

    /// Puts the deleted rule back where it was and saves it on the server again, with the same id.
    func undo() async {
        guard let rule = deleted else { return }
        hideTask?.cancel()
        let index = deletedIndex
        await deleteTask?.value
        // A second tap while the delete finished has nothing left to restore.
        guard deleted == rule else { return }
        deleted = nil
        await rules.restore(rule, at: index)
    }

    /// The permission, the server's rule states and the notifications delivered since the last look.
    func refresh() async {
        await rules.refresh()
        await updates.refresh()
    }

    // MARK: Tab dot

    /// The accent dot on the Alerts tab icon: a rule needs review that the rider has not seen on the tab yet.
    var showsTabDot: Bool {
        !reviewIDs.isSubset(of: seenReviews)
    }

    /// The rider opened the tab: the rules needing review now are seen.
    func markReviewsSeen() {
        let ids = reviewIDs
        if ids != seenReviews { seenReviews = ids }
    }

    // MARK: Private

    private var today: ServiceDay { ServiceDay(containing: clock.now) }

    /// Every rule except the one just deleted and This-trip rules for a past service day, whose train has gone.
    private var listedRules: [AlertRule] {
        let today = self.today
        return rules.rules.filter { rule in
            rule.id != deleted?.id && (rule.kind == .repeating || (rule.trip?.serviceDay ?? today) >= today)
        }
    }

    private var reviewIDs: Set<AlertRule.ID> {
        Set(listedRules.filter { rules.state(of: $0) == .reviewNeeded }.map(\.id))
    }

    private func rowState(_ rule: AlertRule) -> RowState {
        if switching[rule.id] != nil { return .settingUp }
        return RowState(rules.state(of: rule), paused: rule.paused)
    }

    private func routeName(_ rule: AlertRule) -> String {
        String(format: String(localized: "schedule.route_title"), rule.origin.name, rule.destination.name)
    }

    /// "Mon to Fri" for Repeat; "Today only" or the date for This trip.
    private func days(_ rule: AlertRule, today: ServiceDay) -> String {
        switch rule.kind {
        case .repeating:
            let days = AlertSetupViewModel.summary(of: Set(rule.weekdays)) ?? ""
            guard rules.hasNoMatchingTrain(rule, on: today) else { return days }
            return String(format: String(localized: "alerts.no_train_today"), days)
        case .thisTrip:
            guard let day = rule.trip?.serviceDay, day != today else { return String(localized: "alerts.today_only") }
            return day.shortLabel
        }
    }

    private func hideToast(after duration: Duration) {
        hideTask?.cancel()
        let rule = deleted
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self, self.deleted == rule else { return }
            self.deleted = nil
        }
    }

    /// "Today, 7:29 AM", "Yesterday, 4:48 PM", else "Mon, Nov 2, 4:48 PM", by the calendar day in Toronto.
    static func stamp(_ date: Date, now: Date, formatter: some TimeFormatting) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = goTimeZone
        let time = formatter.time(date)
        if calendar.isDate(date, inSameDayAs: now) {
            return String(format: String(localized: "alerts.time.today"), time)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return String(format: String(localized: "alerts.time.yesterday"), time)
        }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let day = ServiceDay(year: parts.year ?? 0, month: parts.month ?? 1, day: parts.day ?? 1)
        return String(format: String(localized: "alerts.time.day"), day.shortLabel, time)
    }
}

private extension AlertSetupViewModel.SheetState {
    /// Review needed and Could not save first, then Setting up, On, Paused and Notifications off.
    var rank: Int {
        switch self {
        case .reviewNeeded, .couldNotSave: 0
        case .settingUp: 1
        case .on: 2
        case .paused: 3
        case .notificationsOff: 4
        }
    }
}

extension ScheduleViewModel: LineNoticesProviding {}
