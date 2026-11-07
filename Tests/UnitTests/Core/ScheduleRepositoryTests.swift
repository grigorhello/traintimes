import XCTest
@testable import TrainTimes

/// TT-110: every fixture scenario loads, missing or stale data is never On time, and trip identity survives a moving estimate.
final class ScheduleRepositoryTests: XCTestCase {
    private let bundle = Bundle(for: ScheduleRepositoryTests.self)
    private let day = ServiceDay(year: 2026, month: 11, day: 5)

    private func repository(_ scenario: FixtureScheduleRepository.Scenario) throws -> FixtureScheduleRepository {
        try FixtureScheduleRepository(scenario: scenario, bundle: bundle)
    }

    private func departures(
        _ repo: FixtureScheduleRepository, now: Date? = nil, offline: Bool = false, isToday: Bool = true
    ) async throws -> [Departure] {
        let trips = try await repo.trips(for: repo.route, on: repo.serviceDay)
        var live = try await repo.liveStatus(for: repo.route, on: repo.serviceDay)
        live.isOffline = offline
        return Departure.resolve(trips, live: live, freshness: Freshness(live, now: now ?? repo.now), isToday: isToday)
    }

    private func at(_ hour: Int, _ minute: Int) -> Date { day.date(hour: hour, minute: minute) }

    // MARK: Every scenario loads

    func testEveryScenarioLoads() async throws {
        for scenario in FixtureScheduleRepository.Scenario.allCases {
            let repo = try repository(scenario)
            let trips = try await repo.trips(for: repo.route, on: repo.serviceDay)
            XCTAssertEqual(trips.count, 4, "\(scenario)")
            XCTAssertEqual(repo.serviceDay, day)
        }
    }

    func testNormalScenario() async throws {
        let repo = try repository(.normal)
        XCTAssertEqual(repo.route.from.name, "Oakville")
        XCTAssertEqual(repo.route.to.name, "Union")
        XCTAssertEqual(repo.route.line?.colorHex, "#111827")
        let result = try await departures(repo)
        XCTAssertEqual(result.map(\.status), [.onTime, .onTime, .scheduled, .scheduled])
        XCTAssertEqual(result[0].trip.platform, .published("2"))
        XCTAssertEqual(result[1].trip.platform, .pending)
        XCTAssertEqual(result[1].trip.tags, [.express], "Only Express is a v1 tag")
        let notices = try await repo.lineNotices(for: try XCTUnwrap(repo.route.line))
        XCTAssertTrue(notices.isEmpty)
    }

    func testDelayedScenario() async throws {
        let repo = try repository(.delayed)
        let result = try await departures(repo)
        XCTAssertEqual(result[0].status, .delayed(minutes: 9, reportedAt: at(7, 14)))
        XCTAssertEqual(result[0].expectedDeparture, at(7, 41))
        let notices = try await repo.lineNotices(for: try XCTUnwrap(repo.route.line))
        XCTAssertEqual(notices.map(\.text), ["Delays of up to 15 min near Port Credit"])
    }

    func testCancelledScenario() async throws {
        let result = try await departures(try repository(.cancelled))
        XCTAssertEqual(result[0].status, .cancelled(reportedAt: at(7, 5)))
        XCTAssertNil(result[0].expectedDeparture)
    }

    func testEveningDarkScenario() async throws {
        let repo = try repository(.eveningDark)
        XCTAssertEqual(repo.route.from.name, "Union")
        XCTAssertEqual(repo.route.to.name, "Oakville")
        XCTAssertEqual(repo.now, at(17, 3))
        let result = try await departures(repo)
        XCTAssertEqual(result.map(\.status), [.onTime, .cancelled(reportedAt: at(16, 40)), .scheduled, .scheduled])
        XCTAssertEqual(result[0].trip.platform, .published("9"))
    }

    func testOtherRouteOrDayHasNoTrains() async throws {
        let repo = try repository(.normal)
        let swapped = Route(from: repo.route.to, to: repo.route.from, line: repo.route.line)
        let trips = try await repo.trips(for: swapped, on: repo.serviceDay)
        XCTAssertTrue(trips.isEmpty)
        let otherDay = try await repo.trips(for: repo.route, on: ServiceDay(year: 2026, month: 11, day: 6))
        XCTAssertTrue(otherDay.isEmpty)
    }

    // MARK: Missing or stale data is Scheduled, never On time (D13)

    func testStaleLiveDataMapsToScheduled() async throws {
        for scenario in [FixtureScheduleRepository.Scenario.normal, .delayed] {
            let repo = try repository(scenario)
            let later = repo.now.addingTimeInterval(Freshness.threshold + 60)
            let live = try await repo.liveStatus(for: repo.route, on: repo.serviceDay)
            XCTAssertEqual(Freshness(live, now: later), .stale(lastReported: at(7, 21)))
            let result = try await departures(repo, now: later)
            XCTAssertEqual(result.map(\.status), Array(repeating: .scheduled, count: 4), "\(scenario)")
            XCTAssertTrue(result.allSatisfy { $0.expectedDeparture == nil }, "Cards move back to scheduled positions")
        }
    }

    func testMissingLiveDataMapsToScheduled() async throws {
        let repo = try repository(.normal)
        let trips = try await repo.trips(for: repo.route, on: repo.serviceDay)
        let freshness = Freshness(.empty, now: repo.now)
        XCTAssertEqual(freshness, .scheduledOnly)
        let result = Departure.resolve(trips, live: .empty, freshness: freshness, isToday: true)
        XCTAssertEqual(result.map(\.status), Array(repeating: .scheduled, count: 4))
    }

    func testOfflineAndFutureDayMapToScheduled() async throws {
        let repo = try repository(.normal)
        let offline = try await departures(repo, offline: true)
        XCTAssertFalse(offline.contains { $0.status == .onTime })
        let future = try await departures(repo, isToday: false)
        XCTAssertEqual(future.map(\.status), Array(repeating: .scheduled, count: 4))
    }

    func testCancellationStandsWhenDataGoesStale() async throws {
        let repo = try repository(.cancelled)
        let result = try await departures(repo, now: repo.now.addingTimeInterval(600))
        XCTAssertEqual(result[0].status, .cancelled(reportedAt: at(7, 5)))
    }

    func testDelayThresholdIsThreeMinutes() {
        let trip = Trip(
            key: TripKey(serviceDay: day, tripId: "T"), scheduledDeparture: at(7, 32), scheduledArrival: at(8, 12),
            platform: .pending, tags: []
        )
        let fresh = Freshness.live(updatedAt: at(7, 21))
        func status(expected minute: Int) -> TrainStatus {
            let update = LiveTripUpdate(expectedDeparture: at(7, minute), reportedAt: at(7, 20))
            return TrainStatus.resolve(for: trip, update: update, freshness: fresh, isToday: true)
        }
        XCTAssertEqual(status(expected: 34), .onTime)
        XCTAssertEqual(status(expected: 35), .delayed(minutes: 3, reportedAt: at(7, 20)))
    }

    // MARK: Trip identity (D9)

    func testTripIdentityStaysWhenEstimateMoves() async throws {
        let normal = try await departures(try repository(.normal))
        let delayed = try await departures(try repository(.delayed))
        let before = try XCTUnwrap(normal.first { $0.trip.key.tripId == "LW-0732-20261105" })
        let after = try XCTUnwrap(delayed.first { $0.trip.key.tripId == "LW-0732-20261105" })

        XCTAssertEqual(before.id, after.id)
        XCTAssertEqual(after.trip.scheduledDeparture, at(7, 32))
        XCTAssertEqual(after.departureTime, at(7, 41))
        let formatter = TimeFormatter(format: .twelveHour)
        XCTAssertEqual(formatter.time(after.trip.scheduledDeparture), "7:32 AM", "Still the 7:32 AM train")
        XCTAssertEqual(formatter.time(after.departureTime), "7:41 AM")
    }

    // MARK: Stations (TT-121)

    /// The station list is alphabetical, with full names and line context, and holds the fixture route's stations.
    func testStationsAreAlphabeticalWithFullNames() async throws {
        let repo = try repository(.normal)
        let stations = try await repo.stations()
        XCTAssertGreaterThan(stations.count, 60)
        XCTAssertEqual(stations.map(\.name), stations.map(\.name).sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        let oakville = try XCTUnwrap(stations.first { $0.id == repo.route.from.id })
        XCTAssertEqual(oakville.name, "Oakville GO")
        XCTAssertEqual(oakville.lines, ["Lakeshore West"])
        XCTAssertEqual(stations.first { $0.id == repo.route.to.id }?.name, "Union Station GO")
        XCTAssertTrue(stations.allSatisfy { !$0.lines.isEmpty })
    }

    // MARK: Stops (TT-118)

    func testStopsRunFromOriginToDestinationInTheRouteDirection() async throws {
        let morning = try repository(.normal)
        let stops = try await morning.stops(for: TripKey(serviceDay: day, tripId: "LW-0732-20261105"), on: morning.route)
        XCTAssertEqual(stops.map(\.id), ["OA", "CL", "PO", "LO", "MO", "EX", "UN"])
        XCTAssertEqual(stops.first?.scheduled, at(7, 32))
        XCTAssertEqual(stops.last?.scheduled, at(8, 12))
        XCTAssertTrue(stops.allSatisfy { $0.expected == nil }, "No arrival estimate, so no stop estimates")

        let evening = try repository(.eveningDark)
        let back = try await evening.stops(for: TripKey(serviceDay: day, tripId: "LW-1752"), on: evening.route)
        XCTAssertEqual(back.map(\.id), ["UN", "EX", "MO", "LO", "PO", "CL", "OA"])
        XCTAssertEqual(back.first?.scheduled, at(17, 52))
        XCTAssertEqual(back.last?.scheduled, at(18, 27))
    }

    func testDelayedStopsCarryTheFeedEstimates() async throws {
        let repo = try repository(.delayed)
        let stops = try await repo.stops(for: TripKey(serviceDay: day, tripId: "LW-0732-20261105"), on: repo.route)
        XCTAssertEqual(stops.map(\.expected), [at(7, 41), at(7, 49), at(7, 55), at(8, 1), at(8, 6), at(8, 13), at(8, 21)])
    }
}
