import XCTest
@testable import TrainTimes

/// D49: Settings › Testing › Demo trains puts made-up live status on the real timetable (TestFlight builds only).
@MainActor
final class DemoScheduleRepositoryTests: XCTestCase {
    private func demo(_ mode: DemoTrains) throws -> (repository: DemoScheduleRepository, base: FixtureScheduleRepository) {
        let base = try FixtureScheduleRepository(bundle: Bundle(for: Self.self))
        return (DemoScheduleRepository(base: base, clock: FixedClock(now: base.now), mode: { mode }), base)
    }

    private func resolved(_ mode: DemoTrains) async throws -> (departures: [Departure], freshness: Freshness) {
        let (repository, base) = try demo(mode)
        let trips = try await repository.trips(for: base.route, on: base.serviceDay)
        let live = try await repository.liveStatus(for: base.route, on: base.serviceDay)
        let freshness = Freshness(live, now: base.now)
        return (Departure.resolve(trips, live: live, freshness: freshness, isToday: true), freshness)
    }

    func testOffRepeatsTheRealSchedule() async throws {
        let (repository, base) = try demo(.off)
        let route = base.route
        let day = base.serviceDay
        let live = try await repository.liveStatus(for: route, on: day)
        let real = try await base.liveStatus(for: route, on: day)
        XCTAssertEqual(live, real)
        let notices = try await repository.lineNotices(for: try XCTUnwrap(route.line))
        let realNotices = try await base.lineNotices(for: try XCTUnwrap(route.line))
        XCTAssertEqual(notices, realNotices)
    }

    /// The next train is late, the one after it is cancelled, the rest are on time.
    func testDelaysMakesTheNextTrainLateAndTheOneAfterItCancelled() async throws {
        let (departures, freshness) = try await resolved(.delays)
        XCTAssertTrue(freshness.isLive)
        XCTAssertEqual(departures.count, 4)
        let late = try XCTUnwrap(departures.first { departure in
            if case .delayed(let minutes, _) = departure.status { minutes == DemoScheduleRepository.delayMinutes } else { false }
        })
        XCTAssertEqual(late.trip.scheduledDeparture, departures.map(\.trip.scheduledDeparture).min())
        XCTAssertEqual(late.expectedDeparture, late.trip.scheduledDeparture.addingTimeInterval(9 * 60))
        XCTAssertEqual(departures.filter { !$0.isUsable }.count, 1)
        XCTAssertEqual(departures.filter { $0.status == .onTime }.count, 2)
    }

    /// A train 9 min late has not left at its scheduled time, so it stays the late one and the cancelled one stays cancelled.
    func testTheLateTrainStaysLateAfterItsScheduledTime() async throws {
        let base = try FixtureScheduleRepository(bundle: Bundle(for: Self.self))
        let trips = try await base.trips(for: base.route, on: base.serviceDay).sorted { $0.scheduledDeparture < $1.scheduledDeparture }
        let first = try XCTUnwrap(trips.first)
        let clock = FixedClock(now: first.scheduledDeparture.addingTimeInterval(60))
        let repository = DemoScheduleRepository(base: base, clock: clock, mode: { .delays })
        let live = try await repository.liveStatus(for: base.route, on: base.serviceDay)
        XCTAssertEqual(live.updates[first.key.tripId]?.delayMinutes, DemoScheduleRepository.delayMinutes)
        XCTAssertEqual(live.updates[trips[1].key.tripId]?.isCancelled, true)
    }

    /// TT-158: live status belongs to the real clock, so with Mock time on and Demo trains off there is none; Demo trains
    /// still works on the mocked clock.
    func testMockTimeLeavesNoRealLiveStatus() async throws {
        let base = try FixtureScheduleRepository(bundle: Bundle(for: Self.self))
        let clock = FixedClock(now: base.now)
        let mocked = DemoScheduleRepository(base: base, clock: clock, mode: { .off }, isMockTime: { true })
        let live = try await mocked.liveStatus(for: base.route, on: base.serviceDay)
        XCTAssertEqual(live, .empty)
        let delays = DemoScheduleRepository(base: base, clock: clock, mode: { .delays }, isMockTime: { true })
        let delayed = try await delays.liveStatus(for: base.route, on: base.serviceDay)
        XCTAssertFalse(delayed.updates.isEmpty)
    }

    func testDelaysAddsALineNotice() async throws {
        let (repository, base) = try demo(.delays)
        let notices = try await repository.lineNotices(for: try XCTUnwrap(base.route.line))
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(notices.first?.lineName, "Lakeshore West")
    }

    /// Offline: the cached timetable with no live status, as if there were no connection.
    func testOfflineIsTheCachedScheduleWithNoLiveStatus() async throws {
        let (departures, freshness) = try await resolved(.offline)
        guard case .offline(let lastUpdated) = freshness else { return XCTFail("Expected offline, got \(freshness)") }
        XCTAssertNotNil(lastUpdated)
        XCTAssertEqual(departures.count, 4)
        XCTAssertTrue(departures.allSatisfy { $0.status == .scheduled && $0.expectedDeparture == nil })
    }

    func testTheModeIsReadOnEachCall() async throws {
        final class Box: @unchecked Sendable { // read and written on the main actor in this test only
            var mode = DemoTrains.off
        }
        let box = Box()
        let base = try FixtureScheduleRepository(bundle: Bundle(for: Self.self))
        let repository = DemoScheduleRepository(base: base, clock: FixedClock(now: base.now), mode: { box.mode })
        let off = try await repository.liveStatus(for: base.route, on: base.serviceDay)
        box.mode = .offline
        let offline = try await repository.liveStatus(for: base.route, on: base.serviceDay)
        XCTAssertFalse(off.isOffline)
        XCTAssertTrue(offline.isOffline)
    }
}
