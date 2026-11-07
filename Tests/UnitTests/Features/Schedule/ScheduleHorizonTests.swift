import XCTest
@testable import TrainTimes

/// TT-130: the day strip only offers dates within the feed's validity window (Q6), and a first use with no timetable keeps
/// "Loading timetable" instead of claiming there are no trains.
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

    func testALongerWindowKeepsFourteenDays() async {
        let model = model(WindowRepository(lastDay: today.adding(days: 18)))
        await model.loadIfNeeded()
        XCTAssertEqual(model.days.count, ScheduleViewModel.dayCount)
    }

    func testAnOutOfDateFeedStillShowsToday() async {
        let model = model(WindowRepository(lastDay: today.adding(days: -2)))
        await model.loadIfNeeded()
        XCTAssertEqual(model.days, [today])
    }

    func testNoTimetableKeepsLoading() async {
        let model = model(WindowRepository(hasTimetable: false))
        await model.loadIfNeeded()
        XCTAssertEqual(model.content, .loading)
    }
}
