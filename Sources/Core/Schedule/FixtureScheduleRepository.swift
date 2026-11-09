import Foundation

/// Reads `Fixtures.json` for previews and UI tests (D20). The file ships in Debug builds and the unit test bundle only.
struct FixtureScheduleRepository: ScheduleRepository {
    enum Scenario: String, CaseIterable, Sendable {
        case normal
        case delayed
        case cancelled
        case eveningDark
        /// No connection: the cached schedule from `offlineScenario.lastUpdated` (TT-115).
        case offline
        /// A train every 30 min from 5:24 AM to 11:24 PM with no live data, so UI tests can scroll to Now and cross midnight
        /// on a timeline as long as a real day's (TT-159, D52).
        case fullDay
    }

    enum FixtureError: Error {
        case missingFile
        case invalid(String)
    }

    let route: Route
    let serviceDay: ServiceDay
    /// The fixture's clock ("now" on the canvas).
    let now: Date
    private let allTrips: [Trip]
    private let live: LiveSnapshot
    private let notices: [LineNotice]
    private let stationList: [Station]
    /// The line's stops from the fixture route's origin to its destination, minutes after the origin.
    private let lineStops: [LineStop]

    private struct LineStop: Sendable {
        let station: Station
        let minutes: Int
    }

    init(scenario: Scenario = .normal, bundle: Bundle = .main) throws {
        guard let url = bundle.url(forResource: "Fixtures", withExtension: "json") else { throw FixtureError.missingFile }
        try self.init(data: Data(contentsOf: url), scenario: scenario)
    }

    init(data: Data, scenario: Scenario) throws {
        let file = try JSONDecoder().decode(FixtureFile.self, from: data)
        guard let day = ServiceDay(file.serviceDate) else { throw FixtureError.invalid(file.serviceDate) }
        func at(_ time: String) throws -> Date {
            let parts = time.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2 else { throw FixtureError.invalid(time) }
            return day.date(hour: parts[0], minute: parts[1])
        }

        let from = Station(id: file.route.from.id, name: file.route.from.name)
        let to = Station(id: file.route.to.id, name: file.route.to.name)
        let line = Line(id: file.route.line.id, name: file.route.line.name, colorHex: file.route.line.color)

        var trains = file.trains
        if scenario == .fullDay {
            trains = stride(from: 5 * 60 + 24, through: 23 * 60 + 24, by: 30).map { minute in
                func clock(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
                return FixtureFile.TrainDTO(
                    tripId: "LW-\(String(format: "%02d%02d", minute / 60, minute % 60))-\(file.serviceDate.replacingOccurrences(of: "-", with: ""))",
                    scheduledDeparture: clock(minute), scheduledArrival: clock(minute + 35), expectedDeparture: nil,
                    expectedArrival: nil, status: "scheduled", platform: nil, tags: nil, reportedAt: nil
                )
            }
        }
        var route = Route(from: from, to: to, line: line)
        var now = try at(file.now)
        var updatedAt = try at(file.feedUpdatedAt)
        var notices: [LineNotice] = []
        if scenario == .eveningDark {
            let stations = [from, to]
            guard let eveningFrom = stations.first(where: { $0.name == file.eveningDark.route.from }),
                  let eveningTo = stations.first(where: { $0.name == file.eveningDark.route.to })
            else { throw FixtureError.invalid("eveningDark.route") }
            route = Route(from: eveningFrom, to: eveningTo, line: line)
            trains = file.eveningDark.trains
            now = try at(file.eveningDark.now)
            updatedAt = now
        }

        var updates: [String: LiveTripUpdate] = [:]
        for train in trains {
            switch train.status {
            case "onTime":
                updates[train.tripId] = LiveTripUpdate(
                    expectedDeparture: try train.expectedDeparture.map(at) ?? at(train.scheduledDeparture),
                    expectedArrival: try train.expectedArrival.map(at),
                    reportedAt: updatedAt
                )
            case "cancelled":
                updates[train.tripId] = LiveTripUpdate(isCancelled: true, reportedAt: try at(train.reportedAt ?? file.feedUpdatedAt))
            default:
                break // "scheduled": no live data for this trip
            }
        }

        switch scenario {
        case .delayed:
            let delayed = file.delayedScenario
            updates[delayed.tripId] = LiveTripUpdate(
                expectedDeparture: try at(delayed.expectedDeparture),
                expectedArrival: try at(delayed.expectedArrival),
                delayMinutes: delayed.delayMinutes,
                reportedAt: try at(delayed.reportedAt)
            )
            let notice = delayed.lineNotice
            notices = [LineNotice(id: "\(line.id)-\(notice.reportedAt)", lineName: notice.line, text: notice.text, reportedAt: try at(notice.reportedAt))]
        case .cancelled:
            let cancelled = file.cancelledScenario
            updates[cancelled.tripId] = LiveTripUpdate(isCancelled: true, reportedAt: try at(cancelled.reportedAt))
        case .normal, .eveningDark, .offline, .fullDay:
            break
        }

        self.route = route
        self.serviceDay = day
        self.now = now
        self.allTrips = try trains.map { train in
            Trip(
                key: TripKey(serviceDay: day, tripId: train.tripId),
                scheduledDeparture: try at(train.scheduledDeparture),
                scheduledArrival: try at(train.scheduledArrival),
                platform: train.platform.map(Platform.published) ?? .pending,
                tags: (train.tags ?? []).compactMap(TrainTag.init(rawValue:))
            )
        }
        self.live = scenario == .offline
            ? LiveSnapshot(updatedAt: try at(file.offlineScenario.lastUpdated), isOffline: true, updates: updates)
            : LiveSnapshot(updatedAt: updatedAt, updates: updates)
        self.notices = notices
        let stationList = file.stations
            .map { Station(id: $0.id, name: $0.name, lines: $0.lines) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        self.stationList = stationList
        self.lineStops = try file.stops.map { stop in
            guard let station = stationList.first(where: { $0.id == stop.id }) else { throw FixtureError.invalid(stop.id) }
            return LineStop(station: station, minutes: stop.minutes)
        }
    }

    /// The fixture day's trains, and the same timetable with no live data on every later day but Sunday, where the
    /// route has no direct trains (TT-115, `schedule-no-trains.png`).
    func trips(for route: Route, on day: ServiceDay) async throws -> [Trip] {
        guard matches(route, serviceDay) else { return [] }
        if day == serviceDay { return allTrips }
        guard day > serviceDay, day.weekday != 1 else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = goTimeZone
        func onDay(_ date: Date) -> Date {
            let time = calendar.dateComponents([.hour, .minute], from: date)
            return day.date(hour: time.hour ?? 0, minute: time.minute ?? 0)
        }
        return allTrips.map { trip in
            Trip(
                key: TripKey(serviceDay: day, tripId: trip.key.tripId),
                scheduledDeparture: onDay(trip.scheduledDeparture),
                scheduledArrival: onDay(trip.scheduledArrival),
                platform: trip.platform,
                tags: trip.tags
            )
        }
    }

    func liveStatus(for route: Route, on day: ServiceDay) async throws -> LiveSnapshot {
        matches(route, day) ? live : .empty
    }

    func lineNotices(for line: Line) async throws -> [LineNotice] {
        line.id == route.line?.id ? notices : []
    }

    /// The fixture stop list in the route's direction, spread over the trip's scheduled run (on later days too). A trip
    /// with a live arrival estimate carries its departure delay to every stop and ends at that estimate; otherwise stops
    /// have no estimate.
    func stops(for trip: TripKey, on route: Route) async throws -> [TripStop] {
        guard let found = try await trips(for: route, on: trip.serviceDay).first(where: { $0.key == trip }),
              let total = lineStops.last?.minutes, total > 0
        else { return [] }
        let ordered = route.from.id == lineStops.first?.station.id
            ? lineStops
            : lineStops.reversed().map { LineStop(station: $0.station, minutes: total - $0.minutes) }
        let run = found.scheduledArrival.timeIntervalSince(found.scheduledDeparture)
        let update = trip.serviceDay == serviceDay ? live.updates[trip.tripId] : nil
        let delay = update?.expectedArrival == nil ? nil : update?.expectedDeparture?.timeIntervalSince(found.scheduledDeparture)
        return ordered.enumerated().map { index, stop in
            let minutes = (run / 60 * Double(stop.minutes) / Double(total)).rounded()
            let scheduled = found.scheduledDeparture.addingTimeInterval(minutes * 60)
            let isLast = index == ordered.count - 1
            let expected = delay.flatMap { isLast ? update?.expectedArrival : scheduled.addingTimeInterval($0) }
            return TripStop(station: stop.station, scheduled: scheduled, expected: expected)
        }
    }

    private func matches(_ route: Route, _ day: ServiceDay) -> Bool {
        day == serviceDay && route.from.id == self.route.from.id && route.to.id == self.route.to.id
    }
}

/// Previews and tests list the illustrative stations in `Fixtures.json` (TT-121, D29); the app lists the GTFS feed's
/// stations (TT-130).
/// Only the fixture route's pair has a line and trips.
extension FixtureScheduleRepository: StationRepository {
    func stations() async throws -> [Station] {
        stationList
    }

    func route(from: Station, to: Station) async throws -> Route {
        let served = Set([from.id, to.id]) == Set([self.route.from.id, self.route.to.id])
        return Route(from: from, to: to, line: served ? self.route.line : nil)
    }
}

/// The shape of `design/handoff/Fixtures.json`. Feed and JSON types stay private to the repository.
private struct FixtureFile: Decodable {
    struct StationDTO: Decodable { let id: String; let name: String }
    struct StationListingDTO: Decodable { let id: String; let name: String; let lines: [String] }
    struct LineDTO: Decodable { let id: String; let name: String; let color: String? }
    struct RouteDTO: Decodable { let from: StationDTO; let to: StationDTO; let line: LineDTO }
    struct TrainDTO: Decodable {
        let tripId: String
        let scheduledDeparture: String
        let scheduledArrival: String
        let expectedDeparture: String?
        let expectedArrival: String?
        let status: String
        let platform: String?
        let tags: [String]?
        let reportedAt: String?
    }
    struct StopDTO: Decodable { let id: String; let minutes: Int }
    struct NoticeDTO: Decodable { let line: String; let text: String; let reportedAt: String }
    struct DelayedDTO: Decodable {
        let tripId: String
        let expectedDeparture: String
        let expectedArrival: String
        let delayMinutes: Int
        let reportedAt: String
        let lineNotice: NoticeDTO
    }
    struct CancelledDTO: Decodable { let tripId: String; let reportedAt: String }
    struct OfflineDTO: Decodable { let lastUpdated: String }
    struct EveningDTO: Decodable {
        struct NamesDTO: Decodable { let from: String; let to: String }
        let route: NamesDTO
        let now: String
        let trains: [TrainDTO]
    }

    let route: RouteDTO
    let serviceDate: String
    let now: String
    let feedUpdatedAt: String
    let stops: [StopDTO]
    let trains: [TrainDTO]
    let delayedScenario: DelayedDTO
    let cancelledScenario: CancelledDTO
    let offlineScenario: OfflineDTO
    let eveningDark: EveningDTO
    let stations: [StationListingDTO]
}
