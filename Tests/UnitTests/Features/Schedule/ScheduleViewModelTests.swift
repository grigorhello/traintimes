import SwiftUI
import XCTest
@testable import TrainTimes

@MainActor
final class ScheduleViewModelTests: XCTestCase {
    private let formatter = TimeFormatter(format: .twelveHour)
    private let thursday = ServiceDay(year: 2026, month: 11, day: 5)

    func testTodayIsSelectedFirstWithTheRouteAndLiveFreshness() async throws {
        let model = try await ScheduleViewModel.loadedFixture()
        XCTAssertEqual(model.routeTitle, "Oakville to Union")
        XCTAssertEqual(model.route?.line?.name, "Lakeshore West")
        XCTAssertEqual(model.days.count, 14)
        XCTAssertEqual(model.days.first, thursday)
        XCTAssertEqual(model.days[3], ServiceDay(year: 2026, month: 11, day: 8))
        XCTAssertEqual(model.selectedDay, thursday)
        XCTAssertTrue(model.isToday)
        XCTAssertEqual(model.departures.count, 4)
        XCTAssertNotNil(model.layout.nowY)
        XCTAssertEqual(model.freshnessMode(formatter), .live(updated: "Updated just now"))
        XCTAssertNil(model.statusRowMode(formatter), "Live data says nothing in the status row (D49)")
        XCTAssertEqual(model.scrollRequest, 1, "The first load scrolls to Now")
    }

    func testAnotherDayShowsScheduledTimesOnlyWithoutNowLine() async throws {
        let model = try await ScheduleViewModel.loadedFixture(dayIndex: 3)
        XCTAssertFalse(model.isToday)
        XCTAssertEqual(model.freshnessMode(formatter), .scheduledOnly(day: "Sun, Nov 8"))
        XCTAssertNil(model.layout.nowY)
        XCTAssertTrue(model.departures.isEmpty, "The fixtures run no trains on Sundays")
        XCTAssertEqual(model.scrollRequest, 2, "A new day starts at its first train")
    }

    /// D49: there is no Now button; tapping the Schedule tab again returns to today and now in one tap.
    func testReTappingTheScheduleTabReturnsToTodayAndNow() async throws {
        let model = try await ScheduleViewModel.loadedFixture(dayIndex: 3)
        await model.backToNow()
        XCTAssertEqual(model.selectedDay, thursday)
        XCTAssertTrue(model.isToday)
        XCTAssertEqual(model.departures.count, 4)
        XCTAssertNotNil(model.layout.nowY)
        XCTAssertEqual(model.freshnessMode(formatter), .live(updated: "Updated just now"))
        XCTAssertEqual(model.scrollRequest, 3)
    }

    /// TT-153: back in the app the next morning, with the app still in memory, Schedule opens on the new Today with the
    /// Now line and the next train, not on yesterday (D30, D27).
    func testANewServiceDayMovesTheScheduleToToday() async throws {
        let repository = try FixtureScheduleRepository(bundle: Bundle(for: ScheduleViewModelTests.self))
        let clock = TestClock(now: repository.now)
        let model = ScheduleViewModel(route: repository.route, repository: repository, clock: clock)
        await model.loadIfNeeded()
        XCTAssertEqual(model.selectedDay, thursday)
        let scroll = model.scrollRequest

        clock.advance(minutes: 24 * 60)
        let polling = Task { await model.pollLiveStatus(every: .milliseconds(10)) }
        defer { polling.cancel() }
        for _ in 0..<500 where model.scrollRequest == scroll {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.selectedDay, thursday.adding(days: 1))
        XCTAssertTrue(model.isToday)
        XCTAssertEqual(model.days.first, model.selectedDay, "Today is the strip's first day and selected")
        XCTAssertNotNil(model.layout.nowY)
        XCTAssertEqual(model.scrollRequest, scroll + 1, "The new day scrolls to Now")
    }

    private func fixtureModel(at now: Date) throws -> (model: ScheduleViewModel, clock: TestClock) {
        let repository = try FixtureScheduleRepository(bundle: Bundle(for: ScheduleViewModelTests.self))
        let clock = TestClock(now: now)
        return (ScheduleViewModel(route: repository.route, repository: repository, clock: clock), clock)
    }

    /// TT-159, D52: the screen turns to the next day at midnight, not at the 3:00 AM service-day cutoff. A rider on Today
    /// moves to the new Today, which scrolls to Now at its top, and the strip's first tile is that day.
    func testTheDayTurnsAtMidnightAndTheNewDayStartsFromTheTop() async throws {
        let (model, clock) = try fixtureModel(at: thursday.date(hour: 23, minute: 58))
        await model.loadIfNeeded()
        XCTAssertEqual(model.selectedDay, thursday)
        let scroll = model.scrollRequest

        clock.advance(minutes: 3)
        await model.rollOverIfNeeded()
        let friday = thursday.adding(days: 1)
        XCTAssertEqual(model.selectedDay, friday)
        XCTAssertTrue(model.isToday)
        XCTAssertEqual(model.days.first, friday)
        XCTAssertEqual(model.departures.count, 4)
        XCTAssertEqual(model.scrollRequest, scroll + 1)
        XCTAssertNotNil(model.layout.nowY)
        XCTAssertEqual(model.layout.initialScrollOffset, 0, accuracy: 0.5, "Now is the first thing on the new day: from the top")

        await model.rollOverIfNeeded()
        XCTAssertEqual(model.scrollRequest, scroll + 1, "The same midnight is acted on once")
    }

    /// TT-159: the app opened at 12:01 AM shows the actual day, selected in the strip, though GO still counts the minute
    /// as the previous service day.
    func testOpeningTheAppJustAfterMidnightShowsTheActualDay() async throws {
        let (model, clock) = try fixtureModel(at: thursday.date(hour: 0, minute: 1))
        let friday = thursday.adding(days: 1)
        XCTAssertEqual(ServiceDay(containing: clock.now), thursday, "GO's service day runs to 3:00 AM")
        XCTAssertEqual(model.selectedDay, friday)
        await model.loadIfNeeded()
        XCTAssertTrue(model.isToday)
        XCTAssertEqual(model.days.first, friday)
        XCTAssertEqual(model.departures.count, 4)
        XCTAssertEqual(model.layout.initialScrollOffset, 0, accuracy: 0.5)
    }

    /// TT-159: a rider browsing another day stays there at midnight; only the strip shifts by one.
    func testMidnightLeavesARiderBrowsingAnotherDayWhereTheyAre() async throws {
        let (model, clock) = try fixtureModel(at: thursday.date(hour: 23, minute: 58))
        await model.loadIfNeeded()
        let saturday = thursday.adding(days: 2)
        await model.select(saturday)
        let scroll = model.scrollRequest

        clock.advance(minutes: 3)
        await model.rollOverIfNeeded()
        XCTAssertEqual(model.selectedDay, saturday)
        XCTAssertFalse(model.isToday)
        XCTAssertEqual(model.days.first, thursday.adding(days: 1))
        XCTAssertEqual(model.scrollRequest, scroll, "No scroll: the rider did not move")
    }

    /// TT-159: the day that has just become Today, if the rider was already looking at it, turns into Today with Now.
    func testMidnightOnTomorrowsTimelineMakesItToday() async throws {
        let (model, clock) = try fixtureModel(at: thursday.date(hour: 23, minute: 58))
        await model.loadIfNeeded()
        let friday = thursday.adding(days: 1)
        await model.select(friday)
        XCTAssertFalse(model.isToday)
        XCTAssertNil(model.layout.nowY)
        let scroll = model.scrollRequest

        clock.advance(minutes: 3)
        await model.rollOverIfNeeded()
        XCTAssertEqual(model.selectedDay, friday)
        XCTAssertTrue(model.isToday)
        XCTAssertNotNil(model.layout.nowY, "Reloaded as Today, with the Now line")
        XCTAssertEqual(model.scrollRequest, scroll + 1)
    }

    /// TT-159: a scroll request is followed by two rescrolls, so a first scroll that ran before the content was laid out
    /// still lands.
    func testAScrollRequestIsFollowedByTwoRescrolls() async throws {
        let model = try await ScheduleViewModel.loadedFixture()
        XCTAssertEqual(model.rescrollRequest, 0)
        for _ in 0..<300 where model.rescrollRequest < 2 {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.rescrollRequest, 2)
    }

    /// TT-158: when Mock time changes the clock, the timeline starts again on the new today and its present, as a relaunch would.
    func testRestartMovesToTheNewTodayAndScrollsToNow() async throws {
        let repository = try FixtureScheduleRepository(bundle: Bundle(for: ScheduleViewModelTests.self))
        let clock = TestClock(now: repository.now)
        let model = ScheduleViewModel(route: repository.route, repository: repository, clock: clock)
        await model.loadIfNeeded()
        await model.select(model.days[3])
        let scroll = model.scrollRequest

        clock.advance(minutes: 2 * 24 * 60)
        await model.restart()
        XCTAssertEqual(model.selectedDay, thursday.adding(days: 2))
        XCTAssertTrue(model.isToday)
        XCTAssertEqual(model.now, clock.now)
        XCTAssertNotNil(model.layout.nowY)
        XCTAssertEqual(model.scrollRequest, scroll + 1)
    }

    /// On today the tab re-tap scrolls to the present again.
    func testBackToNowScrollsToThePresentOnToday() async throws {
        let model = try await ScheduleViewModel.loadedFixture()
        await model.backToNow()
        XCTAssertEqual(model.scrollRequest, 2)
        XCTAssertTrue(model.isToday)
    }

    /// The first scroll ran on estimated card sizes, so one more follows once every card is measured (D49).
    func testScrollSettlesOnceEveryCardIsMeasured() async throws {
        let model = try await ScheduleViewModel.loadedFixture()
        XCTAssertEqual(model.settleRequest, 0)
        let ids = model.departures.map(\.id)
        for id in ids.dropLast() { model.setCardSize(TimelineCardSize(height: 110, anchor: 35), for: id) }
        XCTAssertEqual(model.settleRequest, 0, "One card is still unmeasured")
        model.setCardSize(TimelineCardSize(height: 110, anchor: 35), for: try XCTUnwrap(ids.last))
        XCTAssertEqual(model.settleRequest, 1)
        model.setCardSize(TimelineCardSize(height: 140, anchor: 35), for: ids[0])
        XCTAssertEqual(model.settleRequest, 1, "Only a scroll request asks for another")
    }

    func testRefreshKeepsCardIdentityAndScrollPosition() async throws {
        let model = try await ScheduleViewModel.loadedFixture()
        let ids = model.departures.map(\.id)
        await model.refresh()
        XCTAssertEqual(model.departures.map(\.id), ids)
        XCTAssertEqual(model.scrollRequest, 1, "A refresh never scrolls")
    }

    func testFreshnessFollowsTheFeedAge() async throws {
        let recent = try await ScheduleViewModel.loadedFixture(minutesLater: 2)
        XCTAssertEqual(recent.freshnessMode(formatter), .live(updated: "Updated 2 min ago"))
        let stale = try await ScheduleViewModel.loadedFixture(minutesLater: 5)
        XCTAssertEqual(stale.freshnessMode(formatter), .stale(lastReported: "7:21 AM"))
    }

    func testSwapIsExplicitAndReversesTheRoute() async throws {
        let model = try await ScheduleViewModel.loadedFixture()
        XCTAssertEqual(model.routeTitle, "Oakville to Union")
        await model.swap()
        XCTAssertEqual(model.routeTitle, "Union to Oakville")
        XCTAssertEqual(model.route?.line?.name, "Lakeshore West")
    }

    /// Without Fixtures.json (Release builds, D20) there is no route until the route form lands (TT-120).
    func testNoRouteShowsNoFreshness() async {
        let model = ScheduleViewModel.fixtures(bundle: Bundle(for: XCTestCase.self))
        await model.loadIfNeeded()
        XCTAssertNil(model.routeTitle)
        XCTAssertNil(model.freshnessMode(formatter))
    }
}
