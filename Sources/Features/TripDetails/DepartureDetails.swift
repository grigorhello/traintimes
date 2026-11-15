import Foundation

/// The hero card at the top of Trip details for every train that has not left (TT-205, D93; TT-207, D96). Counting down:
/// "5:13 PM departs in" over the minutes to the expected departure ("5:16 PM boarding now" in the last 2 min). A train that
/// does not count down (not the next one, no alert window): "Departs at" over the expected clock time. "Platform" and the
/// pill at the right, the Express bolt beside the label, "3 min late" under the number only when late. Every time is
/// already formatted by the one formatter (D17).
struct DepartureHero: Equatable {
    /// "5:13 PM departs in", "5:16 PM boarding now", or "Departs at".
    let line: String
    /// "5:13 PM": the expected departure, in ink, or delay-ink while late (in `line`, or as `number`).
    let time: String
    /// The big number: "12 min" to the expected departure while counting down, else the expected clock time.
    let number: String
    /// The number counts down; false shows "Departs at" over the clock time.
    let showsCountdown: Bool
    /// "3 min late" while the train runs late (from 3 min, D12); nil otherwise.
    let late: String?
    /// The posted platform, "7"; nil shows the dash pill.
    let platform: String?
    /// The dash pulses while a platform may be posted any minute (fresh live data from a feed that posts them, D55).
    let pillPulses: Bool
    /// The last 2 min: the number in the accent.
    let isBoarding: Bool
    /// The stopping-pattern rule (D35): the bolt beside "Platform".
    let isExpress: Bool

    /// The alerted train's window (TT-177): nil once the train has left, so the sheet goes back to the trip.
    init?(_ live: LiveDeparture, now: Date, pillPulses: Bool, formatter: some TimeFormatting) {
        guard live.phase != .departed else { return nil }
        self.init(live.departure, now: now, showsCountdown: true, pillPulses: pillPulses, formatter: formatter)
    }

    /// Any train that has not left (TT-207): nil once it has, or when it does not run (cancelled, stop skipped).
    init?(_ departure: Departure, now: Date, showsCountdown: Bool, pillPulses: Bool, formatter: some TimeFormatting) {
        let untilDeparture = departure.departureTime.timeIntervalSince(now)
        guard departure.isUsable, untilDeparture > 0 else { return nil }
        let time = formatter.time(departure.departureTime)
        let isBoarding = showsCountdown && untilDeparture <= LiveDeparture.boardingLead
        if !showsCountdown {
            line = String(localized: "depart.atLine")
            number = time
        } else {
            let format = if isBoarding { String(localized: "depart.boardingLine") } else { String(localized: "depart.line") }
            line = String(format: format, time)
            number = String(format: String(localized: "onboard.minutes"), max(1, Int(untilDeparture / 60)))
        }
        self.time = time
        self.showsCountdown = showsCountdown
        late = if case .delayed(let minutes, _) = departure.status {
            String(format: String(localized: "onboard.late"), minutes)
        } else {
            nil
        }
        platform = if case .published(let name) = departure.trip.platform { name } else { nil }
        self.pillPulses = pillPulses
        self.isBoarding = isBoarding
        isExpress = departure.trip.tags.contains(.express)
    }

    /// The minutes while counting down; nil when the number is a clock time.
    var countdown: String? { showsCountdown ? number : nil }

    var isLate: Bool { late != nil }
}
