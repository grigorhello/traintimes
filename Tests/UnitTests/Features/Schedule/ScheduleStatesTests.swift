import XCTest
@testable import TrainTimes

/// TT-115: loading, stale, offline, future day, no direct trains and no direct connection. A train with no live status
/// reads On time, and the status row says when the data is stale (D49); only offline keeps the grey Scheduled badge.
@MainActor
final class ScheduleStatesTests: XCTestCase {
    private let formatter = TimeFormatter(format: .twelveHour)

    private func repository() throws -> FixtureScheduleRepository {
        try FixtureScheduleRepository(bundle: Bundle(for: Self.self))
    }

    func testLoadingUntilTheFirstTimetableArrives() async throws {
        let repository = try repository()
        let model = ScheduleViewModel(route: repository.route, repository: repository, clock: FixedClock(now: repository.now))
        XCTAssertEqual(model.content, .loading)
        XCTAssertEqual(model.freshnessMode(formatter), .loading)
        await model.loadIfNeeded()
        XCTAssertEqual(model.content, .timeline)
    }

    func testStaleFallsBackToScheduledTimes() async throws {
        let model = try await ScheduleViewModel.loadedFixture(minutesLater: 5)
        XCTAssertEqual(model.content, .timeline)
        XCTAssertEqual(model.freshnessMode(formatter), .stale(lastReported: "7:21 AM"))
        XCTAssertEqual(model.cards(formatter).map(\.status), Array(repeating: .onTime, count: 4))
        XCTAssertEqual(model.statusRowMode(formatter), .stale(lastReported: "7:21 AM"))
        XCTAssertTrue(model.departures.allSatisfy { $0.expectedDeparture == nil }, "Cards move back to scheduled positions")
    }

    func testOfflineKeepsTheCachedScheduleUsable() async throws {
        let model = try await ScheduleViewModel.loadedFixture(.offline)
        XCTAssertEqual(model.content, .timeline)
        XCTAssertEqual(model.freshnessMode(formatter), .offline(lastUpdated: "6:52 AM"))
        let cards = model.cards(formatter)
        XCTAssertEqual(cards.map(\.status), Array(repeating: .scheduled, count: 4), "Offline keeps the grey Scheduled badge")
        XCTAssertEqual(model.statusRowMode(formatter), .offline(lastUpdated: "6:52 AM"))
        XCTAssertEqual(Set(cards.map(\.platform)), ["Platform pending"])
        XCTAssertNotNil(model.layout.nowY, "The Now line still follows the device clock")
        XCTAssertEqual(cards.first?.relativeTime, "in 11 min")
    }

    func testFutureDayShowsScheduledTimesOnly() async throws {
        let model = try await ScheduleViewModel.loadedFixture(dayIndex: 1)
        XCTAssertEqual(model.content, .timeline)
        XCTAssertEqual(model.freshnessMode(formatter), .scheduledOnly(day: "Fri, Nov 6"))
        XCTAssertEqual(model.cards(formatter).map(\.status), Array(repeating: .onTime, count: 4))
        XCTAssertNil(model.statusRowMode(formatter), "Timetable-only data says nothing in the status row")
        XCTAssertNil(model.layout.nowY)
        XCTAssertNil(model.nextDepartureId)
        XCTAssertEqual(model.layout.initialScrollOffset, 0, "The timeline starts at the day's first train")
    }

    func testNoTrainsOffersTheNextDayWithTrains() async throws {
        let model = try await ScheduleViewModel.loadedFixture(dayIndex: 3)
        XCTAssertEqual(
            model.content,
            .noTrains(
                title: "No direct trains on Sunday",
                message: "There are no direct trains between Oakville and Union on Sun, Nov 8.",
                showDay: "Show Monday"
            )
        )
        await model.showNextDayWithTrains()
        XCTAssertEqual(model.selectedDay, ServiceDay(year: 2026, month: 11, day: 9))
        XCTAssertEqual(model.content, .timeline)
        XCTAssertEqual(model.scrollRequest, 3, "Monday starts at its first train")
    }

    func testNoTrainsWithoutALaterDayHasNoAction() async throws {
        let repository = try repository()
        let reverse = Route(from: repository.route.to, to: repository.route.from, line: repository.route.line)
        let model = ScheduleViewModel(route: reverse, repository: repository, clock: FixedClock(now: repository.now))
        await model.loadIfNeeded()
        XCTAssertEqual(
            model.content,
            .noTrains(
                title: "No direct trains on Thursday",
                message: "There are no direct trains between Union and Oakville on Thu, Nov 5.",
                showDay: nil
            )
        )
    }

    func testStationsWithoutACommonLineHaveNoDirectConnection() async throws {
        let repository = try repository()
        let route = Route(from: repository.route.from, to: Station(id: "BA", name: "Barrie"), line: nil)
        let model = ScheduleViewModel(route: route, repository: repository, clock: FixedClock(now: repository.now))
        XCTAssertEqual(model.content, .noConnection)
        await model.loadIfNeeded()
        XCTAssertEqual(model.content, .noConnection)
    }

    /// D13 still holds in the domain: only fresh live data for today resolves to On time. The cards' badge is a
    /// presentation choice (D49) and reads On time without live data too, except offline.
    func testOnlyFreshLiveDataShowsOnTime() async throws {
        let stale = try await ScheduleViewModel.loadedFixture(minutesLater: 5)
        let offline = try await ScheduleViewModel.loadedFixture(.offline)
        let futureDay = try await ScheduleViewModel.loadedFixture(dayIndex: 1)
        for model in [stale, offline, futureDay] {
            XCTAssertFalse(model.departures.contains { $0.status == .onTime })
        }
        let live = try await ScheduleViewModel.loadedFixture()
        XCTAssertTrue(live.departures.contains { $0.status == .onTime })
        XCTAssertTrue(live.cards(formatter).contains { $0.status == .onTime })
    }
}
