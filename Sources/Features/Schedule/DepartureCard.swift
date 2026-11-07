import Foundation

/// What one timeline card shows (TT-113), with every time already formatted by the one formatter (D17).
struct DepartureCard: Hashable, Identifiable {
    let id: TripKey
    /// The next usable train: 34 pt time, solid marker and pill, "in N min", and its platform under the arrival.
    let isNext: Bool
    /// "7:32 AM": the expected departure, else the scheduled one.
    let time: String
    /// The rail pill: "7:32".
    let pillTime: String
    /// "Scheduled arrival" or "Est. arrival" (D15).
    let arrivalLabel: String
    let arrivalTime: String
    let status: TripStatus
    /// Next train only: "in 11 min", or "Departing" under 1 min.
    let relativeTime: String?
    /// "Platform 2" or "Platform pending".
    let platform: String
    /// Verified tags only (D21).
    let tags: [TrainTag]

    init(_ departure: Departure, isNext: Bool, now: Date, formatter: some TimeFormatting) {
        id = departure.id
        self.isNext = isNext
        time = formatter.time(departure.departureTime)
        pillTime = formatter.railTime(departure.departureTime)
        if let expected = departure.expectedArrival {
            arrivalLabel = String(localized: "schedule.est_arrival")
            arrivalTime = formatter.time(expected)
        } else {
            arrivalLabel = String(localized: "schedule.scheduled_arrival")
            arrivalTime = formatter.time(departure.trip.scheduledArrival)
        }
        status = TripStatus(departure.status, formatter: formatter)
        relativeTime = isNext ? formatter.relative(until: departure.departureTime, now: now) : nil
        platform = switch departure.trip.platform {
        case .published(let name): String(format: String(localized: "schedule.platform"), name)
        case .pending: String(localized: "schedule.platform_pending")
        }
        tags = departure.trip.tags
    }
}

extension TripStatus {
    /// The badge for a resolved status (D12).
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
