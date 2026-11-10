import Foundation
@testable import TrainTimes

private final class BundleToken {}

/// A repository that returns what a test hands it.
struct StubScheduleRepository: ScheduleRepository {
    var tripList: [Trip]
    var live: LiveSnapshot
    var stopList: [TripStop]

    func trips(for route: Route, on day: ServiceDay) async throws -> [Trip] { tripList }
    func liveStatus(for route: Route, on day: ServiceDay) async throws -> LiveSnapshot { live }
    func lineNotices(for line: Line) async throws -> [LineNotice] { [] }
    func stops(for trip: TripKey, on route: Route) async throws -> [TripStop] { stopList }
}

extension TripDetailsViewModel {
    nonisolated static let fixtureTripId = "LW-0732-20261105"

    /// One fixture trip (the 7:32 AM train by default) on the fixture clock, Thu Nov 5, 7:21 AM, already loaded.
    @MainActor
    static func loadedFixture(
        _ scenario: FixtureScheduleRepository.Scenario = .normal,
        tripId: String = fixtureTripId,
        minutesLater: Int = 0,
        hasAlert: Bool = false
    ) async throws -> TripDetailsViewModel {
        let repository = try FixtureScheduleRepository(scenario: scenario, bundle: Bundle(for: BundleToken.self))
        let model = TripDetailsViewModel(
            route: repository.route,
            key: TripKey(serviceDay: repository.serviceDay, tripId: tripId),
            repository: repository,
            clock: FixedClock(now: repository.now.addingTimeInterval(TimeInterval(minutesLater * 60))),
            hasAlert: hasAlert
        )
        await model.load()
        return model
    }

    /// The 7:32 AM train at 7:50 AM with fresh live data: it left at 7:43 AM, 11 min late, and is expected at Union at
    /// 8:23 AM. `skipping` marks those stops as skipped by the feed.
    @MainActor
    static func departedFixture(skipping skipped: Set<String> = []) async throws -> TripDetailsViewModel {
        let fixture = try FixtureScheduleRepository(bundle: Bundle(for: BundleToken.self))
        let day = fixture.serviceDay
        let key = TripKey(serviceDay: day, tripId: fixtureTripId)
        let delay: TimeInterval = 11 * 60
        let now = day.date(hour: 7, minute: 50)
        let trips = try await fixture.trips(for: fixture.route, on: day)
        let stops = try await fixture.stops(for: key, on: fixture.route).map { stop in
            skipped.contains(stop.id)
                ? TripStop(station: stop.station, scheduled: stop.scheduled, isSkipped: true)
                : TripStop(station: stop.station, scheduled: stop.scheduled, expected: stop.scheduled.addingTimeInterval(delay))
        }
        let update = LiveTripUpdate(
            expectedDeparture: day.date(hour: 7, minute: 43),
            expectedArrival: day.date(hour: 8, minute: 23),
            delayMinutes: 11,
            reportedAt: day.date(hour: 7, minute: 49)
        )
        let repository = StubScheduleRepository(
            tripList: trips,
            live: LiveSnapshot(updatedAt: now, updates: [fixtureTripId: update]),
            stopList: stops
        )
        let model = TripDetailsViewModel(route: fixture.route, key: key, repository: repository, clock: FixedClock(now: now), hasAlert: true)
        await model.load()
        return model
    }

    /// One fixture trip with no live data at all: the timetable only (D14), as the app shows it without the Metrolinx
    /// key. The 7:58 AM express train by default, which has no platform yet.
    @MainActor
    static func timetableOnlyFixture(tripId: String = "LW-0758-20261105", hasAlert: Bool = false) async throws -> TripDetailsViewModel {
        let fixture = try FixtureScheduleRepository(bundle: Bundle(for: BundleToken.self))
        let key = TripKey(serviceDay: fixture.serviceDay, tripId: tripId)
        let repository = StubScheduleRepository(
            tripList: try await fixture.trips(for: fixture.route, on: fixture.serviceDay),
            live: .empty,
            stopList: try await fixture.stops(for: key, on: fixture.route)
        )
        let model = TripDetailsViewModel(
            route: fixture.route, key: key, repository: repository, clock: FixedClock(now: fixture.now), hasAlert: hasAlert
        )
        await model.load()
        return model
    }

    /// West Harbour to Union with 12 stops, 6:58 to 8:02 AM, timetable only, at 6:30 AM: the list is taller than the
    /// sheet (the canvas's Trip-Details-End frame).
    @MainActor
    static func longTripFixture(hasAlert: Bool = false) async throws -> TripDetailsViewModel {
        let fixture = try FixtureScheduleRepository(bundle: Bundle(for: BundleToken.self))
        let day = fixture.serviceDay
        let departure = day.date(hour: 6, minute: 58)
        let trip = Trip(
            key: TripKey(serviceDay: day, tripId: "LW-0658-20261105"),
            scheduledDeparture: departure,
            scheduledArrival: day.date(hour: 8, minute: 2),
            platform: .pending,
            tags: []
        )
        let stations = [
            ("WH", "West Harbour GO", 0), ("AL", "Aldershot GO", 10), ("BU", "Burlington GO", 14), ("AP", "Appleby GO", 19),
            ("BR", "Bronte GO", 23), ("OA", "Oakville GO", 28), ("CL", "Clarkson GO", 33), ("PO", "Port Credit GO", 38),
            ("LO", "Long Branch GO", 44), ("MO", "Mimico GO", 49), ("EX", "Exhibition GO", 55), ("UN", "Union Station GO", 64),
        ]
        let stops = stations.map { id, name, minutes in
            TripStop(station: Station(id: id, name: name), scheduled: departure.addingTimeInterval(TimeInterval(minutes * 60)))
        }
        let repository = StubScheduleRepository(tripList: [trip], live: .empty, stopList: stops)
        let model = TripDetailsViewModel(
            route: fixture.route, key: trip.key, repository: repository, clock: FixedClock(now: day.date(hour: 6, minute: 30)),
            hasAlert: hasAlert
        )
        await model.load()
        return model
    }
}
