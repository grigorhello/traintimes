import XCTest
@testable import TrainTimes

/// TT-130, D49: the day strip only offers dates within the feed's validity window (Q6), and a first use with no timetable shows
/// the failed card (TT-206) instead of claiming there are no trains.
@MainActor
final class ScheduleHorizonTests: XCTestCase {
    private struct WindowRepository: ScheduleRepository {
        var lastDay: ServiceDay?
        var hasTimetable = true

        func trips(for route: Route, on day: ServiceDay) async throws -> [Trip] {
            guard hasTimetable else { throw URLError(.notConnectedToInternet) }
            return []
        }

        func liveStatus(for route: Route, on day: ServiceDay) async throws -> LiveSnapshot { .empty }
        func lineNotices(for line: Line) async throws -> [LineNotice] { [] }
        func lastServiceDay() async throws -> ServiceDay? { lastDay }
    }

    private let today = ServiceDay(year: 2026, month: 11, day: 9)
    private let route = Route(
        from: Station(id: "OA", name: "Oakville GO"), to: Station(id: "UN", name: "Union Station GO"),
        line: Line(id: "LW", name: "Lakeshore West", colorHex: "#98002e")
    )

    private func model(_ repository: WindowRepository) -> ScheduleViewModel {
        ScheduleViewModel(route: route, repository: repository, clock: FixedClock(now: today.date(hour: 7, minute: 21)))
    }

    func testDayStripStopsAtTheLastServiceDay() async {
        let model = model(WindowRepository(lastDay: today.adding(days: 3)))
        await model.loadIfNeeded()
        XCTAssertEqual(model.days, (0...3).map { today.adding(days: $0) })
    }

    /// The strip covers every day of the feed's calendar (D49), not a fixed two weeks.
    func testALongerWindowShowsEveryDay() async {
        let model = model(WindowRepository(lastDay: today.adding(days: 18)))
        await model.loadIfNeeded()
        XCTAssertEqual(model.days, (0...18).map { today.adding(days: $0) })
    }

    func testAVeryLongWindowStopsAtSixWeeks() async {
        let model = model(WindowRepository(lastDay: today.adding(days: 200)))
        await model.loadIfNeeded()
        XCTAssertEqual(model.days.count, ScheduleViewModel.maxDayCount)
    }

    func testNoKnownEndKeepsFourteenDays() async {
        let model = model(WindowRepository(lastDay: nil))
        await model.loadIfNeeded()
        XCTAssertEqual(model.days.count, ScheduleViewModel.dayCount)
    }

    func testAnOutOfDateFeedStillShowsToday() async {
        let model = model(WindowRepository(lastDay: today.adding(days: -2)))
        await model.loadIfNeeded()
        XCTAssertEqual(model.days, [today])
    }

    /// TT-206: no timetable on device and none downloaded shows "Couldn’t load the timetable", never an empty timeline, and
    /// the status row says nothing over it; Try again loads once more.
    func testNoTimetableShowsTheFailedCardAndTryAgainLoads() async {
        let repository = FlakyRepository()
        let model = ScheduleViewModel(route: route, repository: repository, clock: FixedClock(now: today.date(hour: 7, minute: 21)))
        XCTAssertEqual(model.content, .loading, "Loading while the first download runs")
        await model.loadIfNeeded()
        XCTAssertEqual(model.content, .failed)
        XCTAssertNil(model.statusRowMode(TimeFormatter(format: .twelveHour)))

        repository.fails = false
        await model.retry()
        XCTAssertFalse(model.timetableFailed)
        XCTAssertNotEqual(model.content, .failed)
        XCTAssertNotEqual(model.content, .loading)
    }

    /// Fails until told otherwise. `@unchecked Sendable` is safe: the tests set `fails` only between awaited loads.
    private final class FlakyRepository: ScheduleRepository, @unchecked Sendable {
        var fails = true

        func trips(for route: Route, on day: ServiceDay) async throws -> [Trip] {
            if fails { throw URLError(.notConnectedToInternet) }
            return []
        }

        func liveStatus(for route: Route, on day: ServiceDay) async throws -> LiveSnapshot { .empty }
        func lineNotices(for line: Line) async throws -> [LineNotice] { [] }
    }
}
