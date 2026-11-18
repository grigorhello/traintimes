import XCTest
@testable import TrainTimes

/// TT-225: GO's platforms come from its departures board for the route's origin, relayed by the alert server, and land
/// on today's cards by GO's trip number.
final class PlatformStoreTests: XCTestCase {
    private let monday = ServiceDay(year: 2026, month: 11, day: 9)
    private let route = Route(from: Station(id: "OA", name: "Oakville GO"), to: Station(id: "UN", name: "Union Station GO"), line: nil)
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// The alert server's answer for Oakville: 1108 posted, 1256 planned (the server already picked one), 1308 none.
    private let oakville = Data("""
    {"fetchedAt":1762689600,"trips":[
      {"trip":"1108","line":"LW","departure":"2026-11-09 07:21:00","platform":"3"},
      {"trip":"1256","line":"LW","departure":"2026-11-09 07:14:00","platform":"9 & 10"},
      {"trip":"1308","line":"LW","departure":"2026-11-09 07:51:00","platform":null}
    ]}
    """.utf8)

    private final class Calls: @unchecked Sendable {
        // Written only from the store's actor, read after it.
        var stops: [String] = []
    }

    func testDecodesTheBoardAndMatchesGTFSTripIds() throws {
        let board = try PlatformStore.decode(oakville)
        XCTAssertEqual(board.platforms, ["1108": "3", "1256": "9 & 10"])
        XCTAssertEqual(board.platform(forTrip: "20261109-LW-1108"), "3")
        XCTAssertNil(board.platform(forTrip: "20261109-LW-1308"))
    }

    func testAStationIsReusedFor20Seconds() async {
        let clock = TestClock(now: monday.date(hour: 7, minute: 0))
        let calls = Calls()
        let data = oakville
        let store = PlatformStore(clock: clock) { stop in
            calls.stops.append(stop)
            return data
        }
        _ = await store.board(at: "OA")
        _ = await store.board(at: "OA")
        XCTAssertEqual(calls.stops, ["OA"])
        clock.advance(seconds: 21)
        XCTAssertEqual(await store.board(at: "OA")?.platforms["1108"], "3")
        XCTAssertEqual(calls.stops, ["OA", "OA"])
    }

    private func departures(platforms: PlatformStore, isToday: Bool = true) async throws -> (LiveSnapshot, [String: Departure]) {
        let clock = FixedClock(now: monday.date(hour: 7, minute: 0).addingTimeInterval(30))
        let repository = try GTFSScheduleRepository.replaying(
            FeedReplay("tripupdates-0700"), platforms: platforms, clock: clock, directory: directory
        )
        let trips = try await repository.trips(for: route, on: monday)
        let live = try await repository.liveStatus(for: route, on: monday)
        let resolved = Departure.resolve(trips, live: live, freshness: Freshness(live, now: clock.now), isToday: isToday)
        return (live, Dictionary(uniqueKeysWithValues: resolved.map { (String($0.id.tripId.dropFirst(9)), $0) }))
    }

    func testTodaysCardsShowThePostedPlatform() async throws {
        let data = oakville
        let (live, departures) = try await departures(platforms: PlatformStore { _ in data })
        XCTAssertTrue(live.hasPlatformSource)
        XCTAssertEqual(departures["LW-1108"]?.trip.platform, .published("3"))
        XCTAssertEqual(departures["LW-1256"]?.trip.platform, .published("9 & 10"))
        XCTAssertEqual(departures["LW-1308"]?.trip.platform, .pending, "No platform posted yet")
    }

    func testAFailedBoardLeavesTheDashAndNoSource() async throws {
        let (live, departures) = try await departures(platforms: PlatformStore { _ in throw URLError(.badServerResponse) })
        XCTAssertFalse(live.hasPlatformSource)
        XCTAssertEqual(departures["LW-1108"]?.trip.platform, .pending)
    }

    func testAnotherDayKeepsTheDash() async throws {
        let data = oakville
        let (_, departures) = try await departures(platforms: PlatformStore { _ in data }, isToday: false)
        XCTAssertEqual(departures["LW-1108"]?.trip.platform, .pending)
    }

    func testOfflineKeepsPlatformPending() {
        let day = monday
        let trip = Trip(
            key: TripKey(serviceDay: day, tripId: "20261109-LW-1108"),
            scheduledDeparture: day.date(hour: 7, minute: 21), scheduledArrival: day.date(hour: 7, minute: 55),
            platform: .pending, tags: []
        )
        let live = LiveSnapshot(updatedAt: day.date(hour: 7, minute: 0), isOffline: true, platforms: [trip.key.tripId: "3"])
        let resolved = Departure.resolve([trip], live: live, freshness: .offline(lastUpdated: nil), isToday: true)
        XCTAssertEqual(resolved.first?.trip.platform, .pending)
    }
}
