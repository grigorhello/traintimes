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

    /// A station the train passes without stopping between two of the ride's stops (TT-232, D111): a disabled row on the
    /// ride screen, a hollow dot on the Live Activity's stop line.
    struct Skipped: Sendable, Equatable {
        let station: Station
        /// The stop in `stops` it comes after.
        let after: Int
        /// How far from that stop to the next one it is, 0 to 1: by distance along the track where the feed places it,
        /// evenly between the two otherwise. The train passes its row when the clock is that far along the stretch.
        let along: Double
    }

    /// The origin first, your stop last; two at least.
    let stops: [Stop]
    /// Nil when the feed gives the trip no track, or a stop no place: the ride then runs on the timetable alone.
    let track: Track?
    /// The stations passed without stopping, in the order the train passes them (`RidePlan.skipped(stops:track:lineId:places:)`);
    /// empty on a train that stops everywhere, and where the line's order is not known.
    var skipped: [Skipped] = []
    /// The Schedule card's express tag (D35) for this trip between the ride's two ends: the bolt by the train.
    var isExpress = false
}

extension RidePlan {
    /// Where the timetable has the train at `time`, in metres along its track: standing at each stop from its arrival to
    /// its departure, at an even speed between them, waiting at the first stop before it leaves and at the last after.
    func scheduledAlong(at time: Date) -> Double {
        guard let distances = track?.stopDistances, let lastDistance = distances.last else { return 0 }
        for index in stops.indices {
            if time < stops[index].arrival {
                guard index > 0 else { return distances[0] }
                let leaves = stops[index - 1].departure
                let span = stops[index].arrival.timeIntervalSince(leaves)
                let fraction = span > 0 ? min(max(time.timeIntervalSince(leaves) / span, 0), 1) : 1
                return distances[index - 1] + (distances[index] - distances[index - 1]) * fraction
            }
            if time <= stops[index].departure { return distances[index] }
        }
        return lastDistance
    }
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
    /// `reportedAt` is the vehicle's own time; false where the feed gave none and the header's time stood in for it
    /// (TT-242, D120): an automatic start (`AutoRideRule` Y3) never counts such a position.
    var hasVehicleTime = true
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
    /// Seconds since iOS measured it: iOS can hand a fix over late, after a pause in the background (TT-220).
    var age: TimeInterval = 0
}

/// The phone's location during a ride (TT-171), and the automatic ride's watch's (TT-242, D120): When In Use permission,
/// and updates with the background session while a ride lasts. Through this protocol When In Use is asked only when a ride
/// starts; the Automatic direction and Automatic ride switches ask it too, and nothing asks at launch (D60 rule 4 as
/// revised by D116 and D120). Automatic direction's one look when the app opens has its own reader, `DirectionLocating`,
/// which never asks by itself. `SystemLocationProvider` in the app (`BackgroundFixes` for a watch armed with the app
/// closed), a fake in tests.
@MainActor
protocol LocationProviding: AnyObject {
    /// When In Use or Always is allowed. Reading it never asks.
    var isAuthorized: Bool { get }
    /// The rider has not answered the When In Use prompt yet, so `requestWhenInUse()` would show it: the first "I'm on
    /// board" shows the app's sheet before it (TT-172). Reading it never asks.
    var canAsk: Bool { get }
    /// Precise Location is on (`accuracyAuthorization == .fullAccuracy`). Reading it never asks. An automatic start needs
    /// it (TT-242, D120).
    var isPrecise: Bool { get }
    /// Shows the iOS When In Use prompt if the rider has not answered it yet; true when location is allowed.
    func requestWhenInUse() async -> Bool
    /// Starts the ride's updates, about one a second, which keep coming in the background until `stopUpdates()`. Called
    /// while updates already run, it only swaps the callback: the same session goes on (the automatic ride's watch hands its
    /// updates over to the ride engine this way, TT-242, D120).
    func startUpdates(_ onFix: @escaping @MainActor @Sendable (LocationFix) -> Void)
    func stopUpdates()
}
