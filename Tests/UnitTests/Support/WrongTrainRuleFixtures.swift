import Foundation
import XCTest
@testable import TrainTimes

/// The wrong train rule's world (TT-251, D127): straight tracks along one latitude, distances in metres east of the rider's
/// station O. T runs east from 16 km west of O to 16 km east of it and the rider rides O to D (8 km east); W1 is the station
/// behind O on T's line. Fri Nov 27, L at 5:30 PM.
enum WrongWorld {
    static let friday = OnBoardFixtures.friday
    static let latitude = 43.60
    static let longitude = -79.60
    private static let metresPerDegree = 111_195.08

    /// The point `x` metres east of O and `north` metres north of its line.
    static func at(_ x: Double, north: Double = 0) -> GeoPoint {
        GeoPoint(
            latitude: latitude + north / metresPerDegree,
            longitude: longitude + x / (metresPerDegree * cos(latitude * .pi / 180))
        )
    }

    /// T's track, eastbound through O: O is 16 km along it.
    static let east = TrackShape(points: [at(-16_000), at(16_000)])
    /// The other way through O: O is 16 km along it.
    static let west = TrackShape(points: [at(16_000), at(-16_000)])
    /// Eastbound from O itself, as a train leaving Union: O is at its start.
    static let fromOrigin = TrackShape(points: [at(0), at(16_000)])
    /// Another line: T's track to 800 m past O, then north.
    static let fork = TrackShape(points: [at(-16_000), at(800), at(800, north: 8_000)])

    static let departure = friday.date(hour: 17, minute: 30)

    static func station(_ id: String, x: Double, north: Double = 0) -> Station {
        Station(id: id, name: id, place: at(x, north: north))
    }

    /// T's line's stations, west to east.
    static let line = [
        station("W2", x: -8_000), station("W1", x: -4_000), station("O", x: 0), station("E1", x: 4_000), station("D", x: 8_000),
        station("E3", x: 12_000),
    ]

    /// T's plan from `origin` (O, or UN for the covered station at the same place) to D, on `shape`.
    static func plan(origin: String = "O", shape: TrackShape = east) -> RidePlan {
        let places = [at(0), at(4_000), at(8_000)]
        let stops = [(origin, 0.0), ("E1", 240.0), ("D", 480.0)].map { id, offset in
            RidePlan.Stop(
                station: Station(id: id, name: id),
                arrival: departure.addingTimeInterval(offset), departure: departure.addingTimeInterval(offset)
            )
        }
        return RidePlan(stops: stops, track: RidePlan.Track(shape: shape, stopDistances: shape.distances(of: places)))
    }

    static func ride(origin: String = "O") -> Ride {
        Ride(trip: TripKey(serviceDay: friday, tripId: "T"), from: origin, to: "D")
    }

    /// A train leaving O `after` seconds after L on `shape`, calling at `stops` after O.
    static func candidate(_ id: String, after: TimeInterval, shape: TrackShape, stops: [String]) -> WrongTrainCandidate {
        WrongTrainCandidate(
            trip: TripKey(serviceDay: friday, tripId: id), lineId: "LW", departure: departure.addingTimeInterval(after),
            shape: shape, originAlong: shape.distances(of: [at(0)])[0], stopsAfter: stops
        )
    }

    /// The westbound train: back along T's line, W1 next.
    static func westbound(_ id: String = "WEST", after: TimeInterval = -300) -> WrongTrainCandidate {
        candidate(id, after: after, shape: west, stops: ["W1", "W2"])
    }

    /// The express: T's track, not stopping at E1 or D.
    static func express(_ id: String = "EXPRESS", after: TimeInterval = -120, shape: TrackShape = east) -> WrongTrainCandidate {
        candidate(id, after: after, shape: shape, stops: ["E3"])
    }

    /// Another line, parting from T's track 800 m past O.
    static func otherLine(_ id: String = "OTHER", after: TimeInterval = 60) -> WrongTrainCandidate {
        candidate(id, after: after, shape: fork, stops: ["N1"])
    }

    /// Metres from the start, `seconds` after `start`: standing, then 0.5 m/s² up to 25 m/s.
    static func moving(_ seconds: Double, from start: Double) -> Double {
        let t = seconds - start
        guard t > 0 else { return 0 }
        return t <= 50 ? 0.25 * t * t : 625 + 25 * (t - 50)
    }
}

/// The wrong train rule with a clock in seconds after L.
struct WrongRig {
    var rule: WrongTrainRule
    let plan: RidePlan
    var candidates: [String: WrongTrainCandidate] = [:]
    var departure = WrongWorld.departure

    init(origin: String = "O", tie: WrongTrainRule.Tie = .alert, shape: TrackShape = WrongWorld.east, candidates: [WrongTrainCandidate]) throws {
        plan = WrongWorld.plan(origin: origin, shape: shape)
        rule = try XCTUnwrap(WrongTrainRule(
            plan: plan, ride: WrongWorld.ride(origin: origin), tie: tie, lineStations: WrongWorld.line, reportsStationary: true
        ))
        rule.setCandidates(candidates)
        for candidate in candidates { self.candidates[candidate.trip.tripId] = candidate }
    }

    func time(_ seconds: Double) -> Date { WrongWorld.departure.addingTimeInterval(seconds) }

    /// The point `metres` from O along trip `id`'s track (T's for "T"), `north` metres north of it.
    func point(_ id: String, _ metres: Double, north: Double = 0) -> GeoPoint {
        let shape: TrackShape, along: Double
        if let candidate = candidates[id] {
            shape = candidate.shape
            along = candidate.originAlong
        } else {
            shape = plan.track!.shape
            along = plan.track!.stopDistances[0]
        }
        var point = shape.point(at: along + metres)
        point.latitude += north / 111_195.08
        return point
    }

    mutating func phone(_ seconds: Double, at point: GeoPoint, accuracy: Double = 8, stationary: Bool = false) {
        rule.observe(LocationFix(coordinate: point, horizontalAccuracy: accuracy, isStationary: stationary, age: 0), at: time(seconds))
    }

    /// GO's position of trip `id` reported at `seconds`, read `lag` later.
    mutating func train(_ id: String, _ seconds: Double, at point: GeoPoint, lag: Double = 40, timed: Bool = true) {
        rule.observe(TrainPosition(coordinate: point, reportedAt: time(seconds), hasVehicleTime: timed), of: id, readAt: time(seconds + lag))
    }

    /// The live feed's stops ahead for trip `id`.
    mutating func stops(_ id: String, _ list: [String], fresh: Bool = true, cancelled: Bool = false, skipped: Set<String> = []) {
        let stops = list.enumerated().map { index, id in
            LiveStopsAhead.Stop(id: id, time: WrongWorld.departure.addingTimeInterval(Double(index + 1) * 300))
        }
        rule.setStops(LiveStopsAhead(stops: stops, skipped: skipped, isCancelled: cancelled, isFresh: fresh), of: id)
    }

    func verdict(_ seconds: Double) -> WrongTrainRule.Verdict {
        rule.verdict(at: WrongTrainRule.Moment(now: time(seconds), departure: departure))
    }

    /// Plays the seconds `from` to `to`: a fix each second where `phone` gives one, each train's position every 30 s
    /// (reported on the half minute after L, read 40 s later, or `lag`) where `trains` gives one, and a verdict each second.
    /// Returns the first verdict `stopAt` accepts, and its second.
    mutating func run(
        from: Int, to: Int,
        phone: (Double) -> GeoPoint?,
        trains: [String: (Double) -> GeoPoint?] = [:],
        lag: Double = 40,
        timed: Bool = true,
        accuracy: (Double) -> Double = { _ in 8 },
        stationary: (Double) -> Bool = { _ in false },
        stopAt: (WrongTrainRule.Verdict) -> Bool = { if case .wrong = $0 { true } else { false } }
    ) -> (verdict: WrongTrainRule.Verdict, second: Int)? {
        for second in from...to {
            let s = Double(second)
            if let point = phone(s) { self.phone(s, at: point, accuracy: accuracy(s), stationary: stationary(s)) }
            let reported = s - lag
            if Int(reported) % 30 == 0 {
                for (id, place) in trains.sorted(by: { $0.key < $1.key }) {
                    if let point = place(reported) { train(id, reported, at: point, lag: lag, timed: timed) }
                }
            }
            let verdict = verdict(s)
            if stopAt(verdict) { return (verdict, second) }
        }
        return nil
    }
}
