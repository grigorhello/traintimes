import Foundation

/// What one timeline card shows (TT-113), with every time already formatted by the one formatter (D17).
struct DepartureCard: Hashable, Identifiable {
    let id: TripKey
    /// The next usable train: 34 pt time, solid marker, "in N min", and its platform under the arrival.
    let isNext: Bool
    /// "7:32 AM": the expected departure, else the scheduled one.
    let time: String
    /// "Arrival" or "Est. arrival" (D15, D49).
    let arrivalLabel: String
    let arrivalTime: String
    let status: TripStatus
    /// Next train only: "in 11 min", or "Departing" under 1 min.
    let relativeTime: String?
    /// "Platform 2" or "Platform pending".
    let platform: String
    /// Verified tags only (D21).
    let tags: [TrainTag]
    /// Delayed train (TT-114): "Scheduled 7:32 AM" under the expected time, so the train keeps its name (D9).
    let scheduledTime: String?
    /// Cancelled or stop skipped (TT-114): red x marker, struck times, no bell, never the lead.
    let isCancelled: Bool
    /// Cancelled card: "Next usable below", when a usable train follows it.
    let note: String?
    /// The train's name, its scheduled departure (D9): "7:32 AM", for the bell's label (TT-141).
    let trainName: String

    /// `isOffline` keeps the grey "Scheduled" badge; with no live status otherwise the badge reads "On time" (D49).
    init(
        _ departure: Departure, isNext: Bool, nextUsableBelow: Bool = false, isOffline: Bool = false, now: Date,
        formatter: some TimeFormatting
    ) {
        id = departure.id
        self.isNext = isNext
        time = formatter.time(departure.departureTime)
        if let expected = departure.expectedArrival {
            arrivalLabel = String(localized: "schedule.est_arrival")
            arrivalTime = formatter.time(expected)
        } else {
            arrivalLabel = String(localized: "schedule.arrival")
            arrivalTime = formatter.time(departure.trip.scheduledArrival)
        }
        status = TripStatus(departure.status, isOffline: isOffline, formatter: formatter)
        relativeTime = isNext ? formatter.relative(until: departure.departureTime, now: now) : nil
        platform = switch departure.trip.platform {
        case .published(let name): String(format: String(localized: "schedule.platform"), name)
        case .pending: String(localized: "schedule.platform_pending")
        }
        tags = departure.trip.tags
        let scheduled = departure.scheduledMarker
        scheduledTime = scheduled.map { String(format: String(localized: "schedule.scheduled_time"), formatter.time($0)) }
        isCancelled = !departure.isUsable
        note = isCancelled && nextUsableBelow ? String(localized: "schedule.next_usable_below") : nil
        trainName = formatter.time(departure.trip.scheduledDeparture)
    }
}

extension TripStatus {
    /// The badge for a resolved status (D12). A train with no live status reads "On time" (D49: the timetable is the
    /// promise, and the status row says when it is stale); only while offline does it stay the grey "Scheduled".
    init(_ status: TrainStatus, isOffline: Bool = false, formatter: some TimeFormatting) {
        self = switch status {
        case .onTime: .onTime
        case .delayed(let minutes, _): .delayed(minutes: minutes)
        case .cancelled: .cancelled
        case .stopSkipped: .stopSkipped
        case .scheduled: isOffline ? .scheduled : .onTime
        case .stale(let lastReported): .lastReported(time: formatter.time(lastReported))
        case .offline: .offline
        }
    }
}
