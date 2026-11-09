import XCTest
@testable import TrainTimes

/// TT-131 feed replay (D36): GTFS-realtime samples written with the official protobuf bindings
/// (`scripts/make-realtime-samples.py`) for real GO trips in the TT-130 feed sample, Oakville GO to Union Station GO on
/// Monday Nov 9, 2026, read at 7:00, 7:01 and 7:02 AM. They stand in for GO's TripUpdates feed until the Metrolinx key
/// arrives (Q1).
final class GTFSRealtimeReplayTests: XCTestCase {
    private let monday = ServiceDay(year: 2026, month: 11, day: 9)
    private let route = Route(from: Station(id: "OA", name: "Oakville GO"), to: Station(id: "UN", name: "Union Station GO"), line: nil)
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func at(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        monday.date(hour: hour, minute: minute).addingTimeInterval(TimeInterval(second))
    }

    private func repository(_ replay: FeedReplay, clock: any AppClock) throws -> GTFSScheduleRepository {
        try .replaying(replay, clock: clock, directory: directory)
    }

    /// The route's departures as the timeline resolves them, by train ("LW-1108"), with the freshness mode.
    private func resolve(_ repository: GTFSScheduleRepository, now: Date) async throws -> (Freshness, [String: Departure]) {
        let trips = try await repository.trips(for: route, on: monday)
        let live = try await repository.liveStatus(for: route, on: monday)
        let freshness = Freshness(live, now: now)
        let departures = Departure.resolve(trips, live: live, freshness: freshness, isToday: true)
        return (freshness, Dictionary(uniqueKeysWithValues: departures.map { (String($0.id.tripId.dropFirst(9)), $0) }))
    }

    func testDecodesTheSample() throws {
        let feed = try GTFSRealtimeFeed(protobuf: FeedReplay.sample("tripupdates-0702"))
        XCTAssertEqual(feed.timestamp, at(7, 2))
        let updates = feed.tripUpdates(on: monday)
        XCTAssertEqual(updates.count, 8)
        let cancelled = try XCTUnwrap(updates["20261109-LW-1858"])
        XCTAssertTrue(cancelled.isCancelled)
        XCTAssertEqual(cancelled.timestamp, at(7, 0, 40))
        XCTAssertEqual(updates["20261109-LW-1758"]?.stopTimeUpdates.first?.relationship, .skipped)
        XCTAssertEqual(updates["20261109-LW-1256"]?.stopTimeUpdates.first?.departure?.time, at(7, 14))
        XCTAssertEqual(updates["20261109-LW-1258"]?.stopTimeUpdates.first?.arrival?.delay, -60, "A negative int32 delay")
        XCTAssertEqual(updates["20261109-LW-1860"]?.delay, 180)
        XCTAssertTrue(feed.tripUpdates(on: monday.adding(days: 1)).isEmpty, "Another service date is another trip (D9)")
    }

    func testATruncatedFeedThrows() throws {
        let data = try FeedReplay.sample("tripupdates-0700")
        XCTAssertThrowsError(try GTFSRealtimeFeed(protobuf: data.prefix(data.count - 3)))
    }

    /// Delay, increase and recovery: one train keeps one card whatever its estimate does (D9).
    func testDelayIncreaseAndRecovery() async throws {
        let clock = TestClock(now: at(7, 0, 30))
        let replay = try FeedReplay("tripupdates-0700")
        let repository = try repository(replay, clock: clock)

        var (freshness, departures) = try await resolve(repository, now: clock.now)
        XCTAssertEqual(freshness, .live(updatedAt: at(7, 0)))
        XCTAssertEqual(departures["LW-1108"]?.status, .delayed(minutes: 5, reportedAt: at(7, 0)))
        XCTAssertEqual(departures["LW-1108"]?.expectedDeparture, at(7, 26))
        XCTAssertNil(departures["LW-1108"]?.expectedArrival, "The feed gives no estimate at Union")
        XCTAssertEqual(departures["LW-1256"]?.status, .onTime)
        XCTAssertEqual(departures["LW-1256"]?.expectedDeparture, at(7, 14))
        XCTAssertEqual(departures["LW-1256"]?.expectedArrival, at(7, 48))
        XCTAssertEqual(departures["LW-1308"]?.status, .scheduled, "NO_DATA at Oakville is no live data")
        XCTAssertEqual(departures["LW-1858"]?.status, .scheduled, "A train the feed leaves out is Scheduled")
        let trains = Set(departures.keys)

        try await replay.serve("tripupdates-0701")
        clock.advance(minutes: 1)
        (freshness, departures) = try await resolve(repository, now: clock.now)
        XCTAssertEqual(freshness, .live(updatedAt: at(7, 1)))
        XCTAssertEqual(departures["LW-1108"]?.status, .delayed(minutes: 9, reportedAt: at(7, 1)))
        XCTAssertEqual(departures["LW-1108"]?.expectedDeparture, at(7, 30))
        XCTAssertEqual(Set(departures.keys), trains, "A moving estimate never makes a new trip")

        try await replay.serve("tripupdates-0702")
        clock.advance(minutes: 1)
        (freshness, departures) = try await resolve(repository, now: clock.now)
        XCTAssertEqual(freshness, .live(updatedAt: at(7, 2)))
        XCTAssertEqual(departures["LW-1108"]?.status, .onTime)
        XCTAssertEqual(departures["LW-1108"]?.expectedDeparture, at(7, 22))
        XCTAssertEqual(Set(departures.keys), trains)
    }

    func testCancelledSkippedAndCarriedDelays() async throws {
        let clock = FixedClock(now: at(7, 2, 30))
        let (_, departures) = try await resolve(repository(FeedReplay("tripupdates-0702"), clock: clock), now: clock.now)
        XCTAssertEqual(departures["LW-1858"]?.status, .cancelled(reportedAt: at(7, 0, 40)))
        XCTAssertNil(departures["LW-1858"]?.expectedDeparture)
        XCTAssertEqual(departures["LW-1758"]?.status, .stopSkipped)
        XCTAssertEqual(departures["LW-1308"]?.status, .delayed(minutes: 4, reportedAt: at(7, 2)), "Appleby's delay carries on")
        XCTAssertEqual(departures["LW-1308"]?.expectedDeparture, at(7, 55))
        XCTAssertNil(departures["LW-1308"]?.expectedArrival, "A carried delay is no arrival estimate (Q3)")
        XCTAssertEqual(departures["LW-1860"]?.status, .delayed(minutes: 3, reportedAt: at(7, 2)))
        XCTAssertEqual(departures["LW-1258"]?.status, .scheduled, "An estimate at Union only is no departure estimate")
        XCTAssertNil(departures["LW-1258"]?.expectedArrival)
    }

    /// Stale: the 7:02 feed read at 7:05:30. Every badge falls back to Scheduled at its scheduled time; a reported
    /// cancellation or skipped stop stands (D13).
    func testStaleFeedIsNeverLive() async throws {
        let clock = FixedClock(now: at(7, 5, 30))
        let (freshness, departures) = try await resolve(repository(FeedReplay("tripupdates-0702"), clock: clock), now: clock.now)
        XCTAssertEqual(freshness, .stale(lastReported: at(7, 2)))
        XCTAssertEqual(departures["LW-1108"]?.status, .scheduled)
        XCTAssertNil(departures["LW-1108"]?.expectedDeparture)
        XCTAssertEqual(departures["LW-1256"]?.status, .scheduled)
        XCTAssertNil(departures["LW-1256"]?.expectedArrival)
        XCTAssertEqual(departures["LW-1858"]?.status, .cancelled(reportedAt: at(7, 0, 40)))
        XCTAssertEqual(departures["LW-1758"]?.status, .stopSkipped)
        XCTAssertFalse(departures.values.contains { $0.status == .onTime }, "Cached data never shows On time")
    }

    /// Offline after a good feed: the last feed is kept as offline, never as live (D13, TT-115).
    func testOfflineKeepsTheLastFeedAsOffline() async throws {
        let clock = TestClock(now: at(7, 2, 30))
        let replay = try FeedReplay("tripupdates-0702")
        let repository = try repository(replay, clock: clock)
        _ = try await resolve(repository, now: clock.now)

        await replay.goOffline()
        clock.advance(minutes: 1)
        let (freshness, departures) = try await resolve(repository, now: clock.now)
        XCTAssertEqual(freshness, .offline(lastUpdated: at(7, 2)))
        XCTAssertEqual(departures["LW-1108"]?.status, .scheduled)
        XCTAssertEqual(departures["LW-1858"]?.status, .cancelled(reportedAt: at(7, 0, 40)))
        XCTAssertFalse(departures.values.contains { $0.status == .onTime })
        XCTAssertTrue(departures.values.allSatisfy { $0.trip.platform == .pending })
    }

    func testOfflineBeforeAnyFeedSaysOffline() async throws {
        let replay = try FeedReplay("tripupdates-0700")
        await replay.goOffline()
        let clock = FixedClock(now: at(7, 0, 30))
        let (freshness, departures) = try await resolve(repository(replay, clock: clock), now: clock.now)
        XCTAssertEqual(freshness, .offline(lastUpdated: nil))
        XCTAssertTrue(departures.values.allSatisfy { $0.status == .scheduled })
    }

    /// The Schedule screen and the Trip details sheet both poll every 30 s; they share one fetch every 20 s.
    func testCallersShareOneFetch() async throws {
        let clock = TestClock(now: at(7, 0, 30))
        let replay = try FeedReplay("tripupdates-0700")
        let store = GTFSRealtimeStore(clock: clock, download: { try await replay.download() })
        _ = await store.latest()
        _ = await store.latest()
        var downloads = await replay.downloads
        XCTAssertEqual(downloads, 1)
        clock.advance(minutes: 1)
        _ = await store.latest()
        downloads = await replay.downloads
        XCTAssertEqual(downloads, 2)
    }

    /// Trip details (D32): each stop shows the feed's own estimate or skip, and nothing where the feed says nothing.
    func testTripDetailsStops() async throws {
        let clock = FixedClock(now: at(7, 0, 30))
        let stops = try await repository(FeedReplay("tripupdates-0700"), clock: clock)
            .stops(for: TripKey(serviceDay: monday, tripId: "20261109-LW-1108"), on: route)
        XCTAssertEqual(stops.map(\.station.id), ["OA", "CL", "PO", "LO", "MI", "EX", "UN"])
        XCTAssertEqual(stops[0].expected, at(7, 26))
        XCTAssertEqual(stops[1].expected, at(7, 33))
        XCTAssertNil(stops[2].expected)
        XCTAssertNil(stops[6].expected)

        let skipped = try await repository(FeedReplay("tripupdates-0702"), clock: FixedClock(now: at(7, 2, 30)))
            .stops(for: TripKey(serviceDay: monday, tripId: "20261109-LW-1758"), on: route)
        XCTAssertEqual(skipped.map(\.isSkipped), [true, false, false])
    }
}
