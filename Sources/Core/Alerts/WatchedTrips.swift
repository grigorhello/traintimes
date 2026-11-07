import Foundation

/// The trips the rider has an alert on, by trip identity (D9). The watched-trip strip on Schedule reads it (TT-144);
/// the alert rules from the bell (TT-141) and alert setup (TT-142) provide it.
@MainActor
protocol WatchedTripsProviding: AnyObject {
    func isWatched(_ trip: TripKey) -> Bool
}

/// No alerts: nothing is watched.
final class NoWatchedTrips: WatchedTripsProviding {
    func isWatched(_ trip: TripKey) -> Bool { false }
}
