import XCTest
@testable import TrainTimes

/// TT-132: the Notice chip follows today's notices for the route's line; dismissing one hides it, after a
/// relaunch too, until a notice with a new id arrives (D37). The feed is the replay of the Alerts samples
/// (`LineNoticeReplayTests`).
final class ScheduleLineNoticeTests: XCTestCase {
    private let monday = ServiceDay(year: 2026, month: 11, day: 9)

    @MainActor
    private func loadedModel(_ alerts: FeedReplay, clock: TestClock, defaults: UserDefaults) async throws -> ScheduleViewModel {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let route = Route(
            from: Station(id: "OA", name: "Oakville GO"),
            to: Station(id: "UN", name: "Union Station GO"),
            line: Line(id: "LW", name: "Lakeshore West", colorHex: "#98002e")
        )
        let model = ScheduleViewModel(
            route: route,
            repository: try GTFSScheduleRepository.replaying(nil, alerts: alerts, clock: clock, directory: directory),
            clock: clock,
            dismissedNotices: DismissedNotices(defaults: defaults)
        )
        await model.loadIfNeeded()
        return model
    }

    @MainActor
    func testDismissingHidesTheNoticeUntilANewIdArrives() async throws {
        let clock = TestClock(now: monday.date(hour: 7, minute: 2).addingTimeInterval(30))
        let alerts = try FeedReplay("alerts-0702")
        let defaults = UserDefaults.ephemeral()
        let model = try await loadedModel(alerts, clock: clock, defaults: defaults)
        XCTAssertEqual(model.lineNotices.map(\.id), ["LW-1001"])
        XCTAssertFalse(model.departures.contains { if case .cancelled = $0.status { true } else { false } })
        let row = try XCTUnwrap(model.noticeRows(TimeFormatter(format: .twelveHour)).first)
        XCTAssertEqual(row.title, "Lakeshore West notice")
        XCTAssertEqual(row.reported, "Reported at 7:00 AM")

        model.dismissNotice("LW-1001")
        XCTAssertTrue(model.lineNotices.isEmpty)
        await model.refresh()
        XCTAssertTrue(model.lineNotices.isEmpty, "Still in the feed, still dismissed")

        let relaunched = try await loadedModel(alerts, clock: clock, defaults: defaults)
        XCTAssertTrue(relaunched.lineNotices.isEmpty, "Dismissed on device, so a relaunch keeps it hidden")

        try await alerts.serve("alerts-0705")
        clock.advance(minutes: 3)
        await relaunched.refresh()
        XCTAssertEqual(relaunched.lineNotices.map(\.id), ["LW-1002"], "A new notice id shows again")
    }

    /// Another day shows scheduled times only, with no notice.
    @MainActor
    func testAnotherDayHasNoNotice() async throws {
        let model = try await ScheduleViewModel.loadedFixture(.delayed)
        XCTAssertEqual(model.lineNotices.count, 1)
        await model.select(model.days[1])
        XCTAssertTrue(model.lineNotices.isEmpty)
        // The Alerts tab and its notice sheet still list today's notice (TT-143).
        XCTAssertEqual(model.todayNotices.count, 1)
        XCTAssertEqual(model.noticeRows(TimeFormatter(format: .twelveHour)).count, 1)
        await model.backToNow()
        XCTAssertEqual(model.lineNotices.count, 1)
        XCTAssertEqual(model.todayNotices, model.lineNotices)
    }

    /// GO's notices start when they were posted (D91): one from another day says the day too.
    @MainActor
    func testANoticeFromAnotherDaySaysTheDay() async throws {
        let clock = TestClock(now: monday.date(hour: 7, minute: 2).addingTimeInterval(30))
        let model = try await loadedModel(FeedReplay("alerts-go-real"), clock: clock, defaults: .ephemeral())
        XCTAssertEqual(
            model.noticeRows(TimeFormatter(format: .twelveHour)).map(\.reported),
            ["Reported Nov 7 at 1:57 PM", "Reported at 6:40 AM"]
        )
        XCTAssertEqual(model.noticeRows(TimeFormatter(format: .twentyFourHour)).first?.reported, "Reported Nov 7 at 13:57")
        XCTAssertFalse(model.departures.contains { if case .cancelled = $0.status { true } else { false } })
    }
}
