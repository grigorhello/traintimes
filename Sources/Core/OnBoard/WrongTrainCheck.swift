import Foundation
import Observation

// The wrong train check (TT-251, D127): what finds a wrong train for real trains and raises TT-250's warning. Terms as in
// `WrongTrainRule`: T the rider's train, O their station, D their stop, L T's expected departure from O, X another train.

/// What the check calls on the warning's presenter (`WrongTrain`); a recording fake in tests.
@MainActor
protocol WrongTrainRaising: AnyObject {
    var warning: WrongTrainWarning? { get }
    @discardableResult
    func raise(_ warning: WrongTrainWarning, now: Date, rate: Double) -> Task<Void, Never>?
    func withdraw()
}

extension WrongTrain: WrongTrainRaising {}

/// The automatic ride's watch's side of the check (`AutoRideWatch(wrongTrain:)`, TT-251, D127).
@MainActor
protocol WrongTrainChecking: AnyObject {
    /// The watch armed on `ride` and reads `reader`: the check opens on it (source `alert`).
    func watchArmed(_ ride: Ride, plan: RidePlan, departure: Date, reader: any LocationProviding)
    /// The watch on `ride` finished with `outcome`, before it lets go of the location: the check takes the location over
    /// while it stays open with no ride, and closes on a start (the watch proved T) or a stop (a gate went).
    func watchEnded(_ ride: Ride, outcome: AutoRideCheck.Outcome)
    /// The phone's first moving fix with the candidate the check follows on `ride`, nil when it follows none.
    func followingSince(_ ride: Ride) -> Date?
    /// The check raised a warning for `ride`: the watch finishes `wrong_train`.
    func hasWarned(_ ride: Ride) -> Bool
    /// The check is open: the watch leaves the location running when it finishes.
    var keepsLocation: Bool { get }
}

/// How the last check ended (Settings › Testing › Last wrong train check, `wrong_train_checked`). In memory only; never a
/// place.
struct WrongTrainCheckResult: Equatable, Sendable {
    enum Outcome: String, Sendable {
        /// The warning was raised.
        case warned
        /// The phone moved with the rider's train.
        case withTrain = "with_train"
        /// It moved, and no other train was proven.
        case noMatch = "no_match"
        /// It never left the station in a train.
        case stayed
    }

    /// Why a check that warned of nothing closed.
    enum Why: String, Sendable {
        /// A fix 300 m or more from O off every track, or not at train speed.
        case walkedAway = "walked_away"
        /// L + 30 min at the station, 3 min of movement with nothing proven (6 while it followed a train), or the phone
        /// never near O once T had left.
        case limit
        /// The ride ended.
        case rideEnded = "ride_ended"
        /// T reached D.
        case arrived
    }

    var outcome: Outcome
    var source: WrongTrainSource
    /// Whole seconds from the phone's first moving fix to the verdict, on `warned` and `withTrain`.
    var seconds: Int?
    /// On `warned`.
    var reason: WrongTrainReason?
    /// On `noMatch` and `stayed`.
    var why: Why?
}

extension WrongTrainStore {
    static let checkedKey = "wrongTrain.checked"

    /// Records that `ride`'s check closed today; true the first time, so `wrong_train_checked` goes once per train and day.
    /// Earlier days are dropped. Trip id and service date only.
    func firstCheck(_ ride: Ride) -> Bool {
        guard let defaults else { return true }
        let entry = "\(ride.serviceDate)/\(ride.tripId)"
        let kept = (defaults.stringArray(forKey: Self.checkedKey) ?? []).filter { stored in
            stored.split(separator: "/", maxSplits: 1).first.flatMap { Int($0) }.map { $0 >= ride.serviceDate } ?? false
        }
        guard !kept.contains(entry) else { return false }
        defaults.set((kept + [entry]).sorted(), forKey: Self.checkedKey)
        return true
    }

    /// `ride`'s check closed today.
    func wasChecked(_ ride: Ride) -> Bool {
        (defaults?.stringArray(forKey: Self.checkedKey) ?? []).contains("\(ride.serviceDate)/\(ride.tripId)")
    }
}

/// The wrong train check (TT-251, D127): one per app as `AppDelegate.wrongTrainCheck`, none in fixture runs, previews and
/// the unit test host. It owns one `WrongTrainRule` for one train at a time, feeds it the phone's fixes, the trains leaving
/// O, GO's timed positions and the stops each train still has ahead, and raises or withdraws TT-250's warning. Its lifetime
/// is its own, not the watch's.
///
/// - **It opens** when the automatic ride's watch arms (`alert`), when a ride starts by a tap (`on_board`, `departure`;
///   never one that started by itself, whose start proved T), or from `consider()` for an alerted train from L − 30 to
///   L + 30 min the watch did not arm for.
/// - **Gates:** location allowed with Precise Location (it never asks), T with a track and not cancelled, no "I’m fine"
///   today, no Mock time or demo; for an alert with no ride, Automatic ride not turned off and T not declined when it opens.
///   A gate that fails closes it silently.
/// - **Fixes** come through the watch's and the engine's `fixTap` while they run; with neither it runs the shared updates
///   itself (`startUpdates` swaps the callback and keeps the session) and stops them when it closes. Five minutes of fixes
///   in memory, nothing with a place saved.
/// - **Looks** every 15 s; the train feed's 15 s copy from the phone's first moving fix until the verdict.
/// - **Closes** on `withTrain` (withdrawing a warning that was up), on walking away from O, at L + 30 min at the station,
///   after 3 min of movement with nothing proven (6 while it follows a train), when T reaches D, when its ride ends, when
///   a warning it raised ends, or when a gate fails.
@Observable @MainActor
final class WrongTrainCheck: WrongTrainChecking {
    // MARK: Numbers

    /// An alerted train is checked from L − 30 min to L + 30 min.
    static let openLead: TimeInterval = 30 * 60
    static let stationTail: TimeInterval = 30 * 60
    /// Once T is due to have left (L + 2 min), the check stays only while the last good fix is this close to O.
    static let leftAfter: TimeInterval = 2 * 60
    static let stationRadius = AutoRideRule.stationRadius
    /// The movement window from the first moving fix, and while the rule follows a train.
    static let movingSpan: TimeInterval = 3 * 60
    static let followingSpan: TimeInterval = 6 * 60
    /// The watch waits this long from the followed train's first moving fix before "On board?".
    static let watchWaits: TimeInterval = 3 * 60
    /// No good fix this long after T left: the updates are started again, at most this often.
    static let pausedAfter: TimeInterval = 30
    /// `consider()` reads today's alerted trains at most this often.
    static let considerEvery: TimeInterval = 30
    /// A warning ends 2 min after X's next stop, or 10 min after it was raised with no time.
    static let expiresAfterStop: TimeInterval = 2 * 60
    static let expiresWithoutTime: TimeInterval = 10 * 60

    // MARK: State

    /// How the last check ended; in memory only.
    private(set) var lastCheck: WrongTrainCheckResult?

    private struct Open {
        let ride: Ride
        var source: WrongTrainSource
        let plan: RidePlan
        /// L, as last read.
        var departure: Date
        var rule: WrongTrainRule
        /// The location fixes come through: the watch's, the shared one for a ride, or the check's own in the tail.
        var reader: any LocationProviding
        /// The check started the updates itself and stops them when it closes.
        var ownsUpdates: Bool
        /// T's and the candidates' trip ids: the positions read.
        let trips: Set<String>
        var firstMove: Date?
        var following: Date?
        var warned: WrongTrainWarning?
        var lastGoodFix: Date?
        /// The last good fix's distance from O, so the first moving fix is one moving away from O.
        var lastFromOrigin: Double?
        var lastRestart: Date?
        let openedAt: Date
    }

    @ObservationIgnored private var open: Open?
    @ObservationIgnored private var opening = false
    @ObservationIgnored private var watchIsArmed = false
    @ObservationIgnored private var followedRide: Ride?
    @ObservationIgnored private var lastConsider: Date?
    /// Rides closed in this run without an event (a gate): `consider()` does not open them again.
    @ObservationIgnored private var closedSilently: Set<Ride> = []
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var follower: Task<Void, Never>?
    @ObservationIgnored private var isLooking = false
    /// Each check gets a number, so a look that outlives its check changes nothing.
    @ObservationIgnored private var generation = 0
    /// The automatic ride's watch still owes the server a report (D120 keeps location for it): a closing check leaves
    /// the updates running and the watch stops them once the report went. Set by `AppDelegate`.
    @ObservationIgnored var locationHeld: (@MainActor () -> Bool)?

    private let presenter: any WrongTrainRaising
    private let location: any LocationProviding
    private let timetable: any WrongTrainTimetable
    private let liveStops: any LiveStopsProviding
    private let positions: any TrainPositionHistoryProviding
    private let clock: any AppClock
    private let store: WrongTrainStore
    private let lookInterval: Duration?
    /// Today's alerted trains with their plans (`AutoRideWake.alertedTrains`).
    private let alertedTrains: @MainActor (Date) async -> [AutoRideTrain]
    /// A ride runs on the app's engine.
    private let rideRuns: @MainActor () -> Bool
    private let isDeclined: @MainActor (TripKey) -> Bool
    private let autoRideOff: @MainActor () -> Bool
    /// Mock time is on, or a demo plays.
    private let isTesting: @MainActor () -> Bool
    private let reportsStationary: Bool

    init(
        presenter: any WrongTrainRaising,
        location: any LocationProviding,
        timetable: any WrongTrainTimetable,
        liveStops: any LiveStopsProviding,
        positions: any TrainPositionHistoryProviding,
        clock: any AppClock,
        store: WrongTrainStore,
        lookInterval: Duration? = .seconds(15),
        alertedTrains: @escaping @MainActor (Date) async -> [AutoRideTrain] = { _ in [] },
        rideRuns: @escaping @MainActor () -> Bool = { false },
        isDeclined: @escaping @MainActor (TripKey) -> Bool = { _ in false },
        autoRideOff: @escaping @MainActor () -> Bool = { false },
        isTesting: @escaping @MainActor () -> Bool = { false },
        reportsStationary: Bool? = nil
    ) {
        self.presenter = presenter
        self.location = location
        self.timetable = timetable
        self.liveStops = liveStops
        self.positions = positions
        self.clock = clock
        self.store = store
        self.lookInterval = lookInterval
        self.alertedTrains = alertedTrains
        self.rideRuns = rideRuns
        self.isDeclined = isDeclined
        self.autoRideOff = autoRideOff
        self.isTesting = isTesting
        if let reportsStationary {
            self.reportsStationary = reportsStationary
        } else if #available(iOS 18, *) {
            self.reportsStationary = true
        } else {
            self.reportsStationary = false
        }
    }

    /// The train being checked; nil while none.
    var checked: Ride? { open?.ride }
    /// How the open check is tied to T; nil while none.
    var source: WrongTrainSource? { open?.source }

    // MARK: Opening

    /// `RootView`, every few seconds while the app is in front, beside the watch's `consider`: an alerted train from L − 30
    /// to L + 30 min the watch did not arm for (a ride under 8 min, or T has left and the rider may still be at O). Reads
    /// today's alerted trains at most every 30 s.
    func consider() async {
        guard open == nil, !opening else { return }
        let now = clock.now
        if let lastConsider, now.timeIntervalSince(lastConsider) < Self.considerEvery { return }
        lastConsider = now
        guard !isTesting(), location.isAuthorized, location.isPrecise, !autoRideOff(), !rideRuns() else { return }
        for train in await alertedTrains(now) {
            let candidate = train.candidate
            let ride = candidate.ride
            guard now >= candidate.departure.addingTimeInterval(-Self.openLead),
                  now <= candidate.departure.addingTimeInterval(Self.stationTail),
                  !closedSilently.contains(ride), !store.wasChecked(ride), !isDeclined(ride.tripKey) else { continue }
            guard open == nil, !opening, !rideRuns() else { return }
            await begin(ride, source: .alert, plan: train.plan, departure: candidate.departure, reader: nil)
            return
        }
    }

    func watchArmed(_ ride: Ride, plan: RidePlan, departure: Date, reader: any LocationProviding) {
        watchIsArmed = true
        if var current = open, current.ride == ride {
            release(current, for: reader)
            current.reader = reader
            current.ownsUpdates = false
            open = current
            return
        }
        if open != nil { close(nil) }
        guard !isDeclined(ride.tripKey) else { return }
        Task { await self.begin(ride, source: .alert, plan: plan, departure: departure, reader: reader) }
    }

    func watchEnded(_ ride: Ride, outcome: AutoRideCheck.Outcome) {
        watchIsArmed = false
        guard let current = open, current.ride == ride else { return }
        switch outcome {
        case .started:
            // The ride started by itself: the phone moved with T's own positions.
            close(.withTrain)
        case .stopped, .notArmed:
            close(nil)
        case .notOnBoard, .unsure, .answered, .wrongTrain:
            // A No, "not on board" or "can’t tell" leaves the check open (the missed train); a ride started meanwhile
            // has the updates.
            guard !rideRuns() else { return }
            takeUpdates()
        }
    }

    /// `AppDelegate`, at launch: a ride the rider starts by a tap opens the check on it (or ties the open alert check to it),
    /// its arrival and its end close it, and a ride that started by itself closes the check on its train.
    func follow(_ engine: RideEngine) {
        follower?.cancel()
        let events = engine.events()
        follower = Task { [weak self, weak engine] in
            for await event in events {
                guard let self, let engine else { return }
                switch event {
                case .update(let state):
                    if let ride = engine.ride, state.phase != .ended {
                        self.rideUpdated(ride, source: engine.startSource, plan: engine.plan, phase: state.phase)
                    } else if let ride = engine.ride {
                        self.rideEnded(ride)
                    }
                case .phase(.ended):
                    if let ride = engine.ride { self.rideEnded(ride) }
                case .phase:
                    break
                }
            }
        }
    }

    /// A ride runs on `ride` (each engine update): the first update of a ride started by a tap opens the check on it.
    func rideUpdated(_ ride: Ride, source: RideStartSource?, plan: RidePlan?, phase: RidePhase) {
        if followedRide != ride {
            followedRide = ride
            rideStarted(ride, source: source, plan: plan)
        }
        if phase == .atYourStop, open?.ride == ride { close(outcomeNow(), why: .arrived) }
    }

    private func rideStarted(_ ride: Ride, source: RideStartSource?, plan: RidePlan?) {
        let tapped: WrongTrainSource? = switch source {
        case .onBoard: .onBoard
        case .departure: .departure
        default: nil
        }
        if var current = open {
            // The ride has the updates now. A tapped ride runs on the shared reader, so one the check ran itself (the
            // closed tier's) stops; an automatic start may keep the closed tier's, which is left alone.
            if tapped != nil { release(current, for: location) }
            current.ownsUpdates = false
            open = current
        }
        guard let tapped else {
            // A ride that started by itself proved T; any other ride ends a check on another train.
            if let current = open { close(current.ride == ride && source == .auto ? .withTrain : nil) }
            return
        }
        let now = clock.now
        if var current = open, current.ride == ride {
            current.source = tapped
            current.reader = location
            current.rule.tie = now < current.departure ? .rideAtOrigin : .rideAfterLeft
            open = current
            return
        }
        if open != nil { close(nil) }
        guard let plan, let first = plan.stops.first else { return }
        Task { await self.begin(ride, source: tapped, plan: plan, departure: first.departure, reader: location) }
    }

    /// The ride on `ride` ended: a check tied to it closes.
    func rideEnded(_ ride: Ride) {
        if followedRide == ride { followedRide = nil }
        guard let current = open, current.ride == ride, current.source != .alert else { return }
        close(outcomeNow(), why: .rideEnded)
    }

    private func begin(
        _ ride: Ride, source: WrongTrainSource, plan: RidePlan, departure: Date, reader: (any LocationProviding)?
    ) async {
        guard open == nil, !opening, plan.track != nil, passesGates(ride, source: source, reader: reader ?? location) else { return }
        opening = true
        defer { opening = false }
        let day = ride.tripKey.serviceDay
        var stations: [Station] = []
        if let line = await timetable.trip(ride.tripKey)?.lineId { stations = await timetable.stations(onLine: line) }
        let candidates = await timetable.candidates(leaving: ride.originId, on: day)
        guard open == nil, passesGates(ride, source: source, reader: reader ?? location) else { return }
        let now = clock.now
        let tie: WrongTrainRule.Tie = source == .alert ? .alert : (now < departure ? .rideAtOrigin : .rideAfterLeft)
        guard var rule = WrongTrainRule(
            plan: plan, ride: ride, tie: tie, lineStations: stations, reportsStationary: reportsStationary
        ) else { return }
        rule.setCandidates(candidates)
        generation += 1
        let owns = reader == nil && !rideRuns() && !watchIsArmed
        open = Open(
            ride: ride, source: source, plan: plan, departure: departure, rule: rule, reader: reader ?? location,
            ownsUpdates: false, trips: Set(candidates.map(\.trip.tripId) + [ride.tripId]), openedAt: now
        )
        if owns { takeUpdates() }
        startLoop()
        Task { await self.look() }
    }

    /// The check runs the updates itself: with updates running this only swaps the callback, so the session goes on.
    private func takeUpdates() {
        guard var current = open else { return }
        current.ownsUpdates = true
        open = current
        current.reader.startUpdates { [weak self] fix in self?.receive(fix) }
    }

    /// Updates the check started on another reader than the one taking over stop: nothing else would.
    private func release(_ current: Open, for reader: any LocationProviding) {
        guard current.ownsUpdates, (current.reader as AnyObject) !== (reader as AnyObject) else { return }
        current.reader.stopUpdates()
    }

    private func passesGates(_ ride: Ride, source: WrongTrainSource, reader: any LocationProviding) -> Bool {
        guard reader.isAuthorized, reader.isPrecise, !store.isFine(ride), !isTesting() else { return false }
        if source == .alert, !rideRuns() {
            return !autoRideOff()
        }
        return true
    }

    // MARK: Fixes

    /// A fix from the phone, through the watch's or the engine's `fixTap`, or the check's own updates.
    func receive(_ fix: LocationFix) {
        guard var current = open else { return }
        current.rule.observe(fix, at: clock.now)
        guard let last = current.rule.lastFix(), last.at != current.lastGoodFix else {
            open = current
            return
        }
        current.lastGoodFix = last.at
        let leaving = last.fromOrigin >= Self.stationRadius
        let away = current.lastFromOrigin.map { last.fromOrigin > $0 } ?? false
        current.lastFromOrigin = last.fromOrigin
        if current.firstMove == nil, leaving, away, last.onTrack, let speed = last.speed, speed >= AutoRideRule.leaveSpeed,
           hasLeftOrigin(current, at: last.at) {
            current.firstMove = last.at
        }
        open = current
        // Walking away: seen at O, then 300 m or more from it off every track, or on one but not at train speed.
        if current.firstMove == nil, current.warned == nil, last.wasAtStation, leaving {
            let notATrain = !last.onTrack || (last.speed.map { $0 < AutoRideRule.leaveSpeed } ?? false)
            if notATrain { close(.stayed, why: .walkedAway) }
        }
    }

    /// The first moving fix counts only once the phone has left O by train: from L − 15 min, after it was seen at O
    /// (as Y1), and at a covered station (where the roof hides the platform) or on a ride started after T left (where
    /// the tap stands in) by the time alone. A train running into O or a car on the way to it never starts the movement
    /// limits.
    private func hasLeftOrigin(_ check: Open, at moment: Date) -> Bool {
        let from = check.departure.addingTimeInterval(-AutoRideRule.stationLead)
        guard moment >= from else { return false }
        if check.rule.tie == .rideAfterLeft || AutoRideRule.coveredStations.contains(check.ride.originId) { return true }
        guard let seen = check.rule.seenAtStation(now: clock.now) else { return false }
        return seen >= from
    }

    // MARK: Looks

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

    /// One look: T's stops ahead (L, cancelled), GO's positions, the stops ahead of the trains near the phone, the verdict,
    /// the limits and the restart on paused fixes. Tests call it in place of the loop.
    func look() async {
        guard let started = open, !isLooking else { return }
        isLooking = true
        defer { isLooking = false }
        let generation = generation
        let ride = started.ride
        // A warning it raised ended (an answer, its expiry): the check is done. Before the gates, since "I’m fine" is one.
        if started.warned != nil, presenter.warning?.ride != ride {
            close(.warned)
            return
        }
        guard passesGates(ride, source: started.source, reader: started.reader) else {
            close(nil)
            return
        }
        let fast = started.warned == nil && started.firstMove.map {
            clock.now < $0.addingTimeInterval(Self.followingSpan)
        } ?? false
        let ownStops = await liveStops.stopsAhead(of: ride.tripKey)
        let history = await positions.positions(on: ride.tripKey.serviceDay, fast: fast)
        guard self.generation == generation, var current = open else { return }
        current.rule.setStops(ownStops, of: ride.tripId)
        if let ownStops, ownStops.isFresh {
            if ownStops.isCancelled {
                open = current
                close(nil)
                return
            }
            if let atOrigin = ownStops.stops.first(where: { $0.id == ride.originId }), let time = atOrigin.time {
                current.departure = time
            }
        }
        let now = clock.now
        for (tripId, list) in history.timed where current.trips.contains(tripId) {
            for read in list { current.rule.observe(read.position, of: tripId, readAt: read.readAt) }
        }
        if let latest = history.latest[ride.tripId] {
            current.rule.observe(latest.position, of: ride.tripId, readAt: latest.readAt)
        }
        open = current
        let weighed = current.rule.weighed()
        var stops: [(String, LiveStopsAhead?)] = []
        for candidate in weighed { stops.append((candidate.trip.tripId, await liveStops.stopsAhead(of: candidate.trip))) }
        guard self.generation == generation, var current = open else { return }
        for (tripId, live) in stops { current.rule.setStops(live, of: tripId) }
        let verdict = current.rule.verdict(at: WrongTrainRule.Moment(now: now, departure: current.departure))
        switch verdict {
        case .withTrain:
            open = current
            if presenter.warning?.ride == ride { presenter.withdraw() }
            close(current.warned == nil ? .withTrain : .warned)
            return
        case .wrong(let finding):
            current.following = nil
            open = current
            if current.warned == nil, let warning = await warning(finding, check: current, now: now) {
                guard self.generation == generation, var raised = open else { return }
                if presenter.raise(warning, now: now, rate: 1) != nil {
                    raised.warned = warning
                    open = raised
                }
            }
        case .following(let since):
            current.following = since
            open = current
        case .quiet:
            current.following = nil
            open = current
        }
        guard self.generation == generation, let checked = open else { return }
        if checked.warned == nil, let why = limit(checked, now: now) {
            close(outcomeNow(), why: why)
            return
        }
        restartIfPaused(now: now)
    }

    /// Which limit closes a check that raised nothing, if one has come. T reaching D closes a ride's check (its engine says
    /// so); an alert's stays at the station up to L + 30 min, as the missed train needs, T's arrival or not. Only an alert's
    /// check closes once T is due to have left and the phone is not at O; a ride's runs from its tap (a Yes after T left
    /// is one) and ends with its ride or the movement limits. No good fix yet is not "not at O": the updates get
    /// `leftAfter` from the moment that rule applies, or from the opening, to start.
    private func limit(_ check: Open, now: Date) -> WrongTrainCheckResult.Why? {
        if let firstMove = check.firstMove {
            let span = check.following == nil ? Self.movingSpan : Self.followingSpan
            return now >= firstMove.addingTimeInterval(span) ? .limit : nil
        }
        let isAlert = check.rule.tie == .alert
        let tailFrom = isAlert ? check.departure : max(check.departure, check.openedAt)
        if now >= tailFrom.addingTimeInterval(Self.stationTail) { return .limit }
        let leftAt = check.departure.addingTimeInterval(Self.leftAfter)
        guard isAlert, now >= leftAt else { return nil }
        // T is due to have left: an alert's check stays only while the phone is still at O.
        if let last = check.rule.lastFix() { return last.fromOrigin < Self.stationRadius ? nil : .limit }
        return now >= max(leftAt, check.openedAt).addingTimeInterval(Self.leftAfter) ? .limit : nil
    }

    /// iOS pauses updates for a phone it takes to be at rest, a smooth train among them (TT-220): once T is due to have
    /// left, no good fix for 30 s starts them again, at most once per 30 s. Never read as quiet or as with the train.
    private func restartIfPaused(now: Date) {
        guard var current = open, now >= current.departure else { return }
        let quiet = current.lastGoodFix.map { now.timeIntervalSince($0) >= Self.pausedAfter } ?? true
        let spaced = current.lastRestart.map { now.timeIntervalSince($0) >= Self.pausedAfter } ?? true
        guard quiet, spaced, now.timeIntervalSince(current.openedAt) >= Self.pausedAfter else { return }
        current.lastRestart = now
        open = current
        current.reader.restartUpdates()
    }

    /// The warning for a finding: D's name, X's next stop (the timetable's name for it) and its time, and its expiry.
    private func warning(_ finding: WrongTrainRule.Finding, check: Open, now: Date) async -> WrongTrainWarning? {
        let destination = check.plan.stops.last?.station
        guard let destination else { return nil }
        var nextId = finding.nextStopId
        var nextName: String?
        if let trip = finding.trip {
            let timetableTrip = await timetable.trip(trip)
            if nextId == nil {
                nextId = check.rule.weighed().first { $0.trip == trip }?.stopsAfter.first
            }
            nextName = timetableTrip?.stops.first { $0.station.id == nextId }?.station.name
        } else {
            nextName = check.rule.behind?.name
        }
        guard let nextId, let nextName else { return nil }
        let expires = finding.nextStopTime.map {
            max($0.addingTimeInterval(Self.expiresAfterStop), now.addingTimeInterval(Self.expiresAfterStop))
        } ?? now.addingTimeInterval(Self.expiresWithoutTime)
        return WrongTrainWarning(
            ride: check.ride, reason: finding.reason, evidence: finding.evidence, source: check.source,
            stopName: RideDetails.shortName(destination.name), originId: check.ride.originId,
            nextStopId: nextId, nextStopName: RideDetails.shortName(nextName), nextStopTime: finding.nextStopTime,
            expires: expires, secondsAfter: max(0, finding.seconds), isDemo: false
        )
    }

    // MARK: The watch and the engine

    func followingSince(_ ride: Ride) -> Date? {
        guard let open, open.ride == ride else { return nil }
        return open.following
    }

    func hasWarned(_ ride: Ride) -> Bool {
        (open?.ride == ride && open?.warned != nil) || presenter.warning?.ride == ride
    }

    var keepsLocation: Bool { open != nil || opening }

    /// `RideEngine.holdsEnding` for left the line: while the warning shows for `ride`, or the check follows a train on it,
    /// at most 6 min from the first moving fix.
    func holdsLeftTheLine(of ride: Ride?) -> Bool {
        guard let ride else { return false }
        if presenter.warning?.ride == ride { return true }
        guard let open, open.ride == ride, let following = open.following else { return false }
        return clock.now < (open.firstMove ?? following).addingTimeInterval(Self.followingSpan)
    }

    // MARK: Closing

    private func outcomeNow() -> WrongTrainCheckResult.Outcome {
        guard let open else { return .stayed }
        if open.warned != nil { return .warned }
        return open.firstMove == nil ? .stayed : .noMatch
    }

    /// Closes the open check; `outcome` nil closes it silently (a gate failed, another train took its place).
    private func close(_ outcome: WrongTrainCheckResult.Outcome?, why: WrongTrainCheckResult.Why? = nil) {
        guard let closed = open else { return }
        open = nil
        generation += 1
        loop?.cancel()
        loop = nil
        if let outcome {
            let now = clock.now
            let seconds: Int? = switch outcome {
            case .warned: closed.warned?.secondsAfter
            case .withTrain: closed.firstMove.map { max(0, Int(now.timeIntervalSince($0))) } ?? 0
            case .noMatch, .stayed: nil
            }
            let result = WrongTrainCheckResult(
                outcome: outcome, source: closed.source, seconds: seconds,
                reason: outcome == .warned ? closed.warned?.reason : nil,
                why: outcome == .noMatch || outcome == .stayed ? why : nil
            )
            lastCheck = result
            if store.firstCheck(closed.ride) { Analytics.track(.wrongTrainChecked(result)) }
        } else {
            closedSilently.insert(closed.ride)
        }
        if closed.ownsUpdates, !rideRuns(), !watchIsArmed, !(locationHeld?() ?? false) { closed.reader.stopUpdates() }
    }
}
