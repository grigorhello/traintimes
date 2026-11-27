import XCTest
@testable import TrainTimes

/// TT-251 (D127): the stops a trip still has ahead in the TripUpdates feed, from the TT-131 replays (Oakville to Union,
/// Monday Nov 9).
final class LiveStopsAheadTests: XCTestCase {
    private let monday = ServiceDay(year: 2026, month: 11, day: 9)
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

    private func key(_ train: String) -> TripKey { TripKey(serviceDay: monday, tripId: "20261109-\(train)") }

    func testTheStopsGOStillLists() async throws {
        let clock = TestClock(now: at(7, 2, 30))
        let replay = try FeedReplay("tripupdates-0702")
        let repository = try GTFSScheduleRepository.replaying(replay, clock: clock, directory: directory)

        let cancelled = try await XCTUnwrapAsync(await repository.stopsAhead(of: key("LW-1858")))
        XCTAssertTrue(cancelled.isCancelled)
        XCTAssertTrue(cancelled.isFresh)

        let skipping = try await XCTUnwrapAsync(await repository.stopsAhead(of: key("LW-1758")))
        XCTAssertFalse(skipping.skipped.isEmpty, "the skipped stop is told apart")
        XCTAssertTrue(skipping.skipped.allSatisfy { !skipping.lists($0) }, "and not listed")

        let timed = try await XCTUnwrapAsync(await repository.stopsAhead(of: key("LW-1256")))
        XCTAssertEqual(timed.stops.first?.time, at(7, 14), "the feed's own time")
        XCTAssertFalse(timed.isCancelled)

        let missing = await repository.stopsAhead(of: key("LW-9999"))
        XCTAssertNil(missing, "no update: nothing to say")

        clock.advance(minutes: 4)
        let stale = try await XCTUnwrapAsync(await repository.stopsAhead(of: key("LW-1256")))
        XCTAssertFalse(stale.isFresh, "a feed over 3 min old is not fresh")
    }

    func testNothingWithoutALiveFeed() async throws {
        let repository = try GTFSScheduleRepository.replaying(nil, clock: TestClock(now: at(7, 2)), directory: directory)
        let stops = await repository.stopsAhead(of: key("LW-1256"))
        XCTAssertNil(stops)
    }

    private func XCTUnwrapAsync<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) async throws -> T {
        try XCTUnwrap(value, file: file, line: line)
    }
}
