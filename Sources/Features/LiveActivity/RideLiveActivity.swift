import ActivityKit
import Foundation
import UIKit

/// The alerted train before it leaves, as the app sees it (TT-178): Schedule's live departure, or the demo departure's.
struct DepartureActivitySource {
    let live: LiveDeparture
    let route: Route
    /// Its clock: Mock time, or the demo departure's own.
    let now: Date

    /// The ride a hand-off would start on this train: the activity's identity.
    var ride: Ride { Ride(trip: live.key, from: route.from.id, to: route.to.id) }
}

/// The ride on the Lock Screen and in the Dynamic Island (TT-174, D67), and before it the alerted train's countdown (TT-178,
/// D74). It follows the app's ride engine, or the demo ride's while Demo trains › Ride plays: it starts the activity when a
/// ride starts (only with the app in front, Apple's rule; a ride restored in the background gets its activity once the app
/// is opened), updates it when what it shows changes and at least once a minute, alerts once when the train is about a
/// minute from your stop, and ends it with the ride: 15 min after the train reached your stop, at once on End ride.
///
/// Before departure the alert server starts the activity with a push-to-start at T−30 (iOS 17.2+); the app in front starts
/// it itself when none came, keeps it up to date while it runs; once the train has left the card asks "On board?" (TT-231,
/// D110: silently while the app is in front, with the alert server's buzz otherwise) and ends 10 min after the train's time,
/// or at your stop if sooner. When it is boarding and when it has left is the source's word (`LiveDeparture`, which follows
/// `BoardingRule`, TT-233, D114): nothing here goes by the train's time alone. Yes (the card's link) starts the ride, and
/// No (`DeclineDepartureIntent`) ends it. "I’m on board" turns that same activity into the ride (the hand-off), and the
/// app tells the server, which then sends nothing more. A card lives only while its alert is switched on (TT-240, D118):
/// the bell turned off, the alert removed or paused ends it at the tap (`keepsDeparture`, `alertsChanged()`). The app
/// sends the server its push-to-start token and each departure activity's update token. One per app, made by
/// `AppDelegate`; none in fixture runs (UI tests, the unit test host, previews), so nothing appears in the island while
/// they run.
@MainActor
final class RideLiveActivity: RideActivityFollowing {
    /// The activity greys itself this long after the app last updated it.
    static let staleAfter: TimeInterval = 2 * 60
    /// An update at least this often, so a running app keeps it fresh; under a minute, so the engine's minute tick on the
    /// timetable always sends one.
    static let refreshAfter: TimeInterval = 45
    /// While the app is in front, the departure is looked at this often: its phases follow the clock and the train feed
    /// (`BoardingRule`, TT-233), not the engine. Nothing here waits for the train's time: each look reads the source again.
    static let departureTick: Duration = .seconds(2)
    /// With a push-to-start token the server starts the activity at T−30; the app in front waits this long for it, so the
    /// two do not cross.
    static let serverGrace: TimeInterval = 90
    /// With the app in front this long before the train's time, or after it has left, the server asks without an alert
    /// (TT-231): told ahead of its minute cycle. Only on the clock: see `asksSilently(_:now:)`.
    static let silenceLead: TimeInterval = 75
    /// A hand-off waits this long for the server's answer before the card turns into the ride (TT-242, D120).
    nonisolated static let handOffWait: Duration = .seconds(5)
    /// A wrong train warning's hand-off the server did not take is sent again this often, up to `handOffRetries` times
    /// (TT-251, D127): with no ride and the app in the background no pass comes to send it.
    static let handOffRetryGap: Duration = .seconds(15)
    static let handOffRetries = 40

    private let app: RideEngine?
    private var demo: RideEngine?
    /// Not on it on the demo ride's card (TT-243): set by `OnBoard`.
    var demoNotOnIt: (@MainActor (Ride) -> Void)?
    /// A departure card appeared, the server's or the app's, once per card (TT-243, D120): "When the app is closed" arms
    /// the watch on it with the app in the background (`AutoRideWake.cardArrived(_:)`). Set by `AppDelegate`.
    var departureArrived: (@MainActor (Ride) -> Void)?
    /// The ride's line, for the tile: the GO feed's, or the demo's.
    private let line: @MainActor (Ride) async -> Line?
    /// A ride's stops, for a departure's activity: made with the ride's stop count, so the hand-off keeps it.
    private let plan: @MainActor (Ride) async -> RidePlan?
    private let formatter: @MainActor () -> TimeFormatter
    /// The app is in front, where an activity can start.
    private let canStart: @MainActor () -> Bool
    /// Reports a departure activity before `connect` (a background launch): straight to the server, if the installation is
    /// registered there.
    private let backgroundReport: (@Sendable (LiveActivityReport) async -> Bool)?

    private var isFollowing = false
    private var listener: Task<Void, Never>?
    private var isSyncing = false
    private var needsSync = false
    /// When the activity was last sent, to refresh it once a minute.
    private var sentAt: Date?
    /// The ride the activity was started for: one the rider swiped off the Lock Screen does not come back with the app.
    private var startedRide: Ride?
    /// The ride that has had its one alert, should the train fall back from arriving and come round to it again.
    private var alertedRide: Ride?

    // Before departure (TT-178)

    /// The live departure, once `RootView` connects.
    private var departures: (@MainActor () -> DepartureActivitySource?)?
    private var reporter: (any LiveActivityReporting)?
    /// The trains whose departure has had an activity while the app runs: one the rider swiped away does not come back.
    private var departureStarted: Set<Ride> = []
    /// A hand-off the server has not taken yet: sent again on each pass, or the server would end the ride's activity 2 min
    /// after the train left.
    private var pendingHandOff: LiveActivityReport?
    /// Sends `pendingHandOff` again after a warning's hand-off failed (`retryHandOff()`).
    private var handOffRetry: Task<Void, Never>?
    private var departureSentAt: Date?
    private var ticker: Task<Void, Never>?
    private var observesTokens = false
    /// The activities whose update tokens are followed.
    private var followedTokens: Set<String> = []
    /// The push-to-start token, hex; nil before iOS 17.2 or until iOS issues it.
    private var startToken: String?
    /// The trains the server was told to ask about silently: the app was in front as they left (TT-231).
    private var askedRides: Set<Ride> = []
    /// The train the automatic ride's watch holds the question's buzz for (TT-242, D120): no silent `asked` goes for it
    /// meanwhile, or the server would end the hold and a "can’t tell" would never buzz.
    var heldRide: Ride?
    /// The ride's arrival wish, the one the ride screen shows (TT-229, D108): `OnBoard`, from `RootView`.
    private weak var wishes: (any ArrivalWishSource)?
    /// At your stop with no wish yet: a pass a second later, since no ride event comes when the wish is due.
    private var wishWait: Task<Void, Never>?
    /// The wrong train warning on a ride's card (TT-250, D127, `show(_:for:until:alert:)`): put into the content each pass
    /// makes for that ride, or the next pass would wipe it.
    private var wrongOverlay: (ride: Ride, wrong: RideActivityAttributes.ContentState.Wrong)?
    /// T's departure card while it carries the warning (TT-251, D127): the departure pass neither updates it nor ends it at
    /// `LiveDeparture.endsAt`; its stale date is the warning's expiry.
    private var wrongDeparture: Ride?
    /// The trains whose warning was handed off to the server (once each: on the server `handedOff` is final).
    private var wrongHandedOff: Set<Ride> = []

    init(
        app: RideEngine?,
        line: @escaping @MainActor (Ride) async -> Line?,
        plan: @escaping @MainActor (Ride) async -> RidePlan? = { _ in nil },
        formatter: @escaping @MainActor () -> TimeFormatter,
        canStart: @escaping @MainActor () -> Bool,
        backgroundReport: (@Sendable (LiveActivityReport) async -> Bool)? = nil
    ) {
        self.app = app
        self.line = line
        self.plan = plan
        self.formatter = formatter
        self.canStart = canStart
        self.backgroundReport = backgroundReport
    }

    /// The engine the activity shows: the demo's while it plays, else the app's.
    private var engine: RideEngine? { demo ?? app }

    /// At launch, once the app's ride is restored: from now on the activity follows it. An activity left from a ride that
    /// is over ends here. The tokens are followed from here too, so an activity the server started while the app was closed
    /// has its token reported even when iOS wakes the app in the background for it.
    func start() {
        isFollowing = true
        followTokens()
        listen()
    }

    /// The train of the departure activity on screen, for its tap and its "I’m on board" (TT-178).
    var departureRide: Ride? {
        Activity<RideActivityAttributes>.activities
            .first { $0.content.state.isDeparture && Self.isShowing($0.activityState) }
            .map { Ride($0.attributes) }
    }

    /// `RootView`: the live departure and the alert rules, which take the tokens to the server.
    func connect(
        reporter: any LiveActivityReporting, wishes: (any ArrivalWishSource)? = nil,
        departures: @escaping @MainActor () -> DepartureActivitySource?
    ) {
        self.reporter = reporter
        self.wishes = wishes
        self.departures = departures
        if let startToken {
            Task { await self.reporter?.reportStartToken(startToken) }
        }
        sync()
    }

    /// Demo trains › Ride started or stopped (`OnBoard`).
    func follow(demo engine: RideEngine?) {
        guard engine !== demo else { return }
        demo = engine
        startedRide = nil
        alertedRide = nil
        if isFollowing { listen() }
    }

    /// The alert rules changed (`RootView`): a pass now, so the card of an alert that was just removed or switched off ends
    /// at the tap, before the app can be closed (TT-240), and a new alert's card starts without waiting for the ticker.
    func alertsChanged() {
        sync()
    }

    /// The app came to the front: a ride restored in the background gets its activity now, and the departure is followed
    /// while the app stays in front.
    func sceneDidBecomeActive() {
        sync()
        guard ticker == nil else { return }
        ticker = Task {
            repeat {
                try? await Task.sleep(for: Self.departureTick)
                sync()
            } while canStart()
            ticker = nil
        }
    }

    private func listen() {
        listener?.cancel()
        listener = nil
        sync()
        guard let engine else { return }
        let events = engine.events()
        listener = Task { [weak self] in
            for await _ in events {
                guard !Task.isCancelled else { return }
                self?.sync()
            }
        }
    }

    /// Brings the activity in line with the engine, one pass at a time.
    private func sync() {
        guard isFollowing else { return }
        needsSync = true
        guard !isSyncing else { return }
        isSyncing = true
        Task {
            while needsSync {
                needsSync = false
                await reconcile()
            }
            isSyncing = false
        }
    }

    private func reconcile() async {
        let engine = engine
        let ride = engine?.ride
        if let handOff = pendingHandOff, await report(handOff) { pendingHandOff = nil }
        let activities = Activity<RideActivityAttributes>.activities.filter { Self.isShowing($0.activityState) }
        // Another ride's activity (one that ended while the app was stopped, or the demo's) leaves at once.
        for id in activities.filter({ !$0.content.state.isDeparture && !$0.attributes.shows(ride) }).map(\.id) {
            await Self.end(id, content: nil, dismissal: nil)
        }
        if let engine, let ride, let plan = engine.plan, let state = engine.state {
            if state.phase != .ended {
                await reconcileRide(engine: engine, ride: ride, plan: plan, state: state, activities: activities)
                return
            }
            await endRide(engine: engine, ride: ride, plan: plan, state: state, activities: activities)
        }
        await reconcileDeparture(activities.filter { $0.content.state.isDeparture })
    }

    /// A ride runs: its activity, which may be the train's departure activity (the hand-off), else a new one.
    private func reconcileRide(
        engine: RideEngine, ride: Ride, plan: RidePlan, state: RideState, activities: [Activity<RideActivityAttributes>]
    ) async {
        // The ride wins over another train's countdown; this train's becomes the ride when its bar has the ride's stops.
        let fits = { (activity: Activity<RideActivityAttributes>) in
            activity.attributes.shows(ride) && (!activity.content.state.isDeparture || activity.attributes.stopCount == plan.stops.count)
        }
        for activity in activities where activity.content.state.isDeparture && !fits(activity) {
            await Self.end(activity.id, content: nil, dismissal: nil)
            // This train's, with another stop count: the ride gets its own activity, and the server leaves this one.
            if activity.attributes.shows(ride) { await handOff(LiveActivityReport(activity.attributes, handedOff: true)) }
        }
        let deviceNow = Date()
        guard var content = RideActivityAttributes.ContentState(
            plan: plan, state: state, now: engine.now, deviceNow: deviceNow, formatter: formatter(), wish: dueWish(at: state)
        ) else { return }
        // Not on it for the ride's first 10 min after it started by itself (TT-243, D120); the pass after the window, at
        // the latest the 45 s refresh, takes it away.
        content.undoable = engine.autoUndoUntil.map { engine.now < $0 } ?? false
        // The wrong train warning while it shows (TT-250, D127): wins over the rest of the card.
        if let overlay = wrongOverlay, overlay.ride == ride { content.wrong = overlay.wrong }
        let current = activities.first(where: fits)
        let staleDate = deviceNow.addingTimeInterval(Self.staleAfter)
        if let current {
            let shown = current.content.state
            guard Self.needsUpdate(from: shown, to: content, sentAt: shown.isDeparture ? nil : sentAt, now: deviceNow) else { return }
            let id = current.id
            let show: @MainActor () async -> Void = {
                self.sentAt = deviceNow
                let alerts = Self.alerts(from: shown, to: content) && self.alertedRide != ride
                if alerts { self.alertedRide = ride }
                await Self.update(
                    id, content: content, staleDate: staleDate,
                    alert: alerts ? WrongTrainAlert(title: content.title, body: "") : nil
                )
                if content.wish != nil { self.wishes?.wishReachedLockScreen() }
            }
            if shown.isDeparture {
                // The hand-off: the same activity now shows the ride, and the server leaves it to the app. Ended later,
                // the ride does not bring the countdown back. The server hears it first (TT-242, D120), for at most 5 s,
                // so a cycle in flight cannot turn the ride card back into the question.
                startedRide = ride
                departureStarted.insert(ride)
                let handOff = LiveActivityReport(current.attributes, handedOff: true)
                let reached = await Self.handOff(report: { await self.report(handOff) }, wait: Self.handOffWait, then: show)
                if !reached { pendingHandOff = handOff }
            } else {
                await show()
            }
        } else {
            guard startedRide != ride, canStart(), ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            let line = await line(ride)
            // The ride may have moved on while the line was looked up; the next pass starts it then.
            guard engine.ride == ride, engine.state?.phase != .ended,
                  !Activity<RideActivityAttributes>.activities.contains(where: { $0.attributes.shows(ride) && Self.isShowing($0.activityState) })
            else { return }
            do {
                _ = try Activity.request(
                    attributes: RideActivityAttributes(ride: ride, plan: plan, line: line),
                    content: ActivityContent(state: content, staleDate: staleDate)
                )
                sentAt = deviceNow
                startedRide = ride
                if content.isAlert { alertedRide = ride }
                if content.wish != nil { wishes?.wishReachedLockScreen() }
            } catch {
                // Live Activities are off for the app, or it went to the background: the next pass in front tries again.
            }
        }
    }

    /// The ride ended: its activity leaves the Lock Screen with it, also after an arrival, when the ride screen closes too
    /// (TT-223, D103: 2 min after your stop).
    private func endRide(
        engine: RideEngine, ride: Ride, plan: RidePlan, state: RideState, activities: [Activity<RideActivityAttributes>]
    ) async {
        // The same trip can be ridden again: it gets a new activity and a new alert. A warning ends with its ride.
        startedRide = nil
        alertedRide = nil
        if wrongOverlay?.ride == ride { wrongOverlay = nil }
        let deviceNow = Date()
        guard let current = activities.first(where: { !$0.content.state.isDeparture && $0.attributes.shows(ride) }),
              let content = RideActivityAttributes.ContentState(
                  plan: plan, state: state, now: engine.now, deviceNow: deviceNow, formatter: formatter(), wish: dueWish(at: state)
              )
        else { return }
        sentAt = nil
        await Self.end(current.id, content: content, dismissal: nil)
    }

    /// The arrival wish at your stop once it is due (TT-229, D108); until then a pass each second looks again, as nothing
    /// else changes at your stop. The ride ends 2 min after your stop, which ends the wait.
    private func dueWish(at state: RideState) -> ArrivalWish? {
        guard let wishes else { return nil }
        switch state.phase {
        case .atYourStop:
            if let wish = wishes.arrivalWish { return wish }
            if wishWait == nil {
                wishWait = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(1))
                    self?.wishWait = nil
                    self?.sync()
                }
            }
            return nil
        case .ended:
            return wishes.arrivalWish
        case .riding, .atStation, .yourStopNext, .arriving:
            return nil
        }
    }

    /// No ride runs: the alerted train's countdown (TT-178), then its question (TT-231). Whoever started it, it ends 10 min
    /// after the train's time or at your stop (its stale date, where the source's window ends too), and at once when its
    /// alert is removed or switched off (TT-240); the app keeps the live departure's up to date and starts it when none
    /// came.
    private func reconcileDeparture(_ activities: [Activity<RideActivityAttributes>]) async {
        let deviceNow = Date()
        let source = departures?()
        var current: [Activity<RideActivityAttributes>] = []
        var removed: [RideActivityAttributes] = []
        for activity in activities {
            let card = Ride(activity.attributes)
            if let stale = activity.content.staleDate, stale <= deviceNow {
                await Self.end(activity.id, content: nil, dismissal: nil)
            } else if !Self.keepsDeparture(
                card, source: source?.ride, hasAlert: reporter?.hasAlert(for: card), warned: wrongDeparture
            ) {
                // Its alert is gone (TT-240, D118): nothing would update the card again, so it leaves now. Forgotten here,
                // so Undo or a new bell tap starts it again when it is the source's train, and tells the server again that
                // the question is silent (TT-231) if it comes back in the last 75 s.
                departureStarted.remove(card)
                askedRides.remove(card)
                await Self.end(activity.id, content: nil, dismissal: nil)
                removed.append(activity.attributes)
            } else {
                current.append(activity)
            }
        }
        // The server is told the card was removed (never handed off, which would silence it for the train after an Undo):
        // it follows the card no more, and starts a fresh one when the alert is switched on again, whatever Schedule shows.
        // Told once: if it fails, the server's sweep ends what it still holds for the card in its next minute.
        for attributes in removed {
            await report(LiveActivityReport(attributes, removed: true))
        }
        guard let source else { return }
        let ride = source.ride
        let content = RideActivityAttributes.ContentState(
            departure: source.live, now: source.now, deviceNow: deviceNow, formatter: formatter()
        )
        let staleDate = Self.departureStaleDate(source.live, now: source.now, deviceNow: deviceNow)
        // With the app in front as the train leaves, the question comes silently (TT-231, D110): Schedule asks with its own
        // strip. The server is told shortly before the departure, ahead of its minute cycle, and then sends the question
        // with no alert, and no notification. A train the feed places is told only once it has left (TT-233).
        // Not while the automatic ride's watch holds this train (TT-242, D120): its outcome says what the server does.
        if canStart(),
           Self.tellsSilently(ride, held: heldRide, live: source.live, now: source.now, warned: wrongHandedOff.contains(ride)),
           askedRides.insert(ride).inserted {
            let silent = LiveActivityReport(
                tripId: ride.tripId, serviceDate: String(ride.serviceDate), originId: ride.originId,
                destinationId: ride.destinationId, asked: true
            )
            // Told once: a report that fails only costs the server's buzz, which iOS does not show over the app.
            await report(silent)
        }
        let mine = current.filter { $0.attributes.shows(ride) }
        // The wrong train warning is on this train's card (TT-251, D127): it stays as the warning left it.
        if wrongDeparture == ride { return }
        if let shown = mine.first {
            departureStarted.insert(ride)
            // The server's start and the app's crossed: one stays, and its token is the one the server updates.
            for extra in mine.dropFirst() {
                await Self.end(extra.id, content: nil, dismissal: nil)
            }
            if mine.count > 1, let token = shown.pushToken {
                await report(LiveActivityReport(shown.attributes, token: Self.hex(token)))
            }
            guard Self.needsUpdate(from: shown.content.state, to: content, sentAt: departureSentAt, now: deviceNow) else { return }
            departureSentAt = deviceNow
            // The app's own update never alerts: the question's buzz is the alert server's (TT-231).
            await Self.update(shown.id, content: content, staleDate: staleDate, alert: nil)
            return
        }
        // Started by the app in front, once a window, and not once the train has left.
        guard !departureStarted.contains(ride), source.live.phase != .departed, canStart(),
              ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if startToken != nil, source.live.leaves.timeIntervalSince(source.now) > LiveDeparture.window - Self.serverGrace { return }
        guard let plan = await plan(ride), plan.stops.count >= 2 else { return }
        let line = await line(ride)
        guard departures?()?.ride == ride,
              !Activity<RideActivityAttributes>.activities.contains(where: { $0.attributes.shows(ride) && Self.isShowing($0.activityState) })
        else { return }
        let attributes = RideActivityAttributes(ride: ride, plan: plan, line: line)
        let activityContent = ActivityContent(state: content, staleDate: staleDate)
        // With an update token the server can update and end it once the app is closed.
        guard let activity = (try? Activity.request(attributes: attributes, content: activityContent, pushType: .token))
            ?? (try? Activity.request(attributes: attributes, content: activityContent))
        else { return }
        departureStarted.insert(ride)
        departureSentAt = deviceNow
        followToken(of: activity.id)
        await report(LiveActivityReport(attributes))
    }

    // MARK: Tokens (TT-178)

    /// The push-to-start token (iOS 17.2+), new activities (the server's starts) and each departure activity's update token.
    private func followTokens() {
        guard !observesTokens else { return }
        observesTokens = true
        if #available(iOS 17.2, *) {
            Task { [weak self] in
                await Self.startTokens { [weak self] token in await self?.received(startToken: token) }
            }
        }
        Task { [weak self] in
            await Self.newActivities { [weak self] id in await self?.followToken(of: id) }
        }
        for activity in Activity<RideActivityAttributes>.activities {
            followToken(of: activity.id)
        }
    }

    private func received(startToken token: String) async {
        startToken = token
        await reporter?.reportStartToken(token)
    }

    private func followToken(of id: String) {
        guard followedTokens.insert(id).inserted else { return }
        if let activity = Activity<RideActivityAttributes>.activities.first(where: { $0.id == id }),
           activity.content.state.isDeparture, Self.isShowing(activity.activityState) {
            departureArrived?(Ride(activity.attributes))
        }
        Task { [weak self] in
            await Self.pushTokens(of: id) { [weak self] token in await self?.received(token: token, of: id) }
        }
    }

    /// A departure activity's update token goes to the server; a ride's is not needed (the app updates the ride).
    private func received(token: String, of id: String) async {
        guard let activity = Activity<RideActivityAttributes>.activities.first(where: { $0.id == id }),
              activity.content.state.isDeparture else { return }
        await report(LiveActivityReport(activity.attributes, token: token))
    }

    /// True once the server has it.
    @discardableResult
    private func report(_ activity: LiveActivityReport) async -> Bool {
        if let reporter { return await reporter.report(activity) }
        return await backgroundReport?(activity) ?? true
    }

    /// The hand-off must reach the server: kept until it does.
    private func handOff(_ activity: LiveActivityReport) async {
        if await !report(activity) { pendingHandOff = activity }
    }

    /// A warning's hand-off (TT-251, D127): kept and sent again on its own every `handOffRetryGap`, since the passes that
    /// send `pendingHandOff` come only with a ride or the app in front.
    private func retryHandOff() {
        guard handOffRetry == nil, pendingHandOff != nil else { return }
        handOffRetry = Task { [weak self] in
            for _ in 0..<Self.handOffRetries {
                try? await Task.sleep(for: Self.handOffRetryGap)
                guard !Task.isCancelled, let self, let pending = self.pendingHandOff else { break }
                if await self.report(pending), self.pendingHandOff == pending { self.pendingHandOff = nil }
            }
            self?.handOffRetry = nil
        }
    }

    /// The hand-off's order (TT-242, D120): the server hears it first, its answer awaited for at most `wait`, and only then
    /// does the card turn into the ride (`update`). True when the server had it in time; the caller keeps one that did not
    /// come back and sends it again on each pass, as a failed one.
    static func handOff(
        report: @escaping @Sendable () async -> Bool, wait: Duration, then update: @MainActor () async -> Void
    ) async -> Bool {
        // A race that does not wait for the loser: a task group would, and a report stuck on something that ignores
        // cancellation (the APNs token's own 10 s wait) would hold the card past `wait`.
        let sent = await withCheckedContinuation { (continuation: CheckedContinuation<Bool?, Never>) in
            let first = FirstAnswer(continuation)
            first.reporting = Task { @MainActor in first.give(await report()) }
            first.timer = Task { @MainActor in
                try? await Task.sleep(for: wait)
                first.give(nil)
            }
        }
        await update()
        return sent == true
    }

    /// The hand-off's race: the first answer, the server's or the time limit's, wins; the other is cancelled.
    @MainActor
    private final class FirstAnswer {
        private var continuation: CheckedContinuation<Bool?, Never>?
        var reporting: Task<Void, Never>?
        var timer: Task<Void, Never>?

        init(_ continuation: CheckedContinuation<Bool?, Never>) { self.continuation = continuation }

        func give(_ answer: Bool?) {
            guard let continuation else { return }
            self.continuation = nil
            continuation.resume(returning: answer)
            if answer == nil { reporting?.cancel() } else { timer?.cancel() }
        }
    }

    /// The automatic ride's watch reports its hold and its outcome (TT-242, D120), through the alert rules once connected,
    /// else straight to the server, as the card's own reports go. True once the server has it.
    func reportHold(_ activity: LiveActivityReport) async -> Bool {
        await report(activity)
    }

    // MARK: ActivityKit

    // An `Activity` is not Sendable, so its async calls run off the main actor, on an activity looked up there by id.

    /// `alert`: the update alerts with these words and the system's default sound (the arriving alert: the card's title; the
    /// wrong train's five: "Wrong train?" and the notification's body, TT-250).
    private nonisolated static func update(
        _ id: String, content: RideActivityAttributes.ContentState, staleDate: Date, alert: WrongTrainAlert?
    ) async {
        guard let activity = Activity<RideActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        let configuration = alert.map {
            AlertConfiguration(
                title: LocalizedStringResource(stringLiteral: $0.title),
                body: LocalizedStringResource(stringLiteral: $0.body),
                sound: .default
            )
        }
        await activity.update(ActivityContent(state: content, staleDate: staleDate), alertConfiguration: configuration)
    }

    /// Ends the activity with its last content, leaving the Lock Screen at `dismissal`, or at once with none.
    private nonisolated static func end(_ id: String, content: RideActivityAttributes.ContentState?, dismissal: Date?) async {
        guard let activity = Activity<RideActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.end(
            content.map { ActivityContent(state: $0, staleDate: nil) },
            dismissalPolicy: dismissal.map { .after($0) } ?? .immediate
        )
    }

    @available(iOS 17.2, *)
    private nonisolated static func startTokens(_ received: @escaping @Sendable (String) async -> Void) async {
        for await token in Activity<RideActivityAttributes>.pushToStartTokenUpdates {
            await received(hex(token))
        }
    }

    private nonisolated static func newActivities(_ found: @escaping @Sendable (String) async -> Void) async {
        for await activity in Activity<RideActivityAttributes>.activityUpdates {
            await found(activity.id)
        }
    }

    private nonisolated static func pushTokens(of id: String, _ received: @escaping @Sendable (String) async -> Void) async {
        guard let activity = Activity<RideActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        for await token in activity.pushTokenUpdates {
            await received(hex(token))
        }
    }

    // MARK: The rules

    private nonisolated static func isShowing(_ state: ActivityState) -> Bool {
        state == .active || state == .stale
    }

    /// An APNs token as the server keeps it: lowercase hex.
    nonisolated static func hex(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }

    /// Something a rider would see changed, or the last update is a minute old.
    static func needsUpdate(
        from shown: RideActivityAttributes.ContentState, to next: RideActivityAttributes.ContentState, sentAt: Date?, now: Date
    ) -> Bool {
        guard let sentAt, now.timeIntervalSince(sentAt) < refreshAfter else { return true }
        return !shown.looksLike(next)
    }

    /// The one alert of a ride: the train is now about a minute from your stop.
    static func alerts(from shown: RideActivityAttributes.ContentState, to next: RideActivityAttributes.ContentState) -> Bool {
        next.phase == .arriving && shown.phase != .arriving
    }

    /// A departure's card stays only while something stands behind it (TT-240, D118): it is the source's own train (the
    /// one the app keeps up to date; the demo departure's has no alert), or a switched-on alert covers it
    /// (`AlertRules.hasAlert(for:)`). The rules are asked about the card itself, never "there is no source": the source is
    /// also nil while another day is picked, the route is turned or Schedule has not loaded, and none of those may end a
    /// card whose alert is on. `hasAlert` is nil before `RootView` connects the rules (a background launch): nothing ends.
    /// A card carrying the wrong train warning (`warned`, TT-251) stays until the warning leaves it.
    static func keepsDeparture(_ card: Ride, source: Ride?, hasAlert: Bool?, warned: Ride? = nil) -> Bool {
        card == source || card == warned || hasAlert != false
    }

    /// A departure's activity goes stale, and ends, 10 min after the train's time or at your stop if sooner, on the device
    /// clock (the server sets the same stale date). That is where `LiveDeparture`'s window ends, also for a train that
    /// stood at its platform past its time (TT-233), so the card never ends while the source still has the train.
    static func departureStaleDate(_ live: LiveDeparture, now: Date, deviceNow: Date) -> Date {
        deviceNow.addingTimeInterval(live.endsAt.timeIntervalSince(now))
    }

    /// The server is told to ask silently (TT-231), unless the automatic ride's watch holds this train (TT-242, D120): then
    /// its outcome says what the server does, or a "can’t tell" would never buzz.
    /// Nor once the wrong train warning was handed off for it (`warned`, TT-251, D127): nothing asks about that train again.
    static func tellsSilently(_ ride: Ride, held: Ride?, live: LiveDeparture, now: Date, warned: Bool = false) -> Bool {
        !warned && held != ride && asksSilently(live, now: now)
    }

    /// The app in front tells the server to ask "On board?" without an alert (TT-231) when the question is near as far as
    /// the source knows (TT-233, D114): once the train has left, and before that only on the clock, within `silenceLead`
    /// of its time with no position to go by. A train the feed places leaves when it moves off or the feed drops the
    /// station, not at its time, so nothing is told ahead for it: told 75 s before its time, a rider who put the phone away
    /// while the train still stood at the platform would get the question minutes later with no buzz. Told late instead
    /// (the server's minute cycle saw the train leave first), the cost is the server's buzz over the open app.
    static func asksSilently(_ live: LiveDeparture, now: Date) -> Bool {
        if live.phase == .departed { return true }
        guard !BoardingRule.hasSighting(of: live.departure, now: now) else { return false }
        return live.leaves.timeIntervalSince(now) <= silenceLead
    }

    // MARK: The departure question (TT-231, D110)

    /// No on Schedule's strip: the card leaves the Lock Screen and the server sends nothing more for it (the hand-off's
    /// report, which stops its updates).
    func declineDeparture(_ ride: Ride) {
        departureStarted.insert(ride)
        Task {
            for activity in Activity<RideActivityAttributes>.activities where activity.attributes.shows(ride) {
                let report = LiveActivityReport(activity.attributes, handedOff: true)
                await Self.end(activity.id, content: nil, dismissal: nil)
                await handOff(report)
            }
        }
    }

    /// No on the card (`DeclineDepartureIntent`, which ended it) or on the notification: the server sends nothing more.
    func declined(_ train: DeclinedDeparture) {
        departureStarted.insert(Ride(train))
        let report = LiveActivityReport(
            tripId: train.tripId, serviceDate: String(train.serviceDate), originId: train.originId,
            destinationId: train.destinationId, handedOff: true
        )
        Task { await handOff(report) }
    }
}

extension LiveActivityReport {
    /// The activity's train, as the server keys its watch.
    init(_ attributes: RideActivityAttributes, token: String? = nil, handedOff: Bool = false, removed: Bool = false) {
        self.init(
            tripId: attributes.tripId, serviceDate: String(attributes.serviceDate), originId: attributes.originId,
            destinationId: attributes.destinationId, token: token, handedOff: handedOff, removed: removed
        )
    }
}

extension Ride {
    /// The train a No was about (TT-231).
    init(_ train: DeclinedDeparture) {
        self.init(
            trip: TripKey(serviceDay: ServiceDay(dateKey: train.serviceDate), tripId: train.tripId),
            from: train.originId, to: train.destinationId
        )
    }

    /// The ride an activity shows.
    init(_ attributes: RideActivityAttributes) {
        self.init(
            trip: TripKey(serviceDay: ServiceDay(dateKey: attributes.serviceDate), tripId: attributes.tripId),
            from: attributes.originId, to: attributes.destinationId
        )
    }
}

extension RideLiveActivity {
    /// The app's: the GO feed's lines and stops and the Time format setting. Nil in fixture runs.
    static func app(following ride: RideEngine, environment: [String: String] = ProcessInfo.processInfo.environment) -> RideLiveActivity? {
        guard !ScheduleDependencies.isFixtureRun(environment) else { return nil }
        let stations = ScheduleDependencies.app(environment: environment).stations
        let installationKey = AlertRules.installationKey
        return RideLiveActivity(
            app: ride,
            line: { ride in
                if ride.tripId == DemoRide.tripId { return DemoRide.line }
                guard let all = try? await stations.stations(),
                      let from = all.first(where: { $0.id == ride.originId }),
                      let to = all.first(where: { $0.id == ride.destinationId }) else { return nil }
                return try? await stations.route(from: from, to: to).line
            },
            plan: { [ride] trip in
                if trip.tripId == DemoRide.tripId { return DemoRide.plan(on: trip.tripKey.serviceDay) }
                return await ride.plan(for: trip)
            },
            formatter: {
                let stored = UserDefaults.standard.string(forKey: AppSettings.timeFormatKey).flatMap(TimeFormat.init(rawValue:))
                return TimeFormatter(format: stored ?? .device)
            },
            canStart: { UIApplication.shared.applicationState == .active },
            backgroundReport: { report in
                // Only an installation the server knows: it registered with the rider's first alert.
                guard let installation = UserDefaults.standard.string(forKey: installationKey) else { return true }
                do {
                    try await HTTPAlertServer().report(report, installation: installation)
                    return true
                } catch {
                    return false
                }
            }
        )
    }
}

extension RideLiveActivity: AutoRideHolding {}

// MARK: Wrong train (TT-250, D127)

extension RideLiveActivity: WrongTrainShowing {
    /// Puts the warning on `ride`'s card (nil takes it away) and updates the card at once, alerting with `alert`; every pass
    /// after it keeps it. A ride card keeps its own stale date. On T's departure card (TT-251, D127, no ride) the server
    /// hears `handedOff` first, as at a ride's start, since its next push would wipe the warning and its "On board?" would
    /// buzz over it; the card's stale date is then `until`, the warning's expiry, and once the warning leaves the card ends
    /// (the server never follows a handed-off card again). With no card the hand-off is reported all the same, so no
    /// "On board?" comes for that train. False when no showing card is that ride's or Live Activities are off.
    func show(
        _ wrong: RideActivityAttributes.ContentState.Wrong?, for ride: Ride, until: Date?, alert: WrongTrainAlert?
    ) async -> Bool {
        if let wrong {
            wrongOverlay = (ride, wrong)
        } else if wrongOverlay?.ride == ride {
            wrongOverlay = nil
        }
        let showing = ActivityAuthorizationInfo().areActivitiesEnabled
            ? Activity<RideActivityAttributes>.activities.filter { Self.isShowing($0.activityState) && $0.attributes.shows(ride) }
            : []
        if let activity = showing.first(where: { !$0.content.state.isDeparture }) {
            var content = activity.content.state
            content.wrong = wrong
            let staleDate = activity.content.staleDate ?? Date().addingTimeInterval(Self.staleAfter)
            await Self.update(activity.id, content: content, staleDate: staleDate, alert: alert)
            return true
        }
        let departure = showing.first(where: { $0.content.state.isDeparture })
        guard let wrong else {
            // The warning left T's departure card: the card ends with it.
            guard let departure, wrongDeparture == ride || departure.content.state.wrong != nil else {
                if wrongDeparture == ride { wrongDeparture = nil }
                return false
            }
            wrongDeparture = nil
            departureStarted.insert(ride)
            await Self.end(departure.id, content: nil, dismissal: nil)
            return true
        }
        guard let departure else {
            // No card: the notification goes at once, the hand-off on its own.
            if wrongHandedOff.insert(ride).inserted {
                let report = LiveActivityReport(
                    tripId: ride.tripId, serviceDate: String(ride.serviceDate), originId: ride.originId,
                    destinationId: ride.destinationId, handedOff: true
                )
                Task {
                    await self.handOff(report)
                    self.retryHandOff()
                }
            }
            return false
        }
        wrongDeparture = ride
        departureStarted.insert(ride)
        var content = departure.content.state
        content.wrong = wrong
        let staleDate = until ?? departure.content.staleDate ?? Date().addingTimeInterval(Self.staleAfter)
        let id = departure.id
        let update: @MainActor () async -> Void = { await Self.update(id, content: content, staleDate: staleDate, alert: alert) }
        if wrongHandedOff.insert(ride).inserted {
            let report = LiveActivityReport(departure.attributes, handedOff: true)
            let reached = await Self.handOff(report: { await self.report(report) }, wait: Self.handOffWait, then: update)
            if !reached {
                pendingHandOff = report
                retryHandOff()
            }
        } else {
            await update()
        }
        return true
    }
}
