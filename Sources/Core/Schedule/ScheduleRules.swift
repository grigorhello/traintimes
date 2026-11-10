import Foundation

/// The data mode the status row and Trip details' freshness line state (D14).
enum Freshness: Hashable, Sendable {
    case live(updatedAt: Date)
    case scheduledOnly
    case stale(lastReported: Date)
    case offline(lastUpdated: Date?)

    /// Live data older than this is demoted to "Last reported" (Q2: 3 min until tuned against the feed).
    static let threshold: TimeInterval = 3 * 60

    init(_ live: LiveSnapshot, now: Date) {
        if live.isOffline {
            self = .offline(lastUpdated: live.updatedAt)
        } else if let updatedAt = live.updatedAt {
            self = now.timeIntervalSince(updatedAt) > Self.threshold ? .stale(lastReported: updatedAt) : .live(updatedAt: updatedAt)
        } else {
            self = .scheduledOnly
        }
    }

    var isLive: Bool {
        if case .live = self { true } else { false }
    }
}

extension TrainStatus {
    /// Delayed starts at a reported delay of 3 min (D12).
    static let delayThresholdMinutes = 3

    /// D12/D13: On time and Delayed need fresh live data for today. Missing, stale or offline data and any other day
    /// mean Scheduled, never On time. A reported cancellation or skipped stop stands for the rest of the day.
    static func resolve(for trip: Trip, update: LiveTripUpdate?, freshness: Freshness, isToday: Bool) -> TrainStatus {
        guard isToday, let update else { return .scheduled }
        if update.isCancelled { return .cancelled(reportedAt: update.reportedAt) }
        if update.isStopSkipped { return .stopSkipped }
        guard freshness.isLive else { return .scheduled }

        let delay = update.delayMinutes
            ?? update.expectedDeparture.map { Int($0.timeIntervalSince(trip.scheduledDeparture) / 60) }
            ?? 0
        return delay >= delayThresholdMinutes ? .delayed(minutes: delay, reportedAt: update.reportedAt) : .onTime
    }
}

/// A trip with its resolved status: what one timeline card shows. Identity is the trip's key (D9).
struct Departure: Hashable, Sendable, Identifiable {
    let trip: Trip
    let status: TrainStatus
    /// Only set while the status rests on fresh live data; otherwise the card sits at its scheduled time.
    let expectedDeparture: Date?
    let expectedArrival: Date?

    var id: TripKey { trip.key }
    /// Where the card sits on the timeline: expected when known, else scheduled.
    var departureTime: Date { expectedDeparture ?? trip.scheduledDeparture }

    /// Resolves every trip's status and sorts by expected departure, else scheduled. Offline, a cached platform may
    /// have changed since, so every card reads "Platform pending" (TT-115).
    static func resolve(_ trips: [Trip], live: LiveSnapshot, freshness: Freshness, isToday: Bool) -> [Departure] {
        trips.map { scheduled in
            var trip = scheduled
            if case .offline = freshness { trip.platform = .pending }
            let update = live.updates[trip.key.tripId]
            let status = TrainStatus.resolve(for: trip, update: update, freshness: freshness, isToday: isToday)
            let hasEstimate = switch status {
            case .onTime, .delayed: true
            default: false
            }
            return Departure(
                trip: trip,
                status: status,
                expectedDeparture: hasEstimate ? update?.expectedDeparture : nil,
                expectedArrival: hasEstimate ? update?.expectedArrival : nil
            )
        }
        .sorted { ($0.departureTime, $0.trip.key.tripId) < ($1.departureTime, $1.trip.key.tripId) }
    }
}

extension Departure {
    /// The countdown shows "in 1 min" to "in 15 min": that is the window in which the next train's card shows the
    /// platform placeholder (TT-162, D55).
    static let platformWaitMinutes = 1...15

    /// The card shows the pulsing placeholder in place of the dash only while the platform is worth waiting for: the next
    /// usable train, its "in N min" countdown within 15 min, its platform still pending, fresh live data and a station
    /// whose feed publishes platforms. Later trains, "Departing", another day, stale or offline data, no platform source
    /// and cancelled trains keep the dash, so at most one thing moves on screen (TT-162, D55).
    func awaitsPlatform(isNext: Bool, now: Date, freshness: Freshness, hasPlatformSource: Bool) -> Bool {
        guard isNext, isUsable, hasPlatformSource, freshness.isLive, trip.platform == .pending else { return false }
        // The same whole minutes the card's countdown shows (`TimeFormatting.relative`).
        return Self.platformWaitMinutes.contains(Int(departureTime.timeIntervalSince(now) / 60))
    }
}

extension ServiceDay {
    /// Parses "2026-11-05".
    init?(_ string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    /// The moment of a wall-clock time on this service day in Toronto; times before 3:00 AM fall on the next calendar day (D24).
    func date(hour: Int, minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = goTimeZone
        let nextDay = hour < Self.cutoffHour ? 1 : 0
        return calendar.date(from: DateComponents(year: year, month: month, day: day + nextDay, hour: hour, minute: minute))!
    }
}
