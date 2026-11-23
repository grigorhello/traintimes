import Foundation
import Observation

/// What the automatic ride's watch reads about its train every look: the train as Schedule would resolve it, for L (its
/// expected departure) and whether it has left (`BoardingRule`).
protocol AutoRideDepartureReading: Sendable {
    /// `trip` resolved with the live status of `ride`'s route at `now`; nil when no fresh live status can be read.
    func departure(of trip: Trip, ride: Ride, at now: Date) async -> Departure?
}

/// The app's: GO's live status for the ride's own route, read from the feed before `withTesting()` (`widgetData`), so
/// Demo trains, Live data and Mock time never reach it.
struct ScheduleDepartureReading: AutoRideDepartureReading {
    let repository: any ScheduleRepository

    func departure(of trip: Trip, ride: Ride, at now: Date) async -> Departure? {
        // The repository reads a route by its two stations' ids.
        let route = Route(from: Station(id: ride.originId, name: ""), to: Station(id: ride.destinationId, name: ""), line: nil)
        guard let live = try? await repository.liveStatus(for: route, on: trip.key.serviceDay) else { return nil }
        let freshness = Freshness(live, now: now)
        // Only fresh live status says L and whether the train left: an offline or stale read resolves to the timetable,
        // which would put a late train's L back and stamp leftAt before it moved. The watch keeps its last L instead.
        guard freshness.isLive else { return nil }
        return Departure.resolve([trip], live: live, freshness: freshness, isToday: true).first
    }
}

/// Where the watch tells the alert server to hold the question's buzz (TT-242, D120): the Live Activity.
@MainActor
protocol AutoRideHolding: AnyObject {
    /// The train of the departure card on the phone.
    var departureRide: Ride? { get }
    /// Set while the watch holds that train: no silent `asked` goes for it meanwhile.
    var heldRide: Ride? { get set }
    /// True once the server has the report.
    func reportHold(_ activity: LiveActivityReport) async -> Bool
}

/// Rides start by themselves, part 1 (TT-242, D120): for an alerted train, from an app open in the 30 min before it leaves
/// until it decides, the watch reads the phone's location and GO's train positions, asks the alert server to hold the
/// question's buzz, and starts the ride by itself when `AutoRideRule` finds the phone left the station with the train. One
/// per app, owned by `AppDelegate` (it decides with the phone locked, where `RootView` does not run); the Testing demo has
/// its own, owned by `OnBoard`. It never asks for anything, keeps no place and no fix on device, and watches one train at a
/// time.
///
/// Real trains are off in this part (`isLive`): TT-243 turns them on.
@Observable @MainActor
final class AutoRideWatch {
    /// Real trains arm only once this is true (TT-243).
    static let isLive = false
    /// It arms from 30 min before L to 2 min after it.
    static let armLead: TimeInterval = 30 * 60
    static let armTail: TimeInterval = 2 * 60
    /// A ride shorter than this could never start (Y5's 5 min plus the 3 min deadline): its question is not held.
    static let shortestRide: TimeInterval = 8 * 60
    /// With no departure card on the phone, the hold goes from this long before L.
    static let holdLead: TimeInterval = 2 * 60
    /// The server lets the hold go by itself at `min(L + holdTail, endsAt − holdMargin)` (`server/src/activity.ts`).
    nonisolated static let holdTail: TimeInterval = 7 * 60
    nonisolated static let holdMargin: TimeInterval = 90
    /// A train still standing this long after L: the hold is let go, and the watch keeps watching.
    static let releaseAfter: TimeInterval = 6 * 60

    /// A train `RootView` passes in: Schedule's alerted train, or the departure card's.
    struct Candidate: Equatable, Sendable {
        let route: Route
        let trip: Trip
        /// L as last read, and the expected arrival at the rider's stop.
        let departure: Date
        let arrival: Date

        var ride: Ride { Ride(trip: trip.key, from: route.from.id, to: route.to.id) }

        init(route: Route, trip: Trip, departure: Date, arrival: Date) {
            self.route = route
            self.trip = trip
            self.departure = departure
            self.arrival = arrival
        }

        init(route: Route, departure: Departure) {
            self.init(
                route: route, trip: departure.trip, departure: departure.departureTime,
                arrival: departure.expectedArrival ?? departure.trip.scheduledArrival
            )
        }
    }

    /// The ride that started by itself, and when: ride mode opens once for it (`RootView`).
    struct Started: Equatable, Sendable {
        let ride: Ride
        let at: Date
    }

    /// A report the watch sent as it ended (not on board's `asked`, `handedOff` with no card, `holds: false`) that the
    /// server has not confirmed: sent again every tick until it has, or until the question ends (`until`). Kept on device,
    /// so a relaunch goes on sending it.
    struct Pending: Codable, Equatable, Sendable {
        var report: LiveActivityReport
        var until: Date
    }

    /// The train being watched, as kept on device (`autoRide.watch`): its identity, the latest L, when it left, when the
    /// watch armed and the reports sent. No plan (read again at restore) and no place.
    struct Saved: Codable, Equatable {
        struct Stop: Codable, Equatable {
            let id: String
            let name: String
        }

        var ride: Ride
        var from: Stop
        var to: Stop
        var lineId: String?
        var lineName: String?
        var scheduledDeparture: Date
        var scheduledArrival: Date
        /// L and the expected arrival, as last read.
        var departure: Date
        var arrival: Date
        var leftAt: Date?
        var armedAt: Date
        /// Armed at or after L: the covered form counts at any station.
        var armedLate: Bool
        var lastLook: Date?
        /// When the server confirmed `holds: true`.
        var holdReachedAt: Date?
        /// The outcome's report (`asked`, or `holds: false`) once one is due, and whether the server has it.
        var outcome: LiveActivityReport?
        var outcomeSent = false
        /// The first "can’t tell" at the deadline, and when; it keeps watching for a later start until the question ends.
        var unsure: AutoRideCheck.Reason?
        var unsureAt: Date?

        var route: Route {
            Route(
                from: Station(id: from.id, name: from.name), to: Station(id: to.id, name: to.name),
                line: lineId.map { Line(id: $0, name: lineName ?? "", colorHex: nil) }
            )
        }

        var trip: Trip {
            Trip(
                key: ride.tripKey, scheduledDeparture: scheduledDeparture, scheduledArrival: scheduledArrival,
                platform: .pending, tags: []
            )
        }

        /// When the question ends (`LiveDeparture.endsAt`), with L as last read.
        var endsAt: Date {
            min(departure.addingTimeInterval(LiveDeparture.askFor), max(arrival, departure))
        }

        /// When the server lets the hold go by itself.
        var holdEnds: Date {
            min(departure.addingTimeInterval(AutoRideWatch.holdTail), endsAt.addingTimeInterval(-AutoRideWatch.holdMargin))
        }

        /// The rule's deadline, or L + 6 min while the train has not left.
        var deadline: Date {
            let cap = departure.addingTimeInterval(AutoRideRule.decideCap)
            guard let leftAt else { return cap }
            return min(leftAt.addingTimeInterval(AutoRideRule.decideSpan), cap)
        }

        func report(holds: Bool? = nil, asked: Bool = false, handedOff: Bool = false) -> LiveActivityReport {
            LiveActivityReport(
                tripId: ride.tripId, serviceDate: String(ride.serviceDate), originId: ride.originId,
                destinationId: ride.destinationId, handedOff: handedOff, asked: asked, holds: holds
            )
        }
    }

    /// The ride that started by itself, until the next one.
    private(set) var started: Started?
    /// How the last watch ended (Settings › Testing › Last check); in memory only.
    private(set) var lastCheck: AutoRideCheck?
    /// The train being watched.
    private(set) var watched: Saved?

    /// The app's engine: plans, the default start and whether a ride runs. Nil for the demo, which starts through `OnBoard`.
    private let ride: RideEngine?
    private let location: any LocationProviding
    private let departures: any AutoRideDepartureReading
    private let positions: any TrainPositionProviding
    private let rivals: any RivalTrainsProviding
    private weak var holding: (any AutoRideHolding)?
    private let clock: any AppClock
    private let store: AutoRideStore
    private let live: Bool
    private let isDemo: Bool
    private let lookInterval: Duration?
    /// The start: the app's engine, or the demo's hand-off.
    private let startRide: @MainActor (Ride) async -> Bool
    /// The arriving nudge's `replan()` after a start, as `OnBoard.start` does.
    private let replan: @MainActor () -> Void
    private let isDeclined: @MainActor (TripKey) -> Bool
    /// Mock time is on, or Demo trains Ride or Departure plays: the engine's clock would not match real fixes.
    private let isTesting: @MainActor () -> Bool
    /// The app is in front: an unsure outcome asks silently, since Schedule asks with its strip.
    private let isActive: @MainActor () -> Bool
    /// A ride runs (the demo's, through `OnBoard`); nil reads the engine.
    private let rideRuns: (@MainActor () -> Bool)?
    private let reportsStationary: Bool

    @ObservationIgnored private var rule: AutoRideRule?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var follower: Task<Void, Never>?
    @ObservationIgnored private var isConsidering = false
    @ObservationIgnored private var isStarting = false
    @ObservationIgnored private var isLooking = false
    /// Reports from watches that ended, not confirmed yet, and the loop that sends them again.
    @ObservationIgnored private var pending: [Pending] = []
    @ObservationIgnored private var retries: Task<Void, Never>?
    @ObservationIgnored private var isRetrying = false
    /// Each watch gets a number, so a look that outlives its watch changes nothing.
    @ObservationIgnored private var generation = 0

    init(
        ride: RideEngine?,
        location: any LocationProviding,
        departures: any AutoRideDepartureReading,
        positions: any TrainPositionProviding,
        rivals: any RivalTrainsProviding = NoRivalTrains(),
        holding: (any AutoRideHolding)? = nil,
        clock: any AppClock,
        store: AutoRideStore,
        live: Bool = AutoRideWatch.isLive,
        demo: Bool = false,
        lookInterval: Duration? = .seconds(15),
        startRide: (@MainActor (Ride) async -> Bool)? = nil,
        replan: @escaping @MainActor () -> Void = {},
        isDeclined: @escaping @MainActor (TripKey) -> Bool = { _ in false },
        isTesting: @escaping @MainActor () -> Bool = { false },
        isActive: @escaping @MainActor () -> Bool = { true },
        rideRuns: (@MainActor () -> Bool)? = nil,
        reportsStationary: Bool? = nil
    ) {
        self.ride = ride
        self.location = location
        self.departures = departures
        self.positions = positions
        self.rivals = rivals
        self.holding = holding
        self.clock = clock
        self.store = store
        self.live = live
        isDemo = demo
        self.lookInterval = lookInterval
        self.startRide = startRide ?? { await ride?.start($0, source: .auto, asks: false) ?? false }
        self.replan = replan
        self.isDeclined = isDeclined
        self.isTesting = isTesting
        self.isActive = isActive
        self.rideRuns = rideRuns
        if let reportsStationary {
            self.reportsStationary = reportsStationary
        } else if #available(iOS 18, *) {
            self.reportsStationary = true
        } else {
            self.reportsStationary = false
        }
        pending = demo ? [] : store.pending
    }

    // MARK: Arming

    /// Real trains may arm and none is watched: `RootView` looks for candidates only then.
    var mayArm: Bool { live && watched == nil }

    /// `RootView`, every few seconds while the app is in front: the alerted trains on screen (Schedule's and the departure
    /// card's). It arms for the first that passes every gate; one blocked by a gate counts once as `not_armed`.
    func consider(_ candidates: [Candidate]) async {
        guard live, watched == nil, !isConsidering else { return }
        isConsidering = true
        defer { isConsidering = false }
        let now = clock.now
        for candidate in candidates {
            let ride = candidate.ride
            guard now >= candidate.departure.addingTimeInterval(-Self.armLead),
                  now <= candidate.departure.addingTimeInterval(Self.armTail),
                  !store.wasWatched(ride), !isDeclined(ride.tripKey), !isRiding else { continue }
            let blocked = candidate.arrival.timeIntervalSince(candidate.departure) < Self.shortestRide
                || !location.isAuthorized || !location.isPrecise || isTesting()
            let plan = blocked ? nil : await self.ride?.plan(for: ride)
            guard watched == nil, !isRiding else { return }
            guard let plan, plan.track != nil else {
                notArmed(ride)
                continue
            }
            arm(candidate, plan: plan, at: now)
            return
        }
    }

    /// The Testing demo (TT-242): its train, with no gate.
    func watchDemo(_ candidate: Candidate, plan: RidePlan) {
        guard watched == nil else { return }
        arm(candidate, plan: plan, at: clock.now)
    }

    private var isRiding: Bool {
        if let rideRuns { return rideRuns() }
        guard let state = ride?.state else { return false }
        return state.phase != .ended
    }

    private func notArmed(_ ride: Ride) {
        guard store.check(ride, outcome: .notArmed) else { return }
        let check = AutoRideCheck(outcome: .notArmed)
        lastCheck = check
        Analytics.track(.autoRideChecked(check, demo: isDemo))
    }

    private func arm(_ candidate: Candidate, plan: RidePlan, at now: Date) {
        let saved = Saved(
            ride: candidate.ride,
            from: .init(id: candidate.route.from.id, name: candidate.route.from.name),
            to: .init(id: candidate.route.to.id, name: candidate.route.to.name),
            lineId: candidate.route.line?.id, lineName: candidate.route.line?.name,
            scheduledDeparture: candidate.trip.scheduledDeparture, scheduledArrival: candidate.trip.scheduledArrival,
            departure: candidate.departure, arrival: candidate.arrival, armedAt: now,
            armedLate: now >= candidate.departure
        )
        begin(saved, plan: plan)
    }

    private func begin(_ saved: Saved, plan: RidePlan) {
        guard let rule = AutoRideRule(
            plan: plan, originId: saved.ride.originId, armedLate: saved.armedLate, reportsStationary: reportsStationary
        ) else { return }
        generation += 1
        self.rule = rule
        watched = saved
        save()
        if !isDemo { holding?.heldRide = saved.ride }
        location.startUpdates { [weak self] fix in self?.receive(fix) }
        startLoop()
        Task { await self.look() }
    }

    // MARK: Following

    /// At launch (`AppDelegate`): a ride the rider starts, or one that starts while the watch waits, ends it as answered.
    func follow(_ engine: RideEngine) {
        follower?.cancel()
        let events = engine.events()
        follower = Task { [weak self] in
            for await event in events {
                guard case .update(let state) = event, state.phase != .ended else { continue }
                self?.someRideRuns()
            }
        }
    }

    private func someRideRuns() {
        guard watched != nil, !isStarting else { return }
        finish(.answered)
    }

    /// The alert rules changed (`RootView`): an alert switched off or removed stops the watch.
    func alertsChanged(_ alerts: any WatchedTripsProviding) {
        guard let watched, !isDemo, !alerts.isAlerted(watched.trip, on: watched.route) else { return }
        // The rule's DELETE or pause lets the server's hold go, and the card's `removed` goes with it.
        finish(.stopped, report: false)
    }

    /// The demo was turned off, or the app's watch must stop for a reason of its own.
    func stop() {
        guard watched != nil else { return }
        finish(.stopped)
    }

    /// The question ended with no look past its end: the demo's clock went back to 5:01 PM for its next play.
    func questionEnded() {
        guard let watched else { return }
        finish(.unsure, reason: watched.unsure)
    }

    // MARK: Relaunch

    /// At launch, after the ride's restore: the watch picks up its train. A ride saved meanwhile means it started (or the
    /// rider started one): answered. Past its deadline it lets the hold go and ends as unsure.
    func restore() async {
        // Reports a watch could not get to the server before the app stopped go on.
        if !pending.isEmpty {
            startRetries()
            Task { await self.retryPending() }
        }
        guard watched == nil, let saved = store.saved, let ride else { return }
        if ride.holdsRide {
            watched = saved
            finish(.answered)
            return
        }
        let now = clock.now
        guard now < saved.deadline, let plan = await ride.plan(for: saved.ride), plan.track != nil else {
            watched = saved
            send(saved.report(holds: false), until: saved.endsAt)
            finish(.unsure, reason: saved.unsure, report: false)
            return
        }
        begin(saved, plan: plan)
    }

    // MARK: Fixes and looks

    private func receive(_ fix: LocationFix) {
        guard watched != nil, rule != nil else { return }
        rule?.observe(fix, at: clock.now)
        decide()
    }

    private func startLoop() {
        loop?.cancel()
        guard let lookInterval else { return }
        let generation = generation
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: lookInterval)
                guard !Task.isCancelled, let self, self.generation == generation else { return }
                await self.look()
            }
        }
    }

    /// One look: the train's live status (L, whether it left), GO's positions of it and its rivals, the hold's reports, and
    /// the verdict. Tests call it in place of the loop.
    func look() async {
        guard var saved = watched, !isLooking else { return }
        isLooking = true
        defer { isLooking = false }
        let generation = generation
        // Stopped: a gate that went while it watched.
        if isTesting() || (!isDemo && (!location.isAuthorized || !location.isPrecise)) {
            finish(.stopped)
            return
        }
        if isDeclined(saved.ride.tripKey) || (isRiding && !isStarting) {
            finish(.answered)
            return
        }
        let departure = await departures.departure(of: saved.trip, ride: saved.ride, at: clock.now)
        let position = await positions.position(of: saved.ride.tripKey)
        let rivalTrains = await rivals.rivals(of: saved.ride, around: saved.departure)
        var rivalPositions: [(String, TrainPosition)] = []
        for rival in rivalTrains {
            if let position = await positions.position(of: rival.trip) { rivalPositions.append((rival.trip.tripId, position)) }
        }
        guard self.generation == generation, watched != nil else { return }
        let now = clock.now
        saved = watched ?? saved
        if let departure {
            saved.departure = departure.departureTime
            saved.arrival = departure.expectedArrival ?? departure.trip.scheduledArrival
        }
        // When it left: the first look that reads it departed (`BoardingRule`).
        if saved.leftAt == nil {
            let phase = departure.map { BoardingRule.phase(of: $0, now: now) }
                ?? (now >= saved.departure ? .departed(.clock) : .waiting)
            if phase.isDeparted {
                let sighted = departure.map { BoardingRule.hasSighting(of: $0, now: now) } ?? false
                saved.leftAt = AutoRideRule.leftAt(look: now, previous: saved.lastLook, departure: saved.departure, sighted: sighted)
            }
        }
        saved.lastLook = now
        watched = saved
        save()
        if let position { rule?.observe(position, readAt: now) }
        rule?.setRivals(rivalTrains)
        for (trip, position) in rivalPositions { rule?.observe(position, rival: trip, readAt: now) }
        await reportHold(at: now)
        guard self.generation == generation, watched != nil else { return }
        decide()
        guard self.generation == generation, let current = watched else { return }
        if clock.now >= current.endsAt {
            finish(.unsure, reason: current.unsure)
        }
    }

    // MARK: The verdict

    private func decide() {
        guard let saved = watched, let rule, !isStarting else { return }
        let now = clock.now
        let moment = AutoRideRule.Moment(
            now: now, departure: saved.departure, leftAt: saved.leftAt, arrival: saved.arrival,
            answered: isDeclined(saved.ride.tripKey)
        )
        switch rule.verdict(at: moment) {
        case .starts:
            Task { await self.start() }
        case .notOnBoard:
            // The silent question until it ends.
            queueOutcome(saved.report(asked: true))
            finish(.notOnBoard)
        case .unsure(let reason):
            guard saved.unsure == nil else { return }
            var changed = saved
            changed.unsure = reason
            changed.unsureAt = now
            // Last check shows it at once; the watch goes on for a later start until the question ends.
            lastCheck = AutoRideCheck(
                outcome: .unsure, reason: reason, secondsAfter: saved.leftAt.map { max(0, Int(now.timeIntervalSince($0))) },
                holdReachedAt: saved.holdReachedAt
            )
            // In front, Schedule asks with its strip and the card asks silently; in the background the server buzzes.
            changed.outcome = isActive() ? saved.report(asked: true) : saved.report(holds: false)
            changed.outcomeSent = false
            watched = changed
            save()
            Task { await self.reportHold(at: self.clock.now) }
        case .waiting:
            break
        }
    }

    private func start() async {
        guard let saved = watched, !isStarting else { return }
        guard !isRiding else {
            finish(.answered)
            return
        }
        isStarting = true
        let generation = generation
        let started = await startRide(saved.ride)
        isStarting = false
        guard self.generation == generation, watched != nil else { return }
        guard started else {
            // The rider's Yes was starting a ride meanwhile.
            if isRiding { finish(.answered) }
            return
        }
        let now = clock.now
        self.started = Started(ride: saved.ride, at: now)
        let seconds = saved.leftAt.map { max(0, Int(now.timeIntervalSince($0))) } ?? 0
        Analytics.track(.rideStarted(source: .auto, demo: isDemo, secondsAfter: seconds))
        replan()
        // With no departure card on the phone, nothing hands it off: the server hears it from here, so it sends no question.
        if !isDemo, holding?.departureRide != saved.ride {
            send(saved.report(handedOff: true), until: saved.endsAt)
        }
        finish(.started)
    }

    // MARK: The hold (section 5)

    /// The outcome's report, which `finish` sends as the watch ends.
    private func queueOutcome(_ report: LiveActivityReport) {
        guard var saved = watched else { return }
        saved.outcome = report
        saved.outcomeSent = false
        watched = saved
        save()
    }

    /// The hold's reports from the watch's own loop: `holds: true` at once with the train's card on the phone, else from
    /// L − 2 min; L + 6 min with the train still standing lets it go; an outcome's report replaces it. Each is sent again on
    /// the next look until the server has it, or the server's own end of the hold has passed.
    private func reportHold(at now: Date) async {
        guard !isDemo, let holding, var saved = watched else { return }
        let generation = generation
        if saved.outcome == nil, saved.leftAt == nil, now >= saved.departure.addingTimeInterval(Self.releaseAfter),
           saved.holdReachedAt != nil {
            saved.outcome = saved.report(holds: false)
            saved.outcomeSent = false
            watched = saved
            save()
        }
        if let outcome = saved.outcome {
            guard !saved.outcomeSent, now < saved.endsAt else { return }
            let sent = await holding.reportHold(outcome)
            guard self.generation == generation, var current = watched, sent else { return }
            current.outcomeSent = true
            watched = current
            save()
            return
        }
        guard saved.holdReachedAt == nil, now < saved.holdEnds else { return }
        let hasCard = holding.departureRide == saved.ride
        guard hasCard || now >= saved.departure.addingTimeInterval(-Self.holdLead) else { return }
        let sent = await holding.reportHold(saved.report(holds: true))
        guard self.generation == generation, var current = watched, sent else { return }
        current.holdReachedAt = clock.now
        watched = current
        save()
    }

    /// A report the watch sends as it ends: sent now, and again every tick until the server has it or `until` has passed.
    /// The latest word on a train replaces an older one still waiting.
    private func send(_ report: LiveActivityReport, until: Date) {
        guard !isDemo, holding != nil, clock.now < until else { return }
        pending.removeAll {
            $0.report.tripId == report.tripId && $0.report.serviceDate == report.serviceDate
                && $0.report.originId == report.originId
        }
        pending.append(Pending(report: report, until: until))
        store.pending = pending
        startRetries()
        Task { await self.retryPending() }
    }

    /// Sends each waiting report once; one the server has, or whose time has passed, is dropped. Tests call it in place of
    /// the loop.
    func retryPending() async {
        guard !isRetrying, let holding else { return }
        isRetrying = true
        defer { isRetrying = false }
        var tried: Set<LiveActivityReport> = []
        while let next = pending.first(where: { !tried.contains($0.report) }) {
            tried.insert(next.report)
            let done = clock.now >= next.until ? true : await holding.reportHold(next.report)
            if done {
                pending.removeAll { $0 == next }
                store.pending = pending
            }
        }
        stopUpdatesIfIdle()
    }

    private func startRetries() {
        guard retries == nil, let lookInterval else { return }
        retries = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: lookInterval)
                guard let watch = self, !watch.pending.isEmpty else { break }
                await watch.retryPending()
            }
            self?.retries = nil
        }
    }

    /// With no train watched and nothing left to tell the server, the location stops: after a start the ride has the
    /// updates (the shared provider), while the demo's phone is the watch's own.
    private func stopUpdatesIfIdle() {
        guard watched == nil, pending.isEmpty else { return }
        if isDemo || !isRiding { location.stopUpdates() }
    }

    // MARK: The end

    private func finish(_ outcome: AutoRideCheck.Outcome, reason: AutoRideCheck.Reason? = nil, report: Bool = true) {
        guard let saved = watched else { return }
        // An unsure outcome counts from when it could not tell, not from when the question ended.
        let now = outcome == .unsure ? (saved.unsureAt ?? clock.now) : clock.now
        let seconds = saved.leftAt.map { max(0, Int(now.timeIntervalSince($0))) }
        let check = AutoRideCheck(
            outcome: outcome, reason: outcome == .unsure ? reason : nil, secondsAfter: seconds,
            holdReachedAt: saved.holdReachedAt
        )
        lastCheck = check
        if store.check(saved.ride, outcome: outcome) || isDemo {
            Analytics.track(.autoRideChecked(check, demo: isDemo))
        }
        // An outcome's report not yet confirmed goes on being sent; stopped with the hold on lets it go. A start says the
        // last word (the hand-off), so an earlier "can’t tell" is not sent after it.
        if report {
            if outcome != .started, let unsent = saved.outcome, !saved.outcomeSent {
                send(unsent, until: saved.endsAt)
            } else if outcome == .stopped, saved.outcome == nil, saved.holdReachedAt != nil {
                send(saved.report(holds: false), until: saved.endsAt)
            }
        }
        generation += 1
        loop?.cancel()
        loop = nil
        rule = nil
        watched = nil
        store.saved = nil
        if !isDemo, holding?.heldRide == saved.ride { holding?.heldRide = nil }
        // The location keeps going while a report still waits for the server, so the app is not suspended before it goes.
        stopUpdatesIfIdle()
    }

    private func save() {
        guard !isDemo else { return }
        store.saved = watched
    }
}

/// The watch as kept on device (TT-242, D120): the train being watched (`autoRide.watch`) and today's checked trains
/// (`autoRide.checked`, so `auto_ride_checked` goes once per train and day, and a finished train is not watched again).
/// No place and no fix. `defaults` nil keeps nothing (the demo, tests that need nothing kept).
@MainActor
final class AutoRideStore {
    static let watchKey = "autoRide.watch"
    static let checkedKey = "autoRide.checked"
    static let pendingKey = "autoRide.pending"

    private let defaults: UserDefaults?

    init(defaults: UserDefaults?) {
        self.defaults = defaults
    }

    var saved: AutoRideWatch.Saved? {
        get { defaults?.data(forKey: Self.watchKey).flatMap { try? JSONDecoder().decode(AutoRideWatch.Saved.self, from: $0) } }
        set {
            guard let defaults else { return }
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Self.watchKey)
            } else {
                defaults.removeObject(forKey: Self.watchKey)
            }
        }
    }

    /// The reports that ended watches still owe the server (`AutoRideWatch.Pending`).
    var pending: [AutoRideWatch.Pending] {
        get { defaults?.data(forKey: Self.pendingKey).flatMap { try? JSONDecoder().decode([AutoRideWatch.Pending].self, from: $0) } ?? [] }
        set {
            guard let defaults else { return }
            if !newValue.isEmpty, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Self.pendingKey)
            } else {
                defaults.removeObject(forKey: Self.pendingKey)
            }
        }
    }

    /// A watch on this train finished today (not a `not_armed`).
    func wasWatched(_ ride: Ride) -> Bool {
        guard let outcome = checked[Self.key(ride)] else { return false }
        return outcome != AutoRideCheck.Outcome.notArmed.rawValue
    }

    /// Records the train's outcome; true when it is the first for that train today, when its event goes. A watch that
    /// arms after a `not_armed` is recorded too, so it is not watched again, and sends no second event.
    @discardableResult
    func check(_ ride: Ride, outcome: AutoRideCheck.Outcome) -> Bool {
        var all = checked
        let key = Self.key(ride)
        let isFirst = all[key] == nil
        // Only today's trains are kept.
        all = all.filter { $0.key.hasPrefix("\(ride.serviceDate)|") }
        all[key] = outcome.rawValue
        defaults?.set(all, forKey: Self.checkedKey)
        return isFirst
    }

    private var checked: [String: String] {
        (defaults?.dictionary(forKey: Self.checkedKey) as? [String: String]) ?? [:]
    }

    private static func key(_ ride: Ride) -> String {
        "\(ride.serviceDate)|\(ride.tripId)|\(ride.originId)"
    }
}
