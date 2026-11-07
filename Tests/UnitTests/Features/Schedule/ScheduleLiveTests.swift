import XCTest
@testable import TrainTimes

/// TT-131: while Schedule is in the foreground it polls live status, and each refresh keeps the cards' identity and the
/// scroll position (D9, D14). The feed is the replay of the 7:00 and 7:01 AM samples (`GTFSRealtimeReplayTests`).
final class ScheduleLiveTests: XCTestCase {
    @MainActor
    func testPollingFollowsTheFeedAndKeepsTheScroll() async throws {
        let monday = ServiceDay(year: 2026, month: 11, day: 9)
        let clock = TestClock(now: monday.date(hour: 7, minute: 0).addingTimeInterval(30))
        let replay = try FeedReplay("tripupdates-0700")
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let route = Route(
            from: Station(id: "OA", name: "Oakville GO"),
            to: Station(id: "UN", name: "Union Station GO"),
            line: Line(id: "LW", name: "Lakeshore West", colorHex: nil)
        )
        let model = ScheduleViewModel(
            route: route,
            repository: try GTFSScheduleRepository.replaying(replay, clock: clock, directory: directory),
            clock: clock,
            favourites: Favourites(defaults: .ephemeral())
        )
        await model.loadIfNeeded()
        let key = TripKey(serviceDay: monday, tripId: "20261109-LW-1108")
        func status() -> TrainStatus? { model.departures.first { $0.id == key }?.status }
        XCTAssertEqual(status(), .delayed(minutes: 5, reportedAt: monday.date(hour: 7, minute: 0)))
        let trains = Set(model.departures.map(\.id))
        let scroll = model.scrollRequest

        try await replay.serve("tripupdates-0701")
        clock.advance(minutes: 1)
        let increased = TrainStatus.delayed(minutes: 9, reportedAt: monday.date(hour: 7, minute: 1))
        let polling = Task { await model.pollLiveStatus(every: .milliseconds(10)) }
        defer { polling.cancel() }
        for _ in 0..<500 where status() != increased {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(status(), increased)
        XCTAssertEqual(model.freshness, .live(updatedAt: monday.date(hour: 7, minute: 1)))
        XCTAssertEqual(Set(model.departures.map(\.id)), trains, "Same trains, same identities")
        XCTAssertEqual(model.scrollRequest, scroll, "A refresh never scrolls")
    }
}
