import Foundation

/// What one timeline card shows (TT-113, TT-157), with every time already formatted by the one formatter (D17).
/// Three fixed rows (D50): time and Express bolt; countdown and platform with the trip length; status and arrival.
struct DepartureCard: Hashable, Identifiable {
    let id: TripKey
    /// The next usable train: 34 pt time, solid marker and "in N min".
    let isNext: Bool
    /// "7:32 AM": the expected departure, else the scheduled one.
    let time: String
    /// The estimated arrival when the feed gives one, else the scheduled one; always labelled "Arrival" on the card.
    let arrivalTime: String
    /// "40 min": arrival minus departure of the two times the card shows.
    let tripLength: String
    let status: TripStatus
    /// Next train only: "in 11 min", or "Departing" under 1 min.
    let relativeTime: String?
    /// The platform's pill (TT-199): "2", or the "—" placeholder until GO publishes it (the pill then shows a dash).
    let platformValue: String
    let hasPlatform: Bool
    /// The next train is within 15 min of leaving and still waiting for its platform: the dash pill pulses
    /// (`Departure.awaitsPlatform`, TT-162, D55).
    let awaitsPlatform: Bool
    /// From the stopping-pattern rule (D35); every other card shows the struck bolt.
    let isExpress: Bool
    /// Cancelled or stop skipped (TT-114): red x marker, struck times, no bell, no bolt, never the lead.
    let isCancelled: Bool
    /// Cancelled card: "Next usable below", when a usable train follows it.
    let note: String?
    /// The train's name, its scheduled departure (D9): "7:32 AM", for the bell's label (TT-141).
    let trainName: String

    /// Delayed: the time and arrival are amber (D50).
    var isDelayed: Bool {
        if case .delayed = status { return true }
        return false
    }

    init(
        _ departure: Departure, isNext: Bool, nextUsableBelow: Bool = false, awaitsPlatform: Bool = false, now: Date,
        formatter: some TimeFormatting
    ) {
        id = departure.id
        self.awaitsPlatform = awaitsPlatform
        self.isNext = isNext
        time = formatter.time(departure.departureTime)
        let arrival = departure.expectedArrival ?? departure.trip.scheduledArrival
        arrivalTime = formatter.time(arrival)
        tripLength = formatter.tripLength(from: departure.departureTime, to: arrival)
        // Ring = Scheduled (D50): stale and offline read Scheduled on the card; the status row says Last reported or Offline.
        let resolved = TripStatus(departure.status, formatter: formatter)
        status = resolved.isLive ? resolved : .scheduled
        relativeTime = isNext ? formatter.relative(until: departure.departureTime, now: now) : nil
        let value: String
        switch departure.trip.platform {
        case .published(let name):
            value = name
            hasPlatform = true
        case .pending:
            value = String(localized: "schedule.platform_placeholder")
            hasPlatform = false
        }
        platformValue = value
        isExpress = departure.trip.tags.contains(.express)
        isCancelled = !departure.isUsable
        note = isCancelled && nextUsableBelow ? String(localized: "schedule.next_usable_below") : nil
        trainName = formatter.time(departure.trip.scheduledDeparture)
    }
}

extension TripStatus {
    /// The status for a resolved domain status (D12, D13). A train with no live status reads "Scheduled" with a ring on the
    /// card and on Trip details: On time needs live data (D50, reversing D49's green On time).
    init(_ status: TrainStatus, formatter: some TimeFormatting) {
        self = switch status {
        case .onTime: .onTime
        case .delayed(let minutes, _): .delayed(minutes: minutes)
        case .cancelled: .cancelled
        case .stopSkipped: .stopSkipped
        case .scheduled: .scheduled
        case .stale(let lastReported): .lastReported(time: formatter.time(lastReported))
        case .offline: .offline
        }
    }
}
