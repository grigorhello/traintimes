import Foundation

/// The hero card at the top of Trip details for every train that has not left (TT-205, D93; TT-207, D96). Counting down:
/// "5:13 PM departs in" over the minutes to the expected departure. A train that does not count down (not the next one, no
/// alert window): "Departs at" over the expected clock time. Boarding (TT-233, D114, `BoardingRule`): while the train stands
/// at the rider's station with its platform posted, every train's line reads "5:58 PM boarding now" and the card lights up;
/// with no position to go by, a counting train reads "boarding now" in its last 2 min, as before (D69). Past its time and
/// still there, the number gives way to "Departing". "Platform" and the pill at the right, the Express bolt beside the
/// label, "3 min late" under the number only when late. Every time is already formatted by the one formatter (D17).
struct DepartureHero: Equatable {
    /// "5:13 PM departs in", "5:16 PM boarding now", or "Departs at".
    let line: String
    /// "5:13 PM": the expected departure, in ink, or delay-ink while late (in `line`, or as `number`).
    let time: String
    /// The big number: "12 min" ("5 h 23 min" from an hour, TT-246) to the expected departure while counting down,
    /// "Departing" once its time has come and it still stands at the station, else the expected clock time.
    let number: String
    /// The number counts down; false shows the expected clock time ("Departs at" over it, unless the train is boarding).
    let showsCountdown: Bool
    /// "3 min late" while the train runs late (from 3 min, D12); nil otherwise.
    let late: String?
    /// The posted platform, "7"; nil shows the dash pill.
    let platform: String?
    /// The dash pulses while a platform may be posted any minute (fresh live data from a feed that posts them, D55).
    let pillPulses: Bool
    /// Boarding at the platform (TT-233, D114): the train stands at the rider's station with its platform posted. The
    /// card's accent outline and tint, the line in the accent, the pill filled.
    let isBoarding: Bool
    /// "Boarding now" by the clock (D69): the last 2 min of a counting train that no position places. The number in the
    /// accent and nothing else, as before TT-233: never the Boarding look on a guess.
    let boardsByClock: Bool
    /// The stopping-pattern rule (D35): the bolt beside "Platform".
    let isExpress: Bool

    /// The alerted train's window (TT-177): nil once the train has left, so the sheet goes back to the trip.
    init?(_ live: LiveDeparture, now: Date, pillPulses: Bool, formatter: some TimeFormatting) {
        guard live.phase != .departed else { return nil }
        self.init(live.departure, now: now, showsCountdown: true, pillPulses: pillPulses, formatter: formatter)
    }

    /// Any train that has not left (TT-207): nil once it has (`BoardingRule`: it moved off, the feed dropped the station, or
    /// its time came with no position to go by), or when it does not run (cancelled, stop skipped).
    init?(_ departure: Departure, now: Date, showsCountdown: Bool, pillPulses: Bool, formatter: some TimeFormatting) {
        let phase = BoardingRule.phase(of: departure, now: now)
        guard departure.isUsable, !phase.isDeparted else { return nil }
        let untilDeparture = departure.departureTime.timeIntervalSince(now)
        let time = formatter.time(departure.departureTime)
        let isBoarding = phase == .boarding
        // Its time has come and it has not left, so a position places it at the station: no clock time is left to show
        // and no minute to count, on any train.
        let isDeparting = untilDeparture <= 0
        let counts = showsCountdown || isDeparting
        // With a position nothing is guessed from the clock, as in the train's Live Activity (`LiveDeparture`).
        let boardsByClock = !isBoarding && counts && untilDeparture <= LiveDeparture.boardingLead
            && !BoardingRule.hasSighting(of: departure, now: now)
        if isBoarding || boardsByClock {
            line = String(format: String(localized: "depart.boardingLine"), time)
        } else if counts {
            line = String(format: String(localized: "depart.line"), time)
        } else {
            line = String(localized: "depart.atLine")
        }
        if isDeparting {
            number = String(localized: "schedule.departing")
        } else if counts {
            number = TimeFormatter.duration(minutes: max(1, Int(untilDeparture / 60)))
        } else {
            number = time
        }
        self.time = time
        self.showsCountdown = counts
        late = if case .delayed(let minutes, _) = departure.status {
            String(format: String(localized: "onboard.late"), TimeFormatter.duration(minutes: minutes))
        } else {
            nil
        }
        platform = if case .published(let name) = departure.trip.platform { name } else { nil }
        self.pillPulses = pillPulses
        self.isBoarding = isBoarding
        self.boardsByClock = boardsByClock
        isExpress = departure.trip.tags.contains(.express)
    }

    /// The minutes while counting down ("Departing" past its time); nil when the number is a clock time.
    var countdown: String? { showsCountdown ? number : nil }

    var isLate: Bool { late != nil }
}
