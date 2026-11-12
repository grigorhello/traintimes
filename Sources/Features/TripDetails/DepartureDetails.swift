import Foundation

/// Trip details before departure (TT-177, *Live-Depart-Trip*): the journey card becomes the departure card, with the ride
/// card's anatomy. Every time is already formatted by the one formatter (D17).
struct DepartureDetails: Equatable {
    /// "Departs from Union Station GO", "Boarding now", or "Departed 5:16 PM".
    let label: String
    /// The posted platform, "7"; nil while it is pending, which shows "Platform" and the pill.
    let platform: String?
    /// "Platform 7", or "Platform" beside the pill.
    let platformText: String
    /// The pill pulses while the platform is worth waiting for: fresh live data from a station whose feed posts platforms
    /// (D55). Without such a feed it stays still and the line under it says "Check the board".
    let pillPulses: Bool
    /// "12 min"; nil once the train has left.
    let countdown: String?
    /// The expected departure, under the countdown.
    let countdownTime: String
    /// The line under the platform: "On time · platform soon", "Delayed 3 min · was 5:13 PM", "Doors close at 5:16 PM".
    let detail: String
    /// The part of `detail` in semibold.
    let emphasis: String?
    /// Counting down a late train: the countdown and `emphasis` in delay-ink.
    let isDelayed: Bool
    /// "Boarding now": the card tints soft green.
    let isBoarding: Bool
    /// "Clarkson GO".
    let yourStop: String
    /// The expected arrival at your stop, else the scheduled one.
    let arrival: String
    /// "30 min ride".
    let rideLength: String
    /// "Live · GO train data" with the Live dot, or "Timetable" with the grey one.
    let source: RideDetails.Source
    /// "Updated just now", "Last reported 5:01 PM", "Offline · last updated 4:52 PM"; nil on the timetable alone.
    let freshness: String?
    /// "Live from 30 minutes before departure because this train has an alert. …"
    let footnote: String

    /// "Platform 7" is said once, after the pill was seen: "just announced" for this long.
    static let announcedFor: TimeInterval = 2 * 60

    init(
        _ live: LiveDeparture, origin: String, destination: String, now: Date, freshness: Freshness?, hasPlatformSource: Bool,
        justAnnounced: Bool, formatter: some TimeFormatting
    ) {
        let departure = live.departure
        let trip = departure.trip
        let leaves = formatter.time(live.leaves)
        let arrivalDate = departure.expectedArrival ?? trip.scheduledArrival
        func pair(_ first: String, _ second: String) -> String {
            String(format: String(localized: "onboard.detail"), first, second)
        }
        let punctuality = if let minutes = live.delayMinutes {
            String(format: String(localized: "depart.delayed"), minutes)
        } else {
            live.isLive ? String(localized: "status.on_time") : String(localized: "status.scheduled")
        }

        platform = live.platform
        platformText = live.platform.map { String(format: String(localized: "depart.platform"), $0) }
            ?? String(localized: "depart.platformLabel")
        pillPulses = hasPlatformSource && (freshness?.isLive ?? false)
        countdownTime = leaves
        isBoarding = live.phase == .boarding
        isDelayed = live.phase == .countingDown && live.delayMinutes != nil

        switch live.phase {
        case .countingDown:
            label = String(format: String(localized: "depart.from"), origin)
            countdown = String(format: String(localized: "onboard.minutes"), live.minutes(at: now))
            if live.delayMinutes != nil {
                let was = String(format: String(localized: "depart.was"), formatter.time(trip.scheduledDeparture))
                detail = pair(punctuality, was)
                emphasis = was
            } else {
                let second: String? = if live.platform == nil {
                    pillPulses ? String(localized: "depart.platformSoon") : String(localized: "depart.checkBoard")
                } else {
                    justAnnounced ? String(localized: "depart.justAnnounced") : nil
                }
                detail = second.map { pair(punctuality, $0) } ?? punctuality
                emphasis = second
            }
        case .boarding:
            label = String(localized: "depart.boarding")
            countdown = String(format: String(localized: "onboard.minutes"), live.minutes(at: now))
            detail = String(format: String(localized: "depart.doors"), leaves)
            emphasis = leaves
        case .departed:
            label = String(format: String(localized: "depart.departed"), leaves)
            countdown = nil
            detail = punctuality
            emphasis = nil
        }

        yourStop = destination
        arrival = formatter.time(arrivalDate)
        rideLength = formatter.tripLength(from: live.leaves, to: arrivalDate)
        switch freshness {
        case .live(let updatedAt):
            source = .live(String(localized: "onboard.live.feed"))
            self.freshness = formatter.updated(at: updatedAt, now: now)
        case .stale(let lastReported):
            source = .timetable
            self.freshness = String(format: String(localized: "status.last_reported"), formatter.time(lastReported))
        case .offline(let lastUpdated):
            source = .timetable
            self.freshness = lastUpdated.map { String(format: String(localized: "freshness.offline"), formatter.time($0)) }
                ?? String(localized: "schedule.offline")
        case .scheduledOnly, nil:
            source = .timetable
            self.freshness = nil
        }
        footnote = String(localized: "depart.footnote")
    }
}

/// Schedule's watched-trip strip while an alerted train counts down (TT-177, *Live-Depart*): "Your 5:13 PM train",
/// "Platform 7 · On time", "12 min · departs". A tap opens its Trip details.
struct DepartureStrip: Equatable {
    let key: TripKey
    /// "Your 5:13 PM train": the scheduled departure, which stays the train's name (D9).
    let title: String
    /// "Platform 7"; nil while it is pending.
    let platform: String?
    /// A pending platform's dash pill pulses while it is worth waiting for (D55).
    let pillPulses: Bool
    /// "On time", "Delayed 3 min", "Boarding now", or "Scheduled" on the timetable alone.
    let status: String
    /// The countdown in delay-ink.
    let isDelayed: Bool
    /// "12 min".
    let countdown: String

    init(_ live: LiveDeparture, now: Date, hasPlatformSource: Bool, formatter: some TimeFormatting) {
        key = live.key
        title = String(format: String(localized: "depart.strip"), formatter.time(live.departure.trip.scheduledDeparture))
        platform = live.platform
        pillPulses = hasPlatformSource && live.isLive
        status = if live.phase == .boarding {
            String(localized: "depart.boarding")
        } else if let minutes = live.delayMinutes {
            String(format: String(localized: "depart.delayed"), minutes)
        } else {
            live.isLive ? String(localized: "status.on_time") : String(localized: "status.scheduled")
        }
        isDelayed = live.phase == .countingDown && live.delayMinutes != nil
        countdown = String(format: String(localized: "onboard.minutes"), live.minutes(at: now))
    }
}

extension OnBoard {
    /// Demo trains › Departure (TT-177): the demo's strip at its clock; nil while its train has left.
    func demoDepartureStrip(formatter: some TimeFormatting) -> DepartureStrip? {
        guard let session = departureDemo else { return nil }
        let now = session.now
        guard let departure = session.departure(at: now), let live = LiveDeparture(departure, now: now), live.phase != .departed
        else { return nil }
        return DepartureStrip(live, now: now, hasPlatformSource: true, formatter: formatter)
    }
}
