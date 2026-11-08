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
        XCTAssertEqual(model.nowButtonTitle, "Now")
        XCTAssertEqual(model.nowButtonAccessibilityLabel, "Back to now, today")
        XCTAssertTrue(model.isAtNow, "Launch already shows the present, so Now is dimmed")
        XCTAssertEqual(model.scrollRequest, 1, "The first load scrolls to Now")
    }

    func testAnotherDayShowsScheduledTimesOnlyWithoutNowLine() async throws {
        let model = try await ScheduleViewModel.loadedFixture(dayIndex: 3)
        XCTAssertFalse(model.isToday)
        XCTAssertEqual(model.freshnessMode(formatter), .scheduledOnly(day: "Sun, Nov 8"))
        XCTAssertEqual(model.nowButtonTitle, "Today")
        XCTAssertEqual(model.nowButtonAccessibilityLabel, "Back to today")
        XCTAssertFalse(model.isAtNow)
        XCTAssertNil(model.layout.nowY)
        XCTAssertTrue(model.departures.isEmpty, "The fixtures run no trains on Sundays")
        XCTAssertEqual(model.scrollRequest, 2, "A new day starts at its first train")
    }

    /// Acceptance: selecting Sun 8 then tapping Today returns to today and now in one tap.
    func testTodayButtonReturnsToTodayAndNowInOneTap() async throws {
        let model = try await ScheduleViewModel.loadedFixture(dayIndex: 3)
        await model.backToNow()
        XCTAssertEqual(model.selectedDay, thursday)
        XCTAssertTrue(model.isToday)
        XCTAssertEqual(model.departures.count, 4)
        XCTAssertNotNil(model.layout.nowY)
        XCTAssertEqual(model.freshnessMode(formatter), .live(updated: "Updated just now"))
        XCTAssertEqual(model.nowButtonTitle, "Now")
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

    func testNowDimsOnlyWhileTheTimelineShowsThePresent() async throws {
        let model = try await ScheduleViewModel.loadedFixture()
        model.viewportHeight = 300
        XCTAssertTrue(model.isAtNow)
        model.scrollOffset = 200
        XCTAssertFalse(model.isAtNow)
        await model.backToNow()
        XCTAssertEqual(model.scrollRequest, 2, "Now scrolls back to the present")
        model.scrollOffset = model.layout.initialScrollOffset
        XCTAssertTrue(model.isAtNow)
    }

    func testRefreshKeepsCardIdentityAndScrollPosition() async throws {
        let model = try await ScheduleViewModel.loadedFixture()
        let ids = model.departures.map(\.id)
        model.scrollOffset = 120
        await model.refresh()
        XCTAssertEqual(model.departures.map(\.id), ids)
        XCTAssertEqual(model.scrollRequest, 1, "A refresh never scrolls")
        XCTAssertEqual(model.scrollOffset, 120)
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

    /// The line dot uses the feed colour unless it would vanish on the canvas; then ink-secondary.
    func testLineColourFallsBackWhenItWouldVanish() {
        XCTAssertNotNil(Color(lineHex: "#111827", on: .light))
        XCTAssertNil(Color(lineHex: "#111827", on: .dark))
        XCTAssertNotNil(Color(lineHex: "98002E", on: .light))
        XCTAssertNil(Color(lineHex: "#FFFFFF", on: .light))
        XCTAssertNil(Color(lineHex: "not a colour", on: .light))
    }
}
