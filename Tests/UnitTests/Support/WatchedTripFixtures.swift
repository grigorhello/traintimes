import Foundation
@testable import TrainTimes

private final class BundleToken {}

/// The trips a test says have an alert.
final class FakeWatchedTrips: WatchedTripsProviding {
    var trips: Set<TripKey>

    init(_ trips: Set<TripKey> = []) {
        self.trips = trips
    }

    func isWatched(_ trip: TripKey) -> Bool { trips.contains(trip) }
}

extension ScheduleViewModel {
    nonisolated static let watchedTripId = "LW-0705-20261105"

    /// `schedule-watched.png`: the canvas route on Thu Nov 5 with the fixture trains on time, plus the 7:05 AM train
    /// (scheduled at Union 7:45 AM), which left on time and is expected at Union at 7:46 AM. The clock is `hour:minute`
    /// (7:28 AM in the frame) and the feed is fresh at that moment. `isWatched` arms its alert; `hasArrivalEstimate` false
    /// leaves the arrival scheduled; `hasLiveData` false leaves the 7:05 AM train out of the feed, so it stays Scheduled.
    /// `route` replaces the canvas route on screen (the trains stay the fixture's).
    @MainActor
    static func watchedFixture(
        route: Route? = nil, hour: Int = 7, minute: Int = 28, isWatched: Bool = true, hasArrivalEstimate: Bool = true, hasLiveData: Bool = true
    ) async throws -> ScheduleViewModel {
        let fixture = try FixtureScheduleRepository(bundle: Bundle(for: BundleToken.self))
        let day = fixture.serviceDay
        let now = day.date(hour: hour, minute: minute)
        let key = TripKey(serviceDay: day, tripId: watchedTripId)
        let watched = Trip(
            key: key, scheduledDeparture: day.date(hour: 7, minute: 5), scheduledArrival: day.date(hour: 7, minute: 45),
            platform: .published("2"), tags: []
        )
        var live = try await fixture.liveStatus(for: fixture.route, on: day)
        live.updatedAt = now
        if hasLiveData {
            live.updates[watchedTripId] = LiveTripUpdate(
                expectedDeparture: day.date(hour: 7, minute: 5),
                expectedArrival: hasArrivalEstimate ? day.date(hour: 7, minute: 46) : nil,
                delayMinutes: 0,
                reportedAt: now
            )
        }
        let repository = StubScheduleRepository(
            tripList: [watched] + (try await fixture.trips(for: fixture.route, on: day)), live: live, stopList: []
        )
        let route = route ?? fixture.route
        let model = ScheduleViewModel(
            route: route, repository: repository, clock: FixedClock(now: now),
            watchedTrips: FakeWatchedTrips(isWatched ? [key] : [])
        )
        await model.loadIfNeeded()
        return model
    }
}
