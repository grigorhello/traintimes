import Foundation

/// One ride on one train (TT-171): the trip, its service date and the stretch the rider rides, from the station they got
/// on at to their stop. Saved on device while it lasts, so it survives a relaunch.
struct Ride: Codable, Hashable, Sendable {
    let tripId: String
    /// The GTFS service date, 20261127.
    let serviceDate: Int
    let originId: String
    let destinationId: String

    init(trip: TripKey, from origin: String, to destination: String) {
        tripId = trip.tripId
        serviceDate = trip.serviceDay.dateKey
        originId = origin
        destinationId = destination
    }

    var tripKey: TripKey { TripKey(serviceDay: ServiceDay(dateKey: serviceDate), tripId: tripId) }
}

/// What the ride engine needs from the schedule: the stops from the origin to your stop with their scheduled times and,
/// when the feed has the trip's track, where each is along it.
struct RidePlan: Sendable, Equatable {
    struct Stop: Sendable, Equatable {
        let station: Station
        let arrival: Date
        let departure: Date
    }

    /// The trip's track and each stop's distance along it, in the order of `stops`.
    struct Track: Sendable, Equatable {
        let shape: TrackShape
        let stopDistances: [Double]
    }

    /// The origin first, your stop last; two at least.
    let stops: [Stop]
    /// Nil when the feed gives the trip no track, or a stop no place: the ride then runs on the timetable alone.
    let track: Track?
}

/// The live word on a trip from GO's TripUpdates feed (D36), as the ride uses it.
struct RideStatus: Sendable, Equatable {
    /// Seconds late at your stop, or at the last stop before it with an estimate; nil with none.
    var delay: TimeInterval?
    var isCancelled = false

    static let none = RideStatus()
}

/// The schedule side of a ride: the GO GTFS feed in the app (`GTFSScheduleRepository`), fakes in tests.
protocol RideDataProviding: Sendable {
    /// The ride's stops and track; nil when the trip does not run that day between those stations.
    func ridePlan(for ride: Ride) async throws -> RidePlan?
    /// The trip's delay and cancellation from the live feed; `.none` without one.
    func rideStatus(for ride: Ride) async -> RideStatus
}

/// Where the train feed last placed a train (GTFS-realtime VehiclePositions through the alert server, TT-179).
struct TrainPosition: Sendable, Equatable {
    let coordinate: GeoPoint
    let reportedAt: Date
}

/// The train feed's positions, the ride's second source when the phone has no fix (Live-Spec). A protocol only until
/// TT-179 adds the server's `GET /trains`.
protocol TrainPositionProviding: Sendable {
    func position(of trip: TripKey) async -> TrainPosition?
}

/// One fix from the phone, as the ride uses it.
struct LocationFix: Sendable, Equatable {
    let coordinate: GeoPoint
    /// Metres; a negative value means the fix is not valid.
    let horizontalAccuracy: Double
    /// The phone has stopped moving, so iOS pauses its updates until it moves again: the last fix still holds.
    var isStationary = false
}

/// The phone's location during a ride (TT-171): When In Use permission, asked only when a ride starts, and updates with
/// the background session while it lasts. `SystemLocationProvider` in the app, a fake in tests.
@MainActor
protocol LocationProviding: AnyObject {
    /// When In Use or Always is allowed. Reading it never asks.
    var isAuthorized: Bool { get }
    /// Shows the iOS When In Use prompt if the rider has not answered it yet; true when location is allowed.
    func requestWhenInUse() async -> Bool
    /// Starts the ride's updates, about one a second, which keep coming in the background until `stopUpdates()`.
    func startUpdates(_ onFix: @escaping @MainActor @Sendable (LocationFix) -> Void)
    func stopUpdates()
}
