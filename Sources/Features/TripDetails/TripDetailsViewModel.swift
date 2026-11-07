import Foundation
import Observation

/// What the Trip details sheet shows (TT-118), every time already formatted by the one formatter (D17).
struct TripDetails: Hashable {
    struct Fact: Hashable {
        let label: String
        let value: String
        /// Later than scheduled: drawn in delay-ink.
        var isLate = false
    }

    struct Stop: Hashable, Identifiable {
        let id: String
        let name: String
        let time: String
        /// Origin and destination: headline name and a filled accent marker.
        let isEnd: Bool
        /// A red x and a struck time.
        let isSkipped: Bool
    }

    /// "7:32 AM train": the scheduled departure, which stays the train's name (D9).
    let title: String
    /// "Oakville GO to Union Station GO".
    let routeName: String
    /// "Lakeshore West · Thu, Nov 5".
    let lineAndDay: String
    let status: TripStatus
    let scheduledDeparture: String
    /// "Expected departure", or "Departed" once the live departure is past; nil when the feed has no estimate.
    let liveDeparture: Fact?
    let scheduledArrival: String
    /// Nil when the feed has no arrival estimate: the cell is left out.
    let estimatedArrival: String?
    /// "Platform 2" or "Platform pending".
    let platform: String
    /// "Expected" when every stop has a live time, otherwise "Scheduled".
    let stopsHeader: String
    let stops: [Stop]
    /// The arrival basis under the stop list.
    let footnote: String
    /// "Alert me" or "Manage alert"; nil once the train has left.
    let alertButton: String?
}

/// The Trip details sheet for one trip and service date (TT-118). It loads the trip, its live status and its stops from
/// the repository, resolves the status with the timeline's rules (D12, D13) and never fills a missing value with a guess.
@Observable @MainActor
final class TripDetailsViewModel {
    let route: Route
    let key: TripKey
    /// An alert rule covers this trip: "Manage alert" in place of "Alert me". Alert rules arrive in TT-142.
    let hasAlert: Bool

    /// Nil until loaded, or when the trip is not on the route that day.
    private(set) var departure: Departure?
    private(set) var stops: [TripStop] = []
    private(set) var freshness: Freshness?
    /// The clock at the last load.
    private(set) var now: Date

    private let repository: any ScheduleRepository
    private let clock: any AppClock

    init(route: Route, key: TripKey, repository: any ScheduleRepository, clock: any AppClock, hasAlert: Bool = false) {
        self.route = route
        self.key = key
        self.repository = repository
        self.clock = clock
        self.hasAlert = hasAlert
        now = clock.now
    }

    var isToday: Bool { key.serviceDay == ServiceDay(containing: now) }

    /// The live departure is in the past: the sheet says "Departed" and hides the alert button.
    var hasDeparted: Bool {
        guard let expected = departure?.expectedDeparture else { return false }
        return expected <= now
    }

    /// The stop list shows live times only while the trip's status rests on fresh live data and every stop the train
    /// calls at has an estimate; otherwise every stop shows its scheduled time.
    var hasLiveStops: Bool {
        guard departure?.expectedDeparture != nil, !stops.isEmpty else { return false }
        return stops.allSatisfy { $0.isSkipped || $0.expected != nil }
    }

    /// No alert for a train that has already left today.
    var showsAlertButton: Bool {
        guard let departure else { return false }
        return !(isToday && departure.departureTime <= now)
    }

    func details(_ formatter: some TimeFormatting) -> TripDetails? {
        guard let departure else { return nil }
        let trip = departure.trip
        let isLive = hasLiveStops
        let day = key.serviceDay.shortLabel
        let platform = switch trip.platform {
        case .published(let name): String(format: String(localized: "schedule.platform"), name)
        case .pending: String(localized: "schedule.platform_pending")
        }
        return TripDetails(
            title: String(format: String(localized: "trip.title"), formatter.time(trip.scheduledDeparture)),
            routeName: String(
                format: String(localized: "schedule.route_title"),
                stops.first?.station.name ?? route.from.name,
                stops.last?.station.name ?? route.to.name
            ),
            lineAndDay: route.line.map { String(format: String(localized: "trip.line_day"), $0.name, day) } ?? day,
            status: TripStatus(departure.status, formatter: formatter),
            scheduledDeparture: formatter.time(trip.scheduledDeparture),
            liveDeparture: departure.expectedDeparture.map { expected in
                TripDetails.Fact(
                    label: hasDeparted ? String(localized: "trip.departed") : String(localized: "trip.expected_departure"),
                    value: formatter.time(expected),
                    isLate: expected.timeIntervalSince(trip.scheduledDeparture) >= 60
                )
            },
            scheduledArrival: formatter.time(trip.scheduledArrival),
            estimatedArrival: departure.expectedArrival.map { formatter.time($0) },
            platform: platform,
            stopsHeader: isLive ? String(localized: "trip.stops_expected") : String(localized: "trip.stops_scheduled"),
            stops: stops.enumerated().map { index, stop in
                TripDetails.Stop(
                    id: stop.id,
                    name: stop.station.name,
                    time: formatter.time(isLive ? (stop.expected ?? stop.scheduled) : stop.scheduled),
                    isEnd: index == 0 || index == stops.count - 1,
                    isSkipped: stop.isSkipped
                )
            },
            footnote: isLive
                ? String(format: String(localized: "trip.footnote_live"), formatter.time(trip.scheduledArrival))
                : String(localized: "trip.footnote_scheduled"),
            alertButton: showsAlertButton
                ? (hasAlert ? String(localized: "button.manage_alert") : String(localized: "button.alert_me"))
                : nil
        )
    }

    /// The freshness line beside the badge (D14), as on the timeline.
    func freshnessMode(_ formatter: some TimeFormatting) -> FreshnessLine.Mode? {
        switch freshness {
        case nil: nil
        case .live(let updatedAt): .live(updated: formatter.updated(at: updatedAt, now: clock.now))
        case .scheduledOnly: .scheduledOnly(day: isToday ? nil : key.serviceDay.shortLabel)
        case .stale(let lastReported): .stale(lastReported: formatter.time(lastReported))
        case .offline(let lastUpdated): .offline(lastUpdated: lastUpdated.map { formatter.time($0) })
        }
    }

    /// Loads, then reloads on the timetable's foreground refresh interval while the sheet is open, so the sheet moves
    /// with the schedule and never holds it up.
    func run() async {
        while !Task.isCancelled {
            await load()
            try? await Task.sleep(for: .seconds(TTTimeline.foregroundRefreshSeconds))
        }
    }

    func load() async {
        let day = key.serviceDay
        let current = clock.now
        let isToday = day == ServiceDay(containing: current)
        let trips = (try? await repository.trips(for: route, on: day)) ?? []
        let live = isToday ? (try? await repository.liveStatus(for: route, on: day)) ?? .empty : .empty
        let stops = (try? await repository.stops(for: key, on: route)) ?? []
        let freshness = isToday ? Freshness(live, now: current) : .scheduledOnly
        now = current
        departure = Departure.resolve(trips.filter { $0.key == key }, live: live, freshness: freshness, isToday: isToday).first
        self.stops = stops
        self.freshness = freshness
    }
}
