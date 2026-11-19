import Foundation

/// How far a train stood from the route's origin station when GO's train feed last placed it (TT-233, D114).
struct OriginFix: Hashable, Sendable {
    /// Metres from the origin station's place.
    let metres: Double
    /// When the feed placed the train there.
    let reportedAt: Date
}

/// Boarding at the platform (TT-233, D114): one rule for the Schedule card, Trip details and the Live Activity, and the
/// alert server's port of it (`server/src/activity.ts`).
///
/// - **Boarding** while GO's train feed places the train within 350 m of the rider's station, not more than 2 min ago,
///   and its platform is posted. It stays Boarding past its time while the train stands there.
/// - **Departed** when the origin has dropped out of the trip's TripUpdates (from 1 min before its time), or its
///   position is farther than 350 m once its time has come. In the minute before its time a far position alone is not
///   a departure: a train still rolling in is as far away.
/// - **No fresh position** (none for the trip, older than 2 min, offline, fixtures): the clock, as before. Never
///   Boarding on a guess.
/// - Cancelled trains and skipped stops never board; they follow the clock.
enum BoardingRule {
    /// A train this close to the station's place stands at it (Union's trains stood 75 to 220 m from the stop point).
    static let radius: Double = 350
    /// A position older than this says nothing.
    static let fixMaxAge: TimeInterval = 2 * 60
    /// The feed's word that the train has left counts from this long before its time.
    static let departLead: TimeInterval = 60

    /// What said the train has left (`train_departed`'s `source`).
    enum Source: String, Hashable, Sendable {
        /// Its position is away from the station.
        case moved
        /// The station dropped out of the trip's TripUpdates.
        case feed
        /// Its time came and no position says otherwise.
        case clock
    }

    enum Phase: Hashable, Sendable {
        /// Not at the platform as far as anyone knows, and not left.
        case waiting
        /// Standing at the rider's station with its platform posted.
        case boarding
        case departed(Source)

        var isDeparted: Bool {
            if case .departed = self { true } else { false }
        }

        /// What said so; nil while the train has not left.
        var source: Source? {
            if case .departed(let source) = self { source } else { nil }
        }
    }

    /// The train's phase at `now`, for a train on Today (another day has no fix and reads the clock).
    static func phase(of departure: Departure, now: Date) -> Phase {
        let leaves = departure.departureTime
        let clock: Phase = now >= leaves ? .departed(.clock) : .waiting
        guard departure.isUsable else { return clock }
        if departure.hasLeftOrigin, now >= leaves.addingTimeInterval(-departLead) { return .departed(.feed) }
        guard let fix = departure.originFix, isFresh(fix, now: now) else { return clock }
        if fix.metres <= radius {
            // Never departed while it stands there, whatever the clock says; Boarding only once the platform is posted.
            return departure.hasPostedPlatform ? .boarding : .waiting
        }
        return now >= leaves ? .departed(.moved) : .waiting
    }

    /// The train feed placed the train recently enough to go by: with a sighting nothing is guessed from the clock.
    static func hasSighting(of departure: Departure, now: Date) -> Bool {
        departure.originFix.map { isFresh($0, now: now) } ?? false
    }

    private static func isFresh(_ fix: OriginFix, now: Date) -> Bool {
        now.timeIntervalSince(fix.reportedAt) <= fixMaxAge
    }
}

extension Departure {
    var hasPostedPlatform: Bool {
        if case .published = trip.platform { true } else { false }
    }

    /// The train stands at the rider's station with its platform posted (`BoardingRule`).
    func isBoarding(at now: Date) -> Bool {
        BoardingRule.phase(of: self, now: now) == .boarding
    }

    /// The train has left the rider's station (`BoardingRule`): it moved off, the feed says so, or its time came.
    func hasLeft(at now: Date) -> Bool {
        BoardingRule.phase(of: self, now: now).isDeparted
    }
}
