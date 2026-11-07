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
}
