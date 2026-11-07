import Foundation

/// Reads `Fixtures.json` for previews and UI tests (D20). The file ships in Debug builds and the unit test bundle only.
struct FixtureScheduleRepository: ScheduleRepository {
    enum Scenario: String, CaseIterable, Sendable {
        case normal
        case delayed
        case cancelled
        case eveningDark
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
        case .normal, .eveningDark:
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
        self.live = LiveSnapshot(updatedAt: updatedAt, updates: updates)
        self.notices = notices
        self.stationList = file.stations
            .map { Station(id: $0.id, name: $0.name, lines: $0.lines) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func trips(for route: Route, on day: ServiceDay) async throws -> [Trip] {
        matches(route, day) ? allTrips : []
    }

    func liveStatus(for route: Route, on day: ServiceDay) async throws -> LiveSnapshot {
        matches(route, day) ? live : .empty
    }

    func lineNotices(for line: Line) async throws -> [LineNotice] {
        line.id == route.line?.id ? notices : []
    }

    private func matches(_ route: Route, _ day: ServiceDay) -> Bool {
        day == serviceDay && route.from.id == self.route.from.id && route.to.id == self.route.to.id
    }
}

/// M1 stations are the illustrative list in `Fixtures.json` (TT-121, D29); GTFS stops replace it in TT-130.
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
    let trains: [TrainDTO]
    let delayedScenario: DelayedDTO
    let cancelledScenario: CancelledDTO
    let eveningDark: EveningDTO
    let stations: [StationListingDTO]
}
