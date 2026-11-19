import Foundation

/// Before departure (TT-177, D69, Live-Spec "Before departure"): an alerted train goes live 30 min before its expected
/// departure. It counts down, shows the platform once it is posted and a delay as the feed reports it, reads "Boarding now"
/// while it stands at the rider's station, and has left when it moves off (TT-233, D114, `BoardingRule`); with no position
/// to go by, "Boarding now" is the last 2 min and it has left at its time, as before. Once it has left, its Live Activity
/// asks "On board?" until 10 min after its time, or until the train reaches the rider's stop if that is sooner (TT-231,
/// D110). One train at a time: of the alerted trains, the one that leaves first.
struct LiveDeparture: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        /// In its window and neither boarding nor left.
        case countingDown
        /// The train stands at the rider's station with its platform posted, also past its time (TT-233); with no position,
        /// the last 2 min before the expected departure.
        case boarding
        /// The train has left (`BoardingRule`), until 10 min after its expected departure, or to the rider's stop if sooner,
        /// then the window ends: the activity asks "On board?" (TT-231).
        case departed
    }

    /// The window opens this long before the expected departure (no setting for now, Live-Spec).
    static let window: TimeInterval = 30 * 60
    /// "Boarding now" from this long before the expected departure, when no position says where the train is.
    static let boardingLead: TimeInterval = 2 * 60
    /// The question after departure stays this long at most, then the window ends (TT-231, D110; 2 min of "Departed"
    /// before it).
    static let askFor: TimeInterval = 10 * 60

    let departure: Departure
    let phase: Phase

    /// The departure's state at `now`; nil outside its window, and for a train that does not run (cancelled, stop skipped).
    init?(_ departure: Departure, now: Date) {
        guard departure.isUsable else { return nil }
        let untilDeparture = departure.departureTime.timeIntervalSince(now)
        guard untilDeparture <= Self.window, now < Self.endsAt(departure) else { return nil }
        self.departure = departure
        phase = switch BoardingRule.phase(of: departure, now: now) {
        case .departed:
            .departed
        case .boarding:
            .boarding
        case .waiting:
            // With no position to go by the last 2 min read Boarding now, by the clock (D69); with one, only the train
            // standing at the station does.
            !BoardingRule.hasSighting(of: departure, now: now) && untilDeparture <= Self.boardingLead ? .boarding : .countingDown
        }
    }

    var key: TripKey { departure.id }
    /// When the window ends: 10 min after the expected departure, or at the expected arrival at the rider's stop if sooner.
    var endsAt: Date { Self.endsAt(departure) }

    static func endsAt(_ departure: Departure) -> Date {
        let arrival = departure.expectedArrival ?? departure.trip.scheduledArrival
        return min(departure.departureTime.addingTimeInterval(askFor), max(arrival, departure.departureTime))
    }
    /// The expected departure, else the scheduled one.
    var leaves: Date { departure.departureTime }
    /// The posted platform; nil while it is pending.
    var platform: String? {
        if case .published(let name) = departure.trip.platform { name } else { nil }
    }

    /// Minutes late, from the live status (D12: from 3 min); nil on time or without live data.
    var delayMinutes: Int? {
        if case .delayed(let minutes, _) = departure.status { minutes } else { nil }
    }

    /// Live data says the train runs on time or late; without it the times are the timetable's.
    var isLive: Bool {
        switch departure.status {
        case .onTime, .delayed: true
        default: false
        }
    }

    /// Whole minutes until the train leaves, counted as the timeline's cards count them ("in 12 min"), and 1 at least.
    func minutes(at now: Date) -> Int {
        max(1, Int(leaves.timeIntervalSince(now) / 60))
    }

    /// Its time has come and it has not left: it still stands at the station, so the minutes give way to "Departing"
    /// (`schedule.departing`, TT-233).
    func isDeparting(at now: Date) -> Bool {
        phase != .departed && now >= leaves
    }

    /// The live departure among `departures` at `now`: the alerted train in its window that leaves first; nil when none is.
    /// A train that has left (its question, TT-231) gives way to one still to leave, so the next train's countdown is not
    /// held up for 10 min.
    static func earliest(in departures: [Departure], now: Date, isAlerted: (Departure) -> Bool) -> LiveDeparture? {
        departures
            .compactMap { LiveDeparture($0, now: now) }
            .filter { isAlerted($0.departure) }
            .min { ($0.phase == .departed ? 1 : 0, $0.leaves, $0.key.tripId) < ($1.phase == .departed ? 1 : 0, $1.leaves, $1.key.tripId) }
    }
}
