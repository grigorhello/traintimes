import Foundation

/// One look at where the phone is, for Automatic direction (TT-234, D116): a place, how far off it may be and how old it
/// is. It is compared with the route's two stations on the phone and then dropped: nothing of it is kept or sent.
struct DirectionReading: Equatable, Sendable {
    let place: GeoPoint
    /// The reading's accuracy radius, in metres.
    let radius: Double
    /// Seconds since the phone took it.
    let age: TimeInterval
}

/// Automatic direction's rule (TT-234, D116): which of the route's two stations the rider is at, from one reading, and
/// whether the route may turn by itself or only ask. Pure: no location code, no clock of its own, no stored values.
enum DirectionRule {
    /// The other station must be at least this many times as far as the closer one.
    static let ratio = 1.5
    /// The closer station is within this, in metres, unless the reading is on its outer side.
    static let reach: Double = 15_000
    /// An old reading may have moved this fast since, metres a second (a GO train's top speed, about 150 km/h).
    static let speed: Double = 42
    /// A reading within this of the track, in metres, may be on a train.
    static let trackReach: Double = 300
    /// … when it is also more than this before the station it names, in metres along the track.
    static let trackLead: Double = 1_000
    /// Back in the app, an answer in this time turns the route; a later one asks.
    static let quick: Duration = .seconds(1)
    /// The look gives up after this.
    static let limit: Duration = .seconds(10)
    /// A route chosen by hand is kept until the app has been out of view for more than this.
    static let handHold: TimeInterval = 10 * 60
    /// After Undo the route is not turned between those two stations for this long.
    static let undoHold: TimeInterval = 60 * 60
    /// A ride that ended at your stop turns the route for this long after it.
    static let proofLasts: TimeInterval = 60 * 60
    /// "Now from …" shows on this many of the app's turns; later turns are quiet, unless Reduce Motion is on (TT-236).
    static let capsuleTurns = 8

    /// The route's two stations with their places.
    struct Ends: Equatable, Sendable {
        let fromId: String
        let from: GeoPoint
        let toId: String
        let to: GeoPoint
    }

    /// The track between the two stations, and how far along it each one is, by station id.
    struct Track: Equatable, Sendable {
        let shape: TrackShape
        let along: [String: Double]
    }

    /// What one reading says.
    enum Verdict: Equatable, Sendable {
        /// From is already the closer station: nothing to do, and nothing is said.
        case stays
        /// The To station is the closer one: the route should leave from it.
        case turns
        /// The To station is the closer one, but the reading is on the track well before it: maybe on the train, so
        /// the route only asks.
        case maybeOnTrain
        /// In between the two stations or far from both, wherever in its circle the phone is: nothing to do, and the
        /// look ends.
        case nowhere
        /// Too wide a circle to tell: the look waits for the next reading.
        case skipped
    }

    /// Why a look ended with nothing, for Settings › Testing › Last look.
    enum Reason: String, Equatable, Sendable {
        case alreadyCloser, inBetween, noReading, covered, noPlaces, left, off, riding, chosenByHand, chosenByLink, undone
        case noRoute, restarted, rideProof
    }

    /// What a look did.
    enum Outcome: Equatable, Sendable {
        case turn
        case ask
        case nothing(Reason)
    }

    /// Which end the reading is at. The closer station is the answer when the other is at least 1.5 times as far and the
    /// closer is within 15 km, or the reading is on its outer side (farther from the other station than the two are
    /// apart). The reading's circle grows by 42 m for each second of its age, and it counts only when the whole circle
    /// gives one answer: a station when the test passes with the radius added to the closer distance and taken off the
    /// farther; nowhere (in between, or far from both) when it fails even with the radius taken off the closer and added
    /// to the farther; otherwise the reading is skipped.
    static func verdict(ends: Ends, reading: DirectionReading, track: Track?) -> Verdict {
        let radius = max(0, reading.radius) + max(0, reading.age) * speed
        let toFrom = TrackShape.distance(reading.place, ends.from)
        let toTo = TrackShape.distance(reading.place, ends.to)
        let apart = TrackShape.distance(ends.from, ends.to)
        guard names(near: min(toFrom, toTo) + radius, far: max(0, max(toFrom, toTo) - radius), apart: apart) else {
            let atBest = names(near: max(0, min(toFrom, toTo) - radius), far: max(toFrom, toTo) + radius, apart: apart)
            return atBest ? .skipped : .nowhere
        }
        guard toTo < toFrom else { return .stays }
        // Within 300 m of the track and more than 1 km before the station, on the other station's side: maybe on the train.
        if let track, let station = track.along[ends.toId], let other = track.along[ends.fromId] {
            let spot = track.shape.project(reading.place)
            let lead = other >= station ? spot.along - station : station - spot.along
            if spot.off <= trackReach, lead > trackLead { return .maybeOnTrain }
        }
        return .turns
    }

    /// The test itself: the closer station is named when the other is at least 1.5 times as far and the closer is within
    /// 15 km, or the place is on its outer side.
    private static func names(near: Double, far: Double, apart: Double) -> Bool {
        far >= ratio * near && (near <= reach || far > apart)
    }

    /// What the look does with a verdict: the route turns by itself only while `mayTurn` (the answer came before the
    /// trains could be read); later, or maybe on the train, it asks. Nil for a reading that is skipped.
    static func outcome(of verdict: Verdict, mayTurn: Bool) -> Outcome? {
        switch verdict {
        case .skipped: nil
        case .nowhere: .nothing(.inBetween)
        case .stays: .nothing(.alreadyCloser)
        case .turns: mayTurn ? .turn : .ask
        case .maybeOnTrain: .ask
        }
    }
}

extension GTFSTimetable {
    /// The track between two stations for Automatic direction's train check (TT-234, D116): the first direct train from
    /// `day` on, either way (today, else the next day that has one), and the track of its ride between the two. Nil when
    /// no train joins them in `days` days or that trip has no shape: the check is then left out.
    func directionTrack(between first: String, and second: String, from day: ServiceDay, days: Int = 14) -> DirectionRule.Track? {
        for offset in 0..<days {
            let day = day.adding(days: offset)
            for (from, to) in [(first, second), (second, first)] {
                guard let call = directCalls(from: from, to: to, on: day).first else { continue }
                let ride = Ride(trip: TripKey(serviceDay: day, tripId: call.tripId), from: from, to: to)
                guard let track = ridePlan(for: ride)?.track, let start = track.stopDistances.first,
                    let end = track.stopDistances.last
                else { return nil }
                return DirectionRule.Track(shape: track.shape, along: [from: start, to: end])
            }
        }
        return nil
    }
}
