import Foundation

/// The ambient feels for a train the rider watches, its alert on or its Trip details open, with the app open (TT-215, D100;
/// the haptics spec's rule 6): Warning once when it turns late or is cancelled, Rail joint once when it reaches Boarding
/// now. A train is first only noted, so opening a screen on a train that is already late or boarding plays nothing; a train
/// no longer watched is forgotten.
struct WatchedTrainFeels {
    private struct Mark: Equatable {
        var trouble: Trouble
        var boarding: Bool
    }

    private enum Trouble: Int, Comparable {
        case none, late, cancelled
        static func < (lhs: Trouble, rhs: Trouble) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private var seen: [TripKey: Mark] = [:]

    /// The one moment to play for `departures` at `now`, if any; `isWatched` says which trains count. Warning wins over
    /// Rail joint when both change at once (one haptic at a time).
    mutating func moment(for departures: [Departure], now: Date, isWatched: (Departure) -> Bool) -> HapticMoment? {
        var next: [TripKey: Mark] = [:]
        var moment: HapticMoment?
        for departure in departures where isWatched(departure) {
            let old = seen[departure.id]
            let mark = Self.mark(departure, now: now, old: old)
            next[departure.id] = mark
            guard let old else { continue }
            if mark.trouble > old.trouble {
                moment = .late
            } else if mark.boarding, !old.boarding, moment == nil {
                moment = .boarding
            }
        }
        seen = next
        return moment
    }

    /// Offline, stale or timetable-only says nothing new: the train keeps what live data last said, so coming back online
    /// does not warn again about a train already late.
    private static func mark(_ departure: Departure, now: Date, old: Mark?) -> Mark {
        let trouble: Trouble = switch departure.status {
        case .cancelled: .cancelled
        case .delayed: .late
        case .onTime: .none
        case .stopSkipped, .scheduled, .stale, .offline: old?.trouble ?? .none
        }
        // Once boarding it stays marked: a position that goes stale for a poll and comes back does not play it again (TT-233).
        let boarding = old?.boarding == true || LiveDeparture(departure, now: now)?.phase == .boarding
        return Mark(trouble: trouble, boarding: boarding)
    }
}
