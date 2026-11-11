import Foundation

/// The trains the rider has an alert on, between a route's stations on the train's day. The watched-trip strip on Schedule
/// (TT-144) and Trip details (its alert button and the Live bar's bell, TT-163/TT-172) read it; the alert rules provide it
/// from their one lookup, the alert that covers the train (TT-189, D70), so a repeating alert counts on each of its days.
@MainActor
protocol WatchedTripsProviding: AnyObject {
    /// An alert covers the train, is switched on and can reach the rider: the filled bell, and the watched-trip strip once
    /// the train has left.
    func isWatched(_ trip: Trip, on route: Route) -> Bool
    /// An alert covers the train and is switched on, whatever its saved state: Trip details' "Manage alert" and its bell.
    func isAlerted(_ trip: Trip, on route: Route) -> Bool
}

/// No alerts: nothing is watched.
final class NoWatchedTrips: WatchedTripsProviding {
    func isWatched(_ trip: Trip, on route: Route) -> Bool { false }
    func isAlerted(_ trip: Trip, on route: Route) -> Bool { false }
}
