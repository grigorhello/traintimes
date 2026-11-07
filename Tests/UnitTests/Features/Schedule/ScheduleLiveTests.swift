import XCTest
@testable import TrainTimes

/// TT-131: while Schedule is in the foreground it polls live status, and each refresh keeps the cards' identity and the
/// scroll position (D9, D14). The feed is the replay of the 7:00 and 7:01 AM samples (`GTFSRealtimeReplayTests`).
final class ScheduleLiveTests: XCTestCase {
    private let monday = ServiceDay(year: 2026, month: 11, day: 9)

    /// Schedule for Oakville GO to Union Station GO, loaded at 7:00:30 AM with the 7:00 sample.
    @MainActor
    private func loadedModel(_ replay: FeedReplay, clock: TestClock) async throws -> ScheduleViewModel {
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
        return model
    }

    @MainActor
    func testPollingFollowsTheFeedAndKeepsTheScroll() async throws {
        let clock = TestClock(now: monday.date(hour: 7, minute: 0).addingTimeInterval(30))
        let replay = try FeedReplay("tripupdates-0700")
        let model = try await loadedModel(replay, clock: clock)
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

    /// Back in the app after five minutes away on a slow connection: the old feed shows as stale, with Scheduled badges,
    /// while the new one downloads, never as live (D13).
    @MainActor
    func testDataLeftOnScreenAgesBeforeTheFetch() async throws {
        let clock = TestClock(now: monday.date(hour: 7, minute: 0).addingTimeInterval(30))
        let replay = try FeedReplay("tripupdates-0700")
        let model = try await loadedModel(replay, clock: clock)
        XCTAssertEqual(model.freshness, .live(updatedAt: monday.date(hour: 7, minute: 0)))

        await replay.hold()
        clock.advance(minutes: 5)
        let stale = Freshness.stale(lastReported: monday.date(hour: 7, minute: 0))
        let polling = Task { await model.pollLiveStatus(every: .milliseconds(10)) }
        for _ in 0..<500 where model.freshness != stale {
            try await Task.sleep(for: .milliseconds(10))
        }
        let downloads = await replay.downloads
        XCTAssertEqual(downloads, 1, "The new feed is still downloading")
        XCTAssertEqual(model.freshness, stale)
        let key = TripKey(serviceDay: monday, tripId: "20261109-LW-1108")
        XCTAssertEqual(model.departures.first { $0.id == key }?.status, .scheduled)
        XCTAssertFalse(model.departures.contains { $0.status == .onTime })
        polling.cancel()
        await replay.release()
    }
}
