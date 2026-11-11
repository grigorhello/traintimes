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
    /// 10 min after your stop.
    case arrived
    /// 1 km off the line for 3 min.
    case leftTheLine
    /// The trip was cancelled.
    case cancelled
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
/// origin and destination, only when the rider asks (the button or the matcher's question, TT-172 and TT-175): it never
/// starts on its own, and it is the only place that asks for location.
///
/// Position, phone first: GPS about once a second, each fix placed along the trip's track. After 60 s with no fix, the
/// train feed's position (TT-179), then the timetable corrected by the last measured offset or the feed's delay. Phases
/// follow the position: at a station within 200 m of it, your stop next once the last station before it is behind, and
/// arriving once your stop is a minute away. The ride ends with End ride, by itself 10 min after your stop, 1 km off the
/// line for 3 min, or when the trip is cancelled. It is saved on device and restored at launch, where the background
/// location session is created again; location is used only during a ride and never leaves the phone.
@Observable @MainActor
final class RideEngine {
    static let fixTimeout: TimeInterval = 60
    /// A stationary fix holds this long, since iOS sends nothing while the phone does not move.
    static let stationaryTimeout: TimeInterval = 10 * 60
    static let feedTimeout: TimeInterval = 90
    /// A train this close to a station is at it: a GO train and its platform are about 300 m long.
    static let stationRadius = 200.0
    /// The timetable has no dwell times, so a train placed by it is at a station this long either side of its time.
    static let timetableDwell: TimeInterval = 30
    static let arrivingLead: TimeInterval = 60
    static let endAfterArrival: TimeInterval = 10 * 60
    static let offLineDistance = 1000.0
    static let offLineDuration: TimeInterval = 3 * 60
    /// A fix less precise than this does not place the train (Precise Location off gives 1 to 20 km).
    static let worstAccuracy = 200.0
    static let storageKey = "onboard.ride"

    private(set) var ride: Ride?
    private(set) var plan: RidePlan?
    private(set) var state: RideState?

    private let data: (any RideDataProviding)?
    private let location: any LocationProviding
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
    /// The last phase sent as `.phase`.
    @ObservationIgnored private var announcedPhase: RidePhase?
    @ObservationIgnored private var loop: Task<Void, Never>?
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

    // MARK: Start, restore, end

    /// Starts a ride the rider asked for. Asks for When In Use location here, and nowhere else; without it the ride runs
    /// on the timetable. False when the trip does not run that day between those stations.
    @discardableResult
    func start(_ ride: Ride) async -> Bool {
        guard let data, let plan = try? await data.ridePlan(for: ride), plan.stops.count >= 2 else { return false }
        let allowed = await location.requestWhenInUse()
        let status = await data.rideStatus(for: ride)
        stopTracking()
        begin(ride, plan: plan, saved: SavedRide(ride: ride, startedAt: clock.now), status: status, tracksLocation: allowed)
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
        guard ride == nil else { return }
        // A ride 10 min past your stop is over: it ends at once on the timetable, and location does not start again.
        let offset = status.delay ?? saved.offset ?? 0
        let arrival = saved.arrivedAt ?? plan.stops[plan.stops.count - 1].arrival.addingTimeInterval(offset)
        let isOver = clock.now.timeIntervalSince(arrival) >= Self.endAfterArrival
        begin(saved.ride, plan: plan, saved: saved, status: status, tracksLocation: location.isAuthorized && !isOver)
    }

    /// End ride.
    func end() {
        end(.byRider)
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
        fix = nil
        feedPosition = nil
        offLineSince = nil
        rank = 0
        measuredRank = 0
        announcedPhase = nil
        // Without a track a fix cannot place the train, so the phone is not used.
        self.tracksLocation = tracksLocation && plan.track != nil
        locationStartedAt = clock.now
        if self.tracksLocation {
            location.startUpdates { [weak self] fix in self?.receive(fix) }
        }
        save()
        update()
        guard state?.phase != .ended else { return }
        startLoop()
    }

    private func end(_ reason: RideEndReason) {
        guard var ended = state, ended.phase != .ended else { return }
        stopTracking()
        ended.phase = .ended
        ended.endReason = reason
        state = ended
        SavedRide.clear(from: defaults, key: Self.storageKey)
        saved = nil
        emit(.phase(.ended))
        emit(.update(ended))
    }

    private func stopTracking() {
        loop?.cancel()
        loop = nil
        if tracksLocation { location.stopUpdates() }
        tracksLocation = false
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

    /// A fix from the phone. A fix more than 1 km off the line does not place the train and starts the off-the-line
    /// count, from the scheduled departure on.
    func receive(_ fix: LocationFix) {
        guard let plan, let track = plan.track, state?.phase != .ended,
              fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= Self.worstAccuracy else { return }
        let now = clock.now
        let projection = track.shape.project(fix.coordinate)
        if projection.off > Self.offLineDistance {
            if now >= plan.stops[0].departure { offLineSince = offLineSince ?? now }
        } else {
            offLineSince = nil
            self.fix = MeasuredPosition(along: projection.along, at: now, isStationary: fix.isStationary)
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
            let placed = Self.rank(along: measured.along, stops: track.stopDistances)
            if placed >= measuredRank {
                measuredRank = placed
                // A stationary fix stands for now, since iOS sends nothing more while the train does not move.
                let time = measured.isStationary ? now : measured.at
                saved.offset = Self.offset(rank: placed, along: measured.along, at: time, now: now, plan: plan)
            }
            // The phone and the feed correct the timetable, back too: an arrival it guessed is taken back.
            rank = measuredRank
            if rank < 2 * last, saved.arrivalGuessed == true {
                saved.arrivedAt = nil
                saved.arrivalGuessed = nil
            }
            saved.lastUpdate = measured.at
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

        let ending: RideEndReason? = if status.isCancelled {
            .cancelled
        } else if let offLineSince, now.timeIntervalSince(offLineSince) >= Self.offLineDuration {
            .leftTheLine
        } else if let arrivedAt = saved.arrivedAt, now.timeIntervalSince(arrivedAt) >= Self.endAfterArrival {
            .arrived
        } else {
            nil
        }
        if let ending {
            state = current
            return end(ending)
        }
        let changed = current != state
        if changed { state = current }
        if announces {
            announcedPhase = phase
            emit(.phase(phase))
        }
        if changed { emit(.update(current)) }
    }

    /// The phone while it has a fix less than 60 s old (or a stationary one, which iOS does not repeat), and for the first
    /// 60 s of the ride while the first fix comes; then the train feed while its position is fresh; then the timetable.
    private func source(at now: Date) -> RidePositionSource {
        if tracksLocation {
            if let fix {
                let age = now.timeIntervalSince(fix.at)
                if age < Self.fixTimeout || (fix.isStationary && age < Self.stationaryTimeout) { return .phone }
            } else if now.timeIntervalSince(locationStartedAt) < Self.fixTimeout {
                return .phone
            }
        }
        if let feedPosition, now.timeIntervalSince(feedPosition.at) < Self.feedTimeout { return .trainFeed }
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
