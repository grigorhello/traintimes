import Foundation

/// Another train leaving the rider's station close to the alerted one (TT-242, D120): `AutoRideRule`'s Y4 waits until the
/// phone is shown to be on the alerted train and not on this one.
struct RivalTrain: Sendable, Equatable {
    let trip: TripKey
    /// When it leaves the station: the live feed's expected departure where it has one, else the timetable's.
    let departure: Date
    /// Its track, and how far along it the station is.
    let shape: TrackShape
    let originAlong: Double
}

/// The trains that could stand beside the alerted one: `GTFSScheduleRepository` in the app; none in fixture runs, the
/// demo and tests that need none.
protocol RivalTrainsProviding: Sendable {
    /// Every other rail trip, any line, leaving `ride`'s origin on its service day within `AutoRideRule.rivalWindow` of
    /// `departure` (live expected departures where the TripUpdates feed has them, else scheduled), that has a track.
    func rivals(of ride: Ride, around departure: Date) async -> [RivalTrain]
}

/// No rivals: fixture runs and the Testing demo.
struct NoRivalTrains: RivalTrainsProviding {
    func rivals(of ride: Ride, around departure: Date) async -> [RivalTrain] { [] }
}
