import Foundation

/// The trips the rider has an alert on, by trip identity (D9). The watched-trip strip on Schedule reads it (TT-144);
/// the alert rules from the bell (TT-141) and alert setup (TT-142) provide it.
@MainActor
protocol WatchedTripsProviding: AnyObject {
    func isWatched(_ trip: TripKey) -> Bool
    /// Before departure (TT-177, D69): the rider set an alert for this train between the route's stations, so it goes live
    /// 30 min before it leaves.
    func isAlerted(_ trip: Trip, on route: Route) -> Bool
}

extension WatchedTripsProviding {
    func isAlerted(_ trip: Trip, on route: Route) -> Bool { isWatched(trip.key) }
}

/// No alerts: nothing is watched.
final class NoWatchedTrips: WatchedTripsProviding {
    func isWatched(_ trip: TripKey) -> Bool { false }
}
