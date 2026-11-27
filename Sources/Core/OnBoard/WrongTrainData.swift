import Foundation

// What the wrong train check reads (TT-251, D127): the trains leaving the rider's station, a trip by id, the stops a trip
// still has ahead in the live feed, and the last timed positions of every train. Fixture runs, previews and the demos have
// none of these, so no check runs there.

/// A train the rider may have taken by mistake: a rail trip leaving the rider's station on the day that does not end there,
/// with its track (`GTFSTimetable.candidates(leaving:on:)`). The rider's own train is left out by `WrongTrainRule`.
struct WrongTrainCandidate: Sendable, Equatable {
    let trip: TripKey
    let lineId: String
    /// Its scheduled departure from the station.
    let departure: Date
    let shape: TrackShape
    /// The station's distance along `shape`, placed as `GTFSTimetable.ridePlan(for:)` places a ride's first stop.
    let originAlong: Double
    /// The stations it calls at after the station, in order; one at least.
    let stopsAfter: [String]
}

/// A trip by id from the timetable (`GTFSTimetable.trip(id:on:)`): its stops in calling order with their scheduled times,
/// its line, and its track over all of its stops with each stop placed on it, nil where the feed has no track or a stop no
/// place.
struct TimetableTrip: Sendable, Equatable {
    struct Stop: Sendable, Equatable {
        let station: Station
        let arrival: Date
        let departure: Date
    }

    let key: TripKey
    let lineId: String
    let stops: [Stop]
    let track: RidePlan.Track?
}

/// The stops a trip still has ahead in GO's TripUpdates feed (D89: GO lists every stop still ahead and drops each one once
/// the train has left it), from `LiveStopsProviding`.
struct LiveStopsAhead: Sendable, Equatable {
    struct Stop: Sendable, Equatable {
        let id: String
        /// The feed's expected time there (departure, else arrival); nil where it gives none.
        let time: Date?
    }

    /// The stops listed, in calling order; skipped ones are left out.
    var stops: [Stop]
    /// The stops the feed says the train skips.
    var skipped: Set<String> = []
    var isCancelled = false
    /// The feed is under 3 min old (`Freshness`).
    var isFresh: Bool

    func lists(_ station: String) -> Bool { stops.contains { $0.id == station } }
}

/// The timetable's side of the check: `GTFSScheduleRepository` in the app.
protocol WrongTrainTimetable: Sendable {
    /// Every rail trip with a track leaving `station` on `day` that does not end there.
    func candidates(leaving station: String, on day: ServiceDay) async -> [WrongTrainCandidate]
    func trip(_ key: TripKey) async -> TimetableTrip?
    /// The stations of line `lineId` with their places (`GONetwork`'s order, the timetable's places).
    func stations(onLine lineId: String) async -> [Station]
}

/// The live feed's word on a trip's stops ahead: `GTFSScheduleRepository` in the app.
protocol LiveStopsProviding: Sendable {
    /// Nil with no feed, or when the feed has no update for the trip.
    func stopsAhead(of trip: TripKey) async -> LiveStopsAhead?
}

/// One of GO's positions with when the app read it: its freshness is the read time minus the vehicle's time.
struct ReadPosition: Sendable, Equatable {
    let position: TrainPosition
    let readAt: Date
}

/// Every train's last positions on a service day (`RelayTrainPositions`).
struct TrainPositionHistory: Sendable, Equatable {
    /// The last `RelayTrainPositions.historyCount` positions with the vehicle's own time, per trip id, oldest first.
    var timed: [String: [ReadPosition]] = [:]
    /// The latest position of any kind, per trip id.
    var latest: [String: ReadPosition] = [:]
}

/// The train feed's history (TT-251), beside `TrainPositionProviding`'s one position.
protocol TrainPositionHistoryProviding: Sendable {
    /// `fast`: from a copy of GO's feed at most 15 s old, reused for 10 s (`/v1/trains?fresh=15`), while the phone moves.
    func positions(on day: ServiceDay, fast: Bool) async -> TrainPositionHistory
}
