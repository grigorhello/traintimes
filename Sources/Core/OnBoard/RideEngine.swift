import Foundation
import Observation

/// Where a ride is (Live-Spec, the six moments): the rows of the ride card, the Live Activity and the taps follow it.
enum RidePhase: String, Codable, Sendable {
    /// Between two stations, your stop not next.
    case riding
    /// Stopped at a station before yours, the origin included.
    case atStation
    /// Your stop is the next one.
    case yourStopNext
    /// About a minute before your stop: the arriving tap (TT-173).
    case arriving
    /// At your stop.
    case atYourStop
    case ended
}

/// What placed the train (Live-Spec): the status line reads "Live · your location", "Live · GO train data" or
/// "Timetable" (greyed, with the last update time).
enum RidePositionSource: String, Sendable {
    case phone
    case trainFeed
    case timetable
}

enum RideEndReason: String, Sendable {
    /// End ride.
    case byRider
    /// 2 min after your stop (TT-223, D103; 10 min before).
    case arrived
    /// 1 km off the line for 3 min.
    case leftTheLine
    /// The trip was cancelled.
    case cancelled
    /// "Not on it" on a ride that started by itself, in its first 10 min (TT-243, D120).
    case notOnIt
    /// The ride that started by itself undid itself: the phone clearly did not go with the train (TT-243, D120,
    /// `AutoRideRule.undoVerdict`).
    case autoUndone
    /// The wrong train warning (TT-250, D127): "Trains from …", or the warning ran out with no answer.
    case wrongTrain
}

/// Where "Not on it" was tapped (TT-243, D120): the Live Activity card or expanded island (`NotOnTrainIntent`), or the ride
/// screen.
enum RideEndSurface: String, Sendable {
    case card, ride
}

/// Everything the ride's views show (TT-172 onward).
struct RideState: Equatable, Sendable {
    var phase: RidePhase
    /// The station the train is at; nil between stations.
    var currentStop: Station?
    /// The first stop ahead; nil at your stop.
    var nextStop: Station?
    /// Stops from the next one to yours, yours included; 0 at your stop.
    var stopsLeft: Int
    /// Whole minutes to your stop, rounded up; 0 there.
    var minutesToYourStop: Int
    /// When the train is expected at your stop: the timetable corrected by the measured offset, else by the feed's delay.
    var expectedArrival: Date
    var source: RidePositionSource
    /// When the phone or the train feed last placed the train; nil before the first fix.
    var lastUpdate: Date?
    var endReason: RideEndReason?
}

/// What the ride's other parts react to: the arriving tap on `.phase(.arriving)` (TT-173), the Live Activity on
/// `.update` (TT-174).
enum RideEvent: Equatable, Sendable {
    case phase(RidePhase)
    /// The state changed.
    case update(RideState)
}

/// The On board ride engine (TT-171, Live-Spec "one position, two sources"). A ride starts for one trip, service date,
/// origin and destination when the rider asks (the button or the departure question's Yes, TT-172 and TT-231), or by
/// itself on an alerted train the phone left the station with (`AutoRideWatch`, TT-242, D120), which asks for nothing. A
/// start the rider asked for asks for When In Use location; so do the Automatic direction and Automatic ride switches, and
/// nothing asks at launch (D60 rule 4 as revised by D116 and D120).
///
/// Position, phone first: GPS about once a second, each fix placed along the trip's track. After 60 s with no fix, the
/// train feed's position (TT-179), then the timetable corrected by the last measured offset or the feed's delay. Phases
/// follow the position: at a station within 200 m of it, your stop next once the last station before it is behind, and
/// arriving once your stop is a minute away. The ride ends with End ride, by itself 2 min after your stop (D103), 1 km off the
/// line for 3 min, or when the trip is cancelled. A ride that started by itself also ends with "Not on it" in its first
/// 10 min, or by itself, silently, when the phone clearly did not go with the train (`AutoRideRule.undoVerdict`, TT-243,
/// D120). It is saved on device and restored at launch, where the background location session is created again. Location
/// is used during a ride, by the automatic ride's watch around an alerted train's departure, and for one look when the app
/// opens to set the route's direction (TT-234, D116); no reading is kept past its use and none is uploaded.
///
/// A ride the phone itself placed at your stop, and that ended there, is Automatic direction's proof of where the rider
/// is (`arrival`, TT-234, D116).
@Observable @MainActor
final class RideEngine: DirectionRideSource {
    static let fixTimeout: TimeInterval = 60
    /// A stationary fix holds this long, since iOS sends nothing while the phone does not move.
    nonisolated static let stationaryTimeout: TimeInterval = 10 * 60
    static let feedTimeout: TimeInterval = 90
    /// A train this close to a station is at it: a GO train and its platform are about 300 m long.
    static let stationRadius = 200.0
    /// The timetable has no dwell times, so a train placed by it is at a station this long either side of its time.
    static let timetableDwell: TimeInterval = 30
    static let arrivingLead: TimeInterval = 60
    /// The ride ends this long after your stop, and the ride screen closes itself (TT-223, D103; 10 min before).
    static let endAfterArrival: TimeInterval = 2 * 60
    static let offLineDistance = 1000.0
    static let offLineDuration: TimeInterval = 3 * 60
    /// A fix less precise than this does not place the train (Precise Location off gives 1 to 20 km).
    static let worstAccuracy = 200.0
    /// A placement this far behind the furthest one measured is an old fix or a lagging train feed: it does not move the
    /// train back (TT-220). Closer, it is noise, or the feed's front car against the phone's, and counts as that point.
    static let behindTolerance = 500.0
    static let storageKey = "onboard.ride"
    /// "Not on it" shows, and the ride may undo itself, this long after a start by itself (TT-243, D120).
    static let undoWindow: TimeInterval = 10 * 60

    private(set) var ride: Ride?
    private(set) var plan: RidePlan?
    private(set) var state: RideState?
    /// When this ride started, and when the train reached your stop; both stay after the ride ends, until the next one
    /// starts, so the arrival wish (TT-223) keeps its ride and its time while the sheet closes.
    @ObservationIgnored private(set) var startedAt: Date?
    @ObservationIgnored private(set) var arrivedAt: Date?
    /// The last ride that ended at your stop after the phone's own fix placed the train there (TT-234, D116): proof of
    /// where the rider is, with no new reading, for Automatic direction. Never a ride that ran on the timetable alone, one
    /// whose arrival only the timetable or the train feed placed, or one `restore()` brings back already over. The next
    /// ride clears it, and it is kept in memory only, never on device.
    private(set) var arrival: RideArrival?
    /// How long and how often the ride screen was on screen during this ride, for `ride_ended` (TT-224, D106); the ride
    /// screen's `RideScreen` keeps it. A relaunch starts it again.
    @ObservationIgnored var watch = RideWatch()
    /// How this ride started (TT-242, D120), saved with it, so `ride_ended` says it after a relaunch; nil for a ride saved
    /// before the app kept it. Not `source`: `RideState.source` is what placed the train.
    private(set) var startSource: RideStartSource?
    /// Each fix as it comes, before the engine's own filter (TT-251, D127): the wrong train check reads the ride's fixes
    /// through it. Set by `AppDelegate`.
    @ObservationIgnored var fixTap: (@MainActor (LocationFix) -> Void)?
    /// Asked before the ride ends as left the line (TT-251, D127): true while the wrong train warning shows for this ride
    /// or the check follows another train on it, so a rider in a train of another line gets the warning, not a silent end.
    /// The other endings are never held. Set by `AppDelegate`.
    @ObservationIgnored var holdsEnding: (@MainActor (RideEndReason) -> Bool)?

    private let data: (any RideDataProviding)?
    private let location: any LocationProviding
    /// The location this ride reads when it is not `location`: the automatic ride's watch's `BackgroundFixes` for a start
    /// with the app closed (TT-243, D120), kept for that ride; the next launch's restore goes back to `location`.
    @ObservationIgnored private var rideLocation: (any LocationProviding)?
    private let trains: (any TrainPositionProviding)?
    private let clock: any AppClock
    private let defaults: UserDefaults?
    private let tickInterval: Duration?

    @ObservationIgnored private var saved: SavedRide?
    @ObservationIgnored private var status = RideStatus.none
    @ObservationIgnored private var fix: MeasuredPosition?
    @ObservationIgnored private var feedPosition: MeasuredPosition?
    @ObservationIgnored private var tracksLocation = false
    @ObservationIgnored private var locationStartedAt = Date.distantPast
    @ObservationIgnored private var offLineSince: Date?
    /// Progress as a rank: 2i at stop i, 2i + 1 between stops i and i + 1. `measuredRank` is the furthest the phone or the
    /// feed placed the train, so a noisy fix never moves it back; a measured position does take back the timetable's guess.
    @ObservationIgnored private var rank = 0
    @ObservationIgnored private var measuredRank = 0
    /// The furthest along the track the phone or the feed placed the train. Ranks alone let a placement behind it reset
    /// the delay on a long stretch, such as Clarkson to Union with no stop between (TT-220).
    @ObservationIgnored private var measuredAlong = -Double.infinity
    /// The undo by itself's rule (TT-243, D120), fed this ride's fixes and the feed's positions in the first 10 min of a
    /// ride that started by itself; nil otherwise.
    @ObservationIgnored private var undoRule: AutoRideRule?
    /// The phone's own fix placed the train at your stop in this ride: what makes its end there a proof (`arrival`).
    @ObservationIgnored private var phoneReachedYourStop = false
    /// The last phase sent as `.phase`.
    @ObservationIgnored private var announcedPhase: RidePhase?
    @ObservationIgnored private var loop: Task<Void, Never>?
    /// A start is awaiting its plan: another one returns false, so the automatic start and the rider's Yes never both begin
    /// a ride (TT-242).
    @ObservationIgnored private var isStarting = false
    @ObservationIgnored private var subscribers: [UUID: AsyncStream<RideEvent>.Continuation] = [:]

    /// `tickInterval` nil runs no timer: tests call `update()` and `refresh()` themselves. `defaults` nil keeps no ride on
    /// device (previews and fixture runs).
    init(
        data: (any RideDataProviding)?,
        location: any LocationProviding,
        trains: (any TrainPositionProviding)? = nil,
        clock: any AppClock,
        defaults: UserDefaults?,
        tickInterval: Duration? = .seconds(1)
    ) {
        self.data = data
        self.location = location
        self.trains = trains
        self.clock = clock
        self.defaults = defaults
        self.tickInterval = tickInterval
    }

    /// A ride can start: the app has the GO feed's trips (fixture runs have none).
    var canStart: Bool { data != nil }

    /// The stops a ride on that train would have, without starting it: the before-departure Live Activity is made with the
    /// ride's stop count, so the hand-off keeps it (TT-178).
    func plan(for ride: Ride) async -> RidePlan? {
        try? await data?.ridePlan(for: ride)
    }

    /// The rider has not answered the When In Use prompt yet: the first "I'm on board" shows the app's sheet before
    /// `start(_:)` asks (TT-172).
    var asksForLocation: Bool { location.canAsk }

    /// The engine's clock, which the ride's countdowns are read against (Mock time, or the demo ride's own clock).
    var now: Date { clock.now }

    /// A ride runs, or one is saved on device and not restored yet (TT-234, D116): Automatic direction does not look
    /// meanwhile.
    var holdsRide: Bool {
        if let state, state.phase != .ended { return true }
        return SavedRide.read(from: defaults, key: Self.storageKey) != nil
    }

    /// The ride, or before a launch's restore the one saved on device: the wrong train notification's "Trains from …"
    /// ends only that train's ride on a cold launch (TT-250, D127).
    var rideOrSaved: Ride? {
        ride ?? SavedRide.read(from: defaults, key: Self.storageKey)?.ride
    }

    // MARK: Start, restore, end

    /// Starts a ride. One the rider asked for (`asks`) asks for When In Use location here, the engine's only ask (the
    /// Automatic direction and Automatic ride switches ask it too, D116, D120; nothing asks at launch); without it the ride
    /// runs on the timetable. An automatic start (`asks` false, TT-242, D120) never asks: a prompt from the background would
    /// never be answered, so it goes by what is allowed. `location`: the automatic ride's watch's own, for a start with the
    /// app closed (TT-243): its `BackgroundFixes` already run in the background, so no new session is made from there; the
    /// ride keeps it until the next launch's restore. False when the trip does not run that day between those stations, or
    /// while another start awaits its plan.
    @discardableResult
    func start(
        _ ride: Ride, source: RideStartSource = .onBoard, asks: Bool = true, location rideLocation: (any LocationProviding)? = nil
    ) async -> Bool {
        guard !isStarting else { return false }
        isStarting = true
        defer { isStarting = false }
        guard let data, let plan = try? await data.ridePlan(for: ride), plan.stops.count >= 2 else { return false }
        let reader = rideLocation ?? location
        let allowed = asks ? await reader.requestWhenInUse() : reader.isAuthorized
        let status = await data.rideStatus(for: ride)
        stopTracking()
        self.rideLocation = rideLocation
        begin(
            ride, plan: plan, saved: SavedRide(ride: ride, startedAt: clock.now, startSource: source), status: status,
            tracksLocation: allowed
        )
        return true
    }

    /// Picks up the ride saved on device, at launch, also when iOS relaunches the app in the background for it: the
    /// background session is created again here. Never asks for location: a saved ride was allowed when it started.
    func restore() async {
        guard ride == nil, let saved = SavedRide.read(from: defaults, key: Self.storageKey) else { return }
        guard let data, let plan = try? await data.ridePlan(for: saved.ride), plan.stops.count >= 2 else {
            SavedRide.clear(from: defaults, key: Self.storageKey)
            return
        }
        let status = await data.rideStatus(for: saved.ride)
        // End ride while the plan and status loaded (TT-174) removed the saved ride.
        guard ride == nil, SavedRide.read(from: defaults, key: Self.storageKey) != nil else { return }
        // The app's own location again, also for a ride that started on the watch's with the app closed (TT-243).
        rideLocation = nil
        // A ride 2 min past your stop is over: it ends at once on the timetable, and location does not start again.
        let offset = status.delay ?? saved.offset ?? 0
        let reachedAt = saved.arrivedAt ?? plan.stops[plan.stops.count - 1].arrival.addingTimeInterval(offset)
        let isOver = clock.now.timeIntervalSince(reachedAt) >= Self.endAfterArrival
        begin(saved.ride, plan: plan, saved: saved, status: status, tracksLocation: location.isAuthorized && !isOver)
    }

    /// End ride. Before a launch's restore has finished (the Live Activity's End ride opening a stopped app, TT-174) there
    /// is no state yet: the saved ride goes, so `restore()` does not bring it back and its Live Activity ends at once.
    func end() {
        guard state != nil else {
            SavedRide.clear(from: defaults, key: Self.storageKey)
            return
        }
        end(.byRider)
    }

    /// The location the running ride reads.
    private var reader: any LocationProviding { rideLocation ?? location }

    /// When "Not on it" stops showing for the ride (TT-243, D120): 10 min after it started by itself; nil for any other ride,
    /// before a start or once it ended.
    var autoUndoUntil: Date? {
        guard startSource == .auto, let startedAt, let state, state.phase != .ended else { return nil }
        return startedAt.addingTimeInterval(Self.undoWindow)
    }

    /// The ride's events, from now on; each caller gets its own stream.
    func events() -> AsyncStream<RideEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: RideEvent.self)
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.subscribers[id] = nil }
        }
        return stream
    }

    private func begin(_ ride: Ride, plan: RidePlan, saved: SavedRide, status: RideStatus, tracksLocation: Bool) {
        self.ride = ride
        self.plan = plan
        self.saved = saved
        self.status = status
        state = nil
        startedAt = saved.startedAt
        startSource = saved.startSource
        watch = RideWatch()
        arrivedAt = saved.arrivedAt
        fix = nil
        feedPosition = nil
        offLineSince = nil
        rank = 0
        measuredRank = 0
        measuredAlong = -.infinity
        phoneReachedYourStop = false
        // A new ride: the last one's proof no longer says where the rider is.
        arrival = nil
        announcedPhase = nil
        // The undo by itself watches the first 10 min of a ride that started by itself (TT-243, D120).
        undoRule = saved.startSource == .auto && clock.now < saved.startedAt.addingTimeInterval(Self.undoWindow)
            ? AutoRideRule(plan: plan, originId: ride.originId, armedLate: false, reportsStationary: Self.reportsStationary)
            : nil
        // Without a track a fix cannot place the train, so the phone is not used.
        self.tracksLocation = tracksLocation && plan.track != nil
        locationStartedAt = clock.now
        if self.tracksLocation {
            reader.startUpdates { [weak self] fix in self?.receive(fix) }
        }
        save()
        update()
        guard state?.phase != .ended else { return }
        startLoop()
    }

    /// Ends the ride for `reason`; End ride is `end()`. `surface`: where Not on it was tapped (TT-243, D120). Before a
    /// launch's restore has finished (the card's Not on it in a stopped app) there is no state yet: the saved ride is read
    /// for how it started, `ride_ended` goes with the reason, the source and the surface, and the saved ride goes, so
    /// `restore()` does not bring it back. Not on it and the undo by itself decline the train for today
    /// (`DetectionStore.silence`), so nothing asks about it again. Returns the ride it ended, nil when none ran.
    @discardableResult
    func end(_ reason: RideEndReason, surface: RideEndSurface? = nil) -> Ride? {
        guard var ended = state else {
            guard let saved = SavedRide.read(from: defaults, key: Self.storageKey) else { return nil }
            Analytics.track(.rideEnded(reason, source: saved.startSource, surface: surface))
            SavedRide.clear(from: defaults, key: Self.storageKey)
            declineIfUndone(saved.ride, reason: reason)
            return saved.ride
        }
        guard ended.phase != .ended else { return nil }
        stopTracking()
        let atStop = ended.phase == .atYourStop
        ended.phase = .ended
        ended.endReason = reason
        state = ended
        // Ended at your stop, by itself, by Done or by End ride there, after the phone's own fix placed the train at it:
        // Automatic direction's proof (TT-234, D116). Tracking has stopped by now, so the ride remembered it.
        if atStop, phoneReachedYourStop, let ride {
            arrival = RideArrival(stopId: ride.destinationId, at: clock.now)
        }
        Analytics.track(.rideEnded(
            reason, source: startSource, atStop: atStop, watchedSeconds: watch.seconds(at: Date()), opens: watch.opens,
            surface: surface
        ))
        SavedRide.clear(from: defaults, key: Self.storageKey)
        saved = nil
        undoRule = nil
        if let ride { declineIfUndone(ride, reason: reason) }
        emit(.phase(.ended))
        emit(.update(ended))
        return ride
    }

    /// Not on it, the undo by itself and the wrong train's ending (TT-250, D127): the train is declined for today, straight
    /// in the store (never `DepartureQuestion.decline`, which would count a question answer that never came).
    private func declineIfUndone(_ ride: Ride, reason: RideEndReason) {
        guard reason == .notOnIt || reason == .autoUndone || reason == .wrongTrain, let defaults else { return }
        DetectionStore.silence([ride.tripKey], in: defaults)
    }

    private func stopTracking() {
        loop?.cancel()
        loop = nil
        if tracksLocation { reader.stopUpdates() }
        tracksLocation = false
    }

    /// iOS sends a stationary update when the phone stops from iOS 18 on, as the watch reads it (TT-242).
    private static var reportsStationary: Bool {
        if #available(iOS 18, *) { return true }
        return false
    }

    private func startLoop() {
        guard let tickInterval else { return }
        loop = Task { [weak self] in
            var ticks = 0
            while !Task.isCancelled, self != nil {
                // The live status every 15 s; the timer itself moves the countdown and the timetable position.
                if ticks % 15 == 0 { await self?.refresh() }
                self?.update()
                ticks += 1
                try? await Task.sleep(for: tickInterval)
            }
        }
    }

    // MARK: Inputs

    /// A fix from the phone, placed at the time iOS measured it. A fix more than 1 km off the line does not place the train
    /// and starts the off-the-line count, from the scheduled departure on. A fix older than 60 s says nothing about now.
    func receive(_ fix: LocationFix) {
        fixTap?(fix)
        // The undo by itself counts only good fixes, by its own rule (TT-243).
        if state?.phase != .ended { undoRule?.observe(fix, at: clock.now) }
        guard let plan, let track = plan.track, state?.phase != .ended, fix.age < Self.fixTimeout,
              fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= Self.worstAccuracy else { return }
        let now = clock.now
        let projection = track.shape.project(fix.coordinate)
        if projection.off > Self.offLineDistance {
            if now >= plan.stops[0].departure { offLineSince = offLineSince ?? now }
        } else {
            offLineSince = nil
            self.fix = MeasuredPosition(along: projection.along, at: now.addingTimeInterval(-fix.age), isStationary: fix.isStationary)
        }
        update()
    }

    /// The trip's live status and the train feed's position, which places the train while the phone has no fix.
    func refresh() async {
        guard let ride, let data, state?.phase != .ended else { return }
        let status = await data.rideStatus(for: ride)
        let position = await trains?.position(of: ride.tripKey)
        guard self.ride == ride, state?.phase != .ended else { return }
        self.status = status
        if let position { undoRule?.observe(position, readAt: clock.now) }
        if let position, let track = plan?.track {
            let projection = track.shape.project(position.coordinate)
            feedPosition = projection.off <= Self.offLineDistance
                ? MeasuredPosition(along: projection.along, at: position.reportedAt, isStationary: false)
                : nil
        }
        update()
    }

    // MARK: The rules

    /// Works out the position, the phase and the countdown at the clock's time, and ends the ride when a rule says so.
    func update() {
        guard let plan, var saved, state?.phase != .ended else { return }
        let now = clock.now
        let last = plan.stops.count - 1

        let source = source(at: now)
        let measured = source == .phone ? fix : source == .trainFeed ? feedPosition : nil
        // Until the phone's first fix the timetable only fills the card in: it moves nothing for good, makes no arrival,
        // and sends no phase.
        let isProvisional = source == .phone && measured == nil
        let shown: Int
        if let measured, let track = plan.track {
            // Never behind the furthest point measured: a placement well behind it is old and is left out, a little
            // behind counts as that point (TT-220).
            let isBehind = measured.along < measuredAlong - Self.behindTolerance
            let along = max(measured.along, measuredAlong)
            let placed = Self.rank(along: along, stops: track.stopDistances)
            // The phone's own fix, not the train feed or the timetable, is at your stop: the ride's proof (TT-234, D116).
            if source == .phone, Self.rank(along: measured.along, stops: track.stopDistances) >= 2 * last {
                phoneReachedYourStop = true
            }
            // Once the train was measured at your stop the offset stays what it was on arrival: standing there is not
            // running late (TT-172, the card's "On time · Ride complete").
            if !isBehind, placed >= measuredRank, saved.arrivedAt == nil || saved.arrivalGuessed == true {
                measuredRank = placed
                measuredAlong = along
                // A stationary fix stands for now, since iOS sends nothing more while the train does not move.
                let time = measured.isStationary ? now : measured.at
                saved.offset = Self.offset(rank: placed, along: along, at: time, now: now, plan: plan)
                // Measured at your stop: an arrival the timetable placed is now the train's, and the offset stays.
                if placed >= 2 * last, saved.arrivalGuessed == true { saved.arrivalGuessed = nil }
            }
            // The phone and the feed correct the timetable, back too: an arrival it guessed is taken back.
            rank = measuredRank
            if rank < 2 * last, saved.arrivalGuessed == true {
                saved.arrivedAt = nil
                saved.arrivalGuessed = nil
            }
            if !isBehind { saved.lastUpdate = measured.at }
            shown = rank
        } else {
            let offset = status.delay ?? saved.offset ?? 0
            shown = max(rank, measuredRank, Self.rank(at: now.addingTimeInterval(-offset), stops: plan.stops))
            if !isProvisional { rank = shown }
        }

        let offset = (measured != nil ? saved.offset : nil) ?? status.delay ?? saved.offset ?? 0
        let expectedArrival = plan.stops[last].arrival.addingTimeInterval(offset)
        if shown >= 2 * last, saved.arrivedAt == nil, !isProvisional {
            if measured == nil {
                // The timetable places the arrival at its expected time, never before the ride started, so a ride
                // restored long after ends at once.
                saved.arrivedAt = max(saved.startedAt, min(now, expectedArrival))
                saved.arrivalGuessed = true
            } else {
                saved.arrivedAt = now
            }
        }

        let index = saved.arrivedAt != nil ? last : min(shown / 2, last)
        let isAtStop = saved.arrivedAt != nil || shown % 2 == 0
        let phase: RidePhase
        if index == last {
            phase = .atYourStop
        } else if isAtStop {
            phase = .atStation
        } else if index + 1 == last {
            let isClose = !isProvisional && expectedArrival.timeIntervalSince(now) <= Self.arrivingLead
            phase = isClose || state?.phase == .arriving ? .arriving : .yourStopNext
        } else {
            phase = .riding
        }
        // The arriving tap comes once a ride (D60), also when a correction brings the train back before it.
        let announces = !isProvisional && phase != announcedPhase && !(phase == .arriving && saved.announcedArriving == true)
        if announces, phase == .arriving { saved.announcedArriving = true }

        if saved != self.saved {
            // Kept on device when the arrival, the arriving tap or the offset moves; not on every fix.
            let before = self.saved
            let offsetMoved = abs((saved.offset ?? 0) - (before?.offset ?? 0)) >= 30 || (saved.offset == nil) != (before?.offset == nil)
            self.saved = saved
            if offsetMoved || saved.arrivedAt != before?.arrivedAt || saved.announcedArriving != before?.announcedArriving {
                save()
            }
        }

        let current = RideState(
            phase: phase,
            currentStop: isAtStop ? plan.stops[index].station : nil,
            nextStop: index < last ? plan.stops[index + 1].station : nil,
            stopsLeft: last - index,
            minutesToYourStop: phase == .atYourStop ? 0 : max(0, Int((expectedArrival.timeIntervalSince(now) / 60).rounded(.up))),
            expectedArrival: expectedArrival,
            source: source,
            lastUpdate: saved.lastUpdate
        )

        arrivedAt = saved.arrivedAt
        let ending: RideEndReason? = if status.isCancelled {
            .cancelled
        } else if let offLineSince, now.timeIntervalSince(offLineSince) >= Self.offLineDuration,
                  !(holdsEnding?(.leftTheLine) ?? false) {
            .leftTheLine
        } else if let arrivedAt = saved.arrivedAt, now.timeIntervalSince(arrivedAt) >= Self.endAfterArrival {
            .arrived
        } else if isUndone(at: now, startedAt: saved.startedAt) {
            .autoUndone
        } else {
            nil
        }
        if let ending {
            state = current
            end(ending)
            return
        }
        let changed = current != state
        if changed { state = current }
        if announces {
            announcedPhase = phase
            emit(.phase(phase))
        }
        if changed { emit(.update(current)) }
    }

    /// The undo by itself (TT-243, D120): in the first 10 min of a ride that started by itself, the phone clearly did not go
    /// with the train. Its rule is let go once the 10 min are over.
    private func isUndone(at now: Date, startedAt: Date) -> Bool {
        guard let rule = undoRule else { return false }
        guard now < startedAt.addingTimeInterval(Self.undoWindow) else {
            undoRule = nil
            return false
        }
        return rule.undoVerdict(at: now) != .keeps
    }

    /// The phone while it has a fix less than 60 s old (or a stationary one, which iOS does not repeat), and for the first
    /// 60 s of the ride while the first fix comes; then the train feed while its position is fresh; then the timetable.
    /// A held stationary fix gives way to the feed once the feed places the train further on: iOS can take a smooth train
    /// for a phone at rest and send nothing while it runs (TT-220).
    private func source(at now: Date) -> RidePositionSource {
        let freshFeed = feedPosition.flatMap { now.timeIntervalSince($0.at) < Self.feedTimeout ? $0 : nil }
        if tracksLocation {
            if let fix {
                let age = now.timeIntervalSince(fix.at)
                if age < Self.fixTimeout { return .phone }
                if fix.isStationary, age < Self.stationaryTimeout {
                    if let freshFeed, freshFeed.along > fix.along + Self.behindTolerance { return .trainFeed }
                    return .phone
                }
            } else if now.timeIntervalSince(locationStartedAt) < Self.fixTimeout {
                return .phone
            }
        }
        if freshFeed != nil { return .trainFeed }
        return .timetable
    }

    /// The rank of a train `along` metres down the track: at the nearest stop within 200 m, else between the stops either
    /// side; before the origin it waits at it, past your stop it is there.
    static func rank(along: Double, stops: [Double]) -> Int {
        guard let last = stops.indices.last else { return 0 }
        if let nearest = stops.indices.min(by: { abs(stops[$0] - along) < abs(stops[$1] - along) }),
           abs(stops[nearest] - along) <= stationRadius {
            return 2 * nearest
        }
        if along <= stops[0] { return 0 }
        if along >= stops[last] { return 2 * last }
        let before = stops.lastIndex { $0 < along } ?? 0
        return 2 * before + 1
    }

    /// The rank the timetable gives at `time` (the clock less the offset): at a station from `timetableDwell` before its
    /// time to as long after, at the origin until it leaves, at your stop from its time on.
    static func rank(at time: Date, stops: [RidePlan.Stop]) -> Int {
        let last = stops.count - 1
        if time >= stops[last].arrival { return 2 * last }
        for index in 0..<last {
            let opens = index == 0 ? Date.distantPast : stops[index].arrival.addingTimeInterval(-timetableDwell)
            let closes = stops[index].departure.addingTimeInterval(index == 0 ? 0 : timetableDwell)
            if time < opens { return 2 * index - 1 }
            if time <= closes { return 2 * index }
        }
        return 2 * last - 1
    }

    /// How late the train is, from where it was placed: at a station it is late only once it is still there after its
    /// departure time (GO trains never leave early); between stations, against the timetable's time for that point.
    static func offset(rank: Int, along: Double, at time: Date, now: Date, plan: RidePlan) -> TimeInterval? {
        guard let distances = plan.track?.stopDistances else { return nil }
        let index = rank / 2
        guard rank % 2 == 1, index + 1 < plan.stops.count else {
            return max(0, now.timeIntervalSince(plan.stops[min(index, plan.stops.count - 1)].departure))
        }
        let from = plan.stops[index], to = plan.stops[index + 1]
        let span = distances[index + 1] - distances[index]
        let fraction = span > 0 ? min(max((along - distances[index]) / span, 0), 1) : 0
        let scheduled = from.departure.addingTimeInterval(to.arrival.timeIntervalSince(from.departure) * fraction)
        return time.timeIntervalSince(scheduled)
    }

    private func emit(_ event: RideEvent) {
        for subscriber in subscribers.values { subscriber.yield(event) }
    }

    private func save() {
        saved?.write(to: defaults, key: Self.storageKey)
    }
}

/// A placing of the train along its track, and when it was made.
private struct MeasuredPosition {
    let along: Double
    let at: Date
    let isStationary: Bool
}

/// The ride as kept on device (`onboard.ride`) while it lasts, to restore it at launch.
struct SavedRide: Codable, Equatable {
    var ride: Ride
    var startedAt: Date
    /// Seconds late, as last measured.
    var offset: TimeInterval?
    var arrivedAt: Date?
    /// The timetable, not the phone or the feed, placed the arrival; a measured position takes it back.
    var arrivalGuessed: Bool?
    var announcedArriving: Bool?
    var lastUpdate: Date?
    /// How the ride started (TT-242); nil in a ride saved before it was kept.
    var startSource: RideStartSource?

    static func read(from defaults: UserDefaults?, key: String) -> SavedRide? {
        defaults?.data(forKey: key).flatMap { try? JSONDecoder().decode(SavedRide.self, from: $0) }
    }

    static func clear(from defaults: UserDefaults?, key: String) {
        defaults?.removeObject(forKey: key)
    }

    func write(to defaults: UserDefaults?, key: String) {
        guard let defaults, let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: key)
    }
}
