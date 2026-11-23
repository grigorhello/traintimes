import Foundation
import XCTest
@testable import TrainTimes

/// Automatic ride test values (TT-242): the On board tests' train (`OnBoardFixtures`, Union to Clarkson at 11:17 AM on the
/// synthetic track), a phone that leaves with it, and GO's positions of it.
enum AutoRideFixtures {
    /// L: the train's departure from Union.
    static func departure(_ plan: RidePlan) -> Date { plan.stops[0].departure }

    /// The phone on the train, `seconds` after L: at the station until 10 s, then 0.5 m/s² up to 25 m/s.
    static func boarding(_ seconds: Double, moves: Double = 10) -> Double {
        let t = seconds - moves
        guard t > 0 else { return 0 }
        let cruise = 50.0
        return t <= cruise ? 0.25 * t * t : 625 + 25 * (t - cruise)
    }

    /// A point `along` metres past the plan's origin on its track, `north` metres north of it.
    static func point(_ plan: RidePlan, along: Double, north: Double = 0) -> GeoPoint {
        let track = plan.track!
        var point = track.shape.point(at: track.stopDistances[0] + along)
        point.latitude += north / 111_195.08
        return point
    }

    /// A train leaving Union a minute after this one, on `shape` (this trip's track unless given).
    static func rival(_ plan: RidePlan, id: String = "RIVAL", after: TimeInterval = 60, shape: TrackShape? = nil) -> RivalTrain {
        let track = plan.track!
        return RivalTrain(
            trip: TripKey(serviceDay: OnBoardFixtures.friday, tripId: id), departure: departure(plan).addingTimeInterval(after),
            shape: shape ?? track.shape, originAlong: shape == nil ? track.stopDistances[0] : 0
        )
    }

    /// A track that leaves this one `after` metres past Union and turns north.
    static func parting(_ plan: RidePlan, after: Double) -> TrackShape {
        let start = point(plan, along: 0)
        let fork = point(plan, along: after)
        var away = fork
        away.latitude += 5000 / 111_195.08
        return TrackShape(points: [start, fork, away])
    }
}

/// The rule with a clock in seconds after L: fixes, positions and verdicts.
struct RuleRig {
    var rule: AutoRideRule
    let plan: RidePlan
    let departure: Date
    var arrival: Date
    var leftAt: Date?
    var answered = false

    /// `origin` names the station for the covered form only (`UN` is covered); the track is always Union's.
    init(origin: String = "EX", armedLate: Bool = false, reportsStationary: Bool = true) throws {
        plan = try OnBoardFixtures.plan()
        rule = try XCTUnwrap(AutoRideRule(plan: plan, originId: origin, armedLate: armedLate, reportsStationary: reportsStationary))
        departure = AutoRideFixtures.departure(plan)
        arrival = plan.stops[plan.stops.count - 1].arrival
    }

    func time(_ seconds: Double) -> Date { departure.addingTimeInterval(seconds) }

    mutating func phone(
        _ seconds: Double, along: Double, north: Double = 0, accuracy: Double = 8, stationary: Bool = false, age: Double = 0
    ) {
        let fix = LocationFix(
            coordinate: AutoRideFixtures.point(plan, along: along, north: north), horizontalAccuracy: accuracy,
            isStationary: stationary, age: age
        )
        rule.observe(fix, at: time(seconds + age))
    }

    /// GO's position reported at `seconds`, read `lag` later.
    mutating func train(_ seconds: Double, along: Double, lag: Double = 40, vehicleTime: Bool = true) {
        let position = TrainPosition(
            coordinate: AutoRideFixtures.point(plan, along: along), reportedAt: time(seconds), hasVehicleTime: vehicleTime
        )
        rule.observe(position, readAt: time(seconds + lag))
    }

    mutating func rival(_ id: String, _ seconds: Double, along: Double, north: Double = 0, lag: Double = 40) {
        let position = TrainPosition(coordinate: AutoRideFixtures.point(plan, along: along, north: north), reportedAt: time(seconds))
        rule.observe(position, rival: id, readAt: time(seconds + lag))
    }

    func verdict(_ seconds: Double) -> AutoRideRule.Verdict {
        rule.verdict(at: AutoRideRule.Moment(
            now: time(seconds), departure: departure, leftAt: leftAt, arrival: arrival, answered: answered
        ))
    }

    /// Plays the seconds `from` to `to`: a fix each second where `phone` gives one, GO's position of the train every 30 s
    /// (reported on the half minute after L, read 40 s later) where `train` gives one, leftAt at `left` s, and a verdict each
    /// second. Returns the first verdict that is not waiting, and its second.
    mutating func run(
        from: Int, to: Int, left: Double? = 60,
        phone: (Double) -> (along: Double, north: Double, stationary: Bool)? = { (AutoRideFixtures.boarding($0), 0, false) },
        train: ((Double) -> Double?)? = { AutoRideFixtures.boarding($0) },
        stopAt: (AutoRideRule.Verdict) -> Bool = { $0 != .waiting }
    ) -> (verdict: AutoRideRule.Verdict, second: Int)? {
        for second in from...to {
            let s = Double(second)
            if let left, s >= left { leftAt = time(left) }
            if let fix = phone(s) { self.phone(s, along: fix.along, north: fix.north, stationary: fix.stationary) }
            let reported = s - 40
            if let train, reported >= -600, Int(reported) % 30 == 0, let along = train(reported) {
                self.train(reported, along: along)
            }
            let verdict = verdict(s)
            if stopAt(verdict) { return (verdict, second) }
        }
        return nil
    }
}

/// The alert server's side of the hold in watch tests: the departure card on the phone, the held train, and every report
/// with what the server answered.
@MainActor
final class FakeHoldReporter: AutoRideHolding {
    var departureRide: Ride?
    var heldRide: Ride?
    private(set) var reports: [LiveActivityReport] = []
    /// What the server answers, in order; true once they run out.
    var answers: [Bool] = []

    func reportHold(_ activity: LiveActivityReport) async -> Bool {
        reports.append(activity)
        return answers.isEmpty ? true : answers.removeFirst()
    }

    var holds: [Bool?] { reports.map(\.holds) }
}

/// The alerted train's live status in watch tests: on time unless `delay`, and GO's train feed placing it `originMetres`
/// from the station 10 s ago (nil: no position, so the clock says when it left).
actor FakeDepartures: AutoRideDepartureReading {
    var delay: TimeInterval = 0
    var originMetres: Double?
    var unreadable = false

    func set(delay: TimeInterval) { self.delay = delay }
    func set(originMetres: Double?) { self.originMetres = originMetres }

    func departure(of trip: Trip, ride: Ride, at now: Date) async -> Departure? {
        guard !unreadable else { return nil }
        let update = LiveTripUpdate(
            expectedDeparture: trip.scheduledDeparture.addingTimeInterval(delay),
            expectedArrival: trip.scheduledArrival.addingTimeInterval(delay), delayMinutes: Int(delay / 60), reportedAt: now
        )
        var live = LiveSnapshot(updatedAt: now, updates: [trip.key.tripId: update])
        if let originMetres {
            live.originFixes = [trip.key.tripId: OriginFix(metres: originMetres, reportedAt: now.addingTimeInterval(-10))]
        }
        return Departure.resolve([trip], live: live, freshness: Freshness(live, now: now), isToday: true).first
    }
}

/// The automatic ride's watch (TT-242) on the On board tests' train, Union to Clarkson at 11:17 AM on the synthetic track,
/// with a clock in seconds after L, the shared fake location, the app's ride engine and fakes for everything else. The
/// watch looks only when a test calls `look()` (or `play`).
@MainActor
final class WatchRig {
    let plan: RidePlan
    let clock: TestClock
    let location = FakeLocation(authorized: true)
    let engine: RideEngine
    let positions = FakeTripPositions()
    let rivals = FakeRivalTrains()
    let departures = FakeDepartures()
    let holder = FakeHoldReporter()
    let store: AutoRideStore
    let departure: Date
    let ride = OnBoardFixtures.ride
    let route = Route(
        from: Station(id: "UN", name: "Union Station GO"), to: Station(id: "CL", name: "Clarkson GO"),
        line: Line(id: "LW", name: "Lakeshore West", colorHex: nil)
    )
    var declined: Set<TripKey> = []
    var testing = false
    var active = true
    private(set) var replans = 0
    private(set) var watch: AutoRideWatch!

    /// `at`: the clock, in seconds after L. `defaults`: where the watch keeps its train (relaunch tests share one);
    /// `rideDefaults`: the engine's.
    init(
        at seconds: Double = -300, defaults: UserDefaults? = .ephemeral(), rideDefaults: UserDefaults? = nil,
        live: Bool = true
    ) throws {
        plan = try OnBoardFixtures.plan()
        departure = AutoRideFixtures.departure(plan)
        clock = TestClock(now: departure.addingTimeInterval(seconds))
        store = AutoRideStore(defaults: defaults)
        engine = RideEngine(
            data: FakeRideData(plan: plan), location: location, clock: clock, defaults: rideDefaults, tickInterval: nil
        )
        watch = AutoRideWatch(
            ride: engine, location: location, departures: departures, positions: positions, rivals: rivals,
            holding: holder, clock: clock, store: store, live: live, lookInterval: nil,
            replan: { [weak self] in self?.replans += 1 },
            isDeclined: { [weak self] in self?.declined.contains($0) ?? false },
            isTesting: { [weak self] in self?.testing ?? false },
            isActive: { [weak self] in self?.active ?? true },
            reportsStationary: true
        )
    }

    var trip: Trip {
        Trip(
            key: ride.tripKey, scheduledDeparture: departure, scheduledArrival: plan.stops[plan.stops.count - 1].arrival,
            platform: .pending, tags: []
        )
    }

    var candidate: AutoRideWatch.Candidate {
        AutoRideWatch.Candidate(route: route, trip: trip, departure: departure, arrival: trip.scheduledArrival)
    }

    func time(_ seconds: Double) -> Date { departure.addingTimeInterval(seconds) }
    func at(_ seconds: Double) { clock.set(time(seconds)) }

    /// A fix `along` metres past Union.
    func phone(along: Double, north: Double = 0, stationary: Bool = false) {
        location.send(LocationFix(
            coordinate: AutoRideFixtures.point(plan, along: along, north: north), horizontalAccuracy: 8, isStationary: stationary
        ))
    }

    /// GO's position of the train, reported at `seconds`.
    func train(reported seconds: Double, along: Double) async {
        let position = TrainPosition(coordinate: AutoRideFixtures.point(plan, along: along), reportedAt: time(seconds))
        await positions.set(position, for: ride.tripId)
    }

    /// Arms the watch at the clock's moment and lets its first look run.
    func arm() async {
        await watch.consider([candidate])
        await settle()
    }

    /// Plays the seconds `from` to `to`: a fix each second where `phone` gives one (by default a phone on the train, seen
    /// only once out of Union's shed), GO's position every 30 s (reported on the half minute after L, readable 40 s later)
    /// where `train` gives one, and a look every 15 s. Stops once the watch watches nothing.
    func play(
        from: Int, to: Int,
        phone: (Double) -> (along: Double, stationary: Bool)? = { s in
            let along = AutoRideFixtures.boarding(s)
            return along >= 300 ? (along, false) : nil
        },
        train: ((Double) -> Double?)? = { AutoRideFixtures.boarding($0) }
    ) async {
        for second in from...to {
            let s = Double(second)
            at(s)
            if let fix = phone(s) { self.phone(along: fix.along, stationary: fix.stationary) }
            let reported = s - 40
            if let train, reported >= -600, Int(reported) % 30 == 0, let along = train(reported) {
                await self.train(reported: reported, along: along)
            }
            if second % 15 == 0 { await watch.look() }
            await settle()
            if watch.watched == nil { return }
        }
    }

    /// Lets the tasks the watch started run (a start, a report sent once).
    func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }

    /// Waits up to 2 s for `condition`.
    func eventually(_ condition: () -> Bool) async {
        for _ in 0..<400 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}
