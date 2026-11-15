import Foundation

/// Trip details before departure (TT-205, D93, boards 2 and 4 of the Live view canvas): the hero card over the folded trip,
/// one look whether the train has an alert or "I’m on board" shows. "5:13 PM departs in" over the minutes to the expected
/// departure, "Platform" and the pill at the right, "3 min late" under the minutes only when late; "5:16 PM boarding now"
/// in the last 2 min. Every time is already formatted by the one formatter (D17).
struct DepartureHero: Equatable {
    /// "5:13 PM departs in", "5:16 PM boarding now".
    let line: String
    /// "5:13 PM": the expected departure at the start of `line`, in ink, or delay-ink while late.
    let time: String
    /// "12 min", to the expected departure.
    let countdown: String
    /// "3 min late" while the train runs late (from 3 min, D12); nil otherwise.
    let late: String?
    /// The posted platform, "7"; nil shows the dash pill.
    let platform: String?
    /// The dash pulses while a platform may be posted any minute (fresh live data from a feed that posts them, D55).
    let pillPulses: Bool
    /// The last 2 min: the number in the accent.
    let isBoarding: Bool

    /// Nil once the train has left: the sheet goes back to the trip.
    init?(_ live: LiveDeparture, now: Date, pillPulses: Bool, formatter: some TimeFormatting) {
        guard live.phase != .departed else { return nil }
        let time = formatter.time(live.leaves)
        let isBoarding = live.phase == .boarding
        let format = if isBoarding { String(localized: "depart.boardingLine") } else { String(localized: "depart.line") }
        line = String(format: format, time)
        self.time = time
        countdown = String(format: String(localized: "onboard.minutes"), live.minutes(at: now))
        late = live.delayMinutes.map { String(format: String(localized: "onboard.late"), $0) }
        platform = live.platform
        self.pillPulses = pillPulses
        self.isBoarding = isBoarding
    }

    var isLate: Bool { late != nil }
}
