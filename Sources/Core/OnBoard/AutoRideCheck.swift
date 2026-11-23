import Foundation

/// How the automatic ride's last watch ended (TT-242, D120): Settings › Testing › Last check and `auto_ride_checked`. Kept in
/// memory only; never a place.
struct AutoRideCheck: Equatable, Sendable {
    enum Outcome: String, Sendable, Codable {
        /// The ride started by itself.
        case started
        /// The phone stayed at the station or went elsewhere.
        case notOnBoard = "not_on_board"
        /// It could not tell before the question ended (`reason` says why).
        case unsure
        /// Yes, No or "I’m on board" came first.
        case answered
        /// The alert went, location or Precise Location went, or Mock time or a demo came on.
        case stopped
        /// An alerted train in its window that a gate kept from arming.
        case notArmed = "not_armed"
    }

    /// Why the rule could not tell, the first that applies (`AutoRideRule`).
    enum Reason: String, Sendable, Codable {
        /// Less than 5 min to the rider's stop.
        case short
        /// The phone was never seen at the station.
        case noStation = "no_station"
        /// Leaving with the train kept failing on accuracy, gaps or standstills.
        case weakFixes = "weak_fixes"
        /// Fewer than two of GO's positions of the train.
        case noFeed = "no_feed"
        /// Another train on the same track was still beside it.
        case rival
    }

    var outcome: Outcome
    /// On `unsure` only.
    var reason: Reason?
    /// Whole seconds from the train leaving to the outcome; nil when it had not left.
    var secondsAfter: Int?
    /// When the server confirmed the hold of the question's buzz; nil when none was sent or confirmed.
    var holdReachedAt: Date?
}
