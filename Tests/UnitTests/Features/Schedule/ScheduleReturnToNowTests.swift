import XCTest
@testable import TrainTimes

/// Back in the foreground after more than 10 min away, Schedule returns to Now on Today, as the Schedule tab does; a
/// shorter time keeps the day and the scroll (TT-222).
@MainActor
final class ScheduleReturnToNowTests: XCTestCase {
    override func tearDown() async throws {
        Analytics.tracker = nil
        try await super.tearDown()
    }

    private func loadedModel() async throws -> (ScheduleViewModel, TestClock) {
        let repository = try FixtureScheduleRepository(bundle: Bundle(for: ScheduleReturnToNowTests.self))
        let clock = TestClock(now: repository.now)
        let model = ScheduleViewModel(route: repository.route, repository: repository, clock: clock)
        await model.loadIfNeeded()
        return (model, clock)
    }

    func testBackAfterMoreThanTenMinutesReturnsToNowOnToday() async throws {
        let analytics = RecordingAnalytics.install()
        let (model, clock) = try await loadedModel()
        await model.select(model.days[1])
        let scrolls = model.scrollRequest
        let pulses = model.nowPulse

        model.wentToBackground()
        clock.advance(minutes: 11)
        await model.cameToForeground()

        XCTAssertEqual(model.selectedDay, model.today)
        XCTAssertEqual(model.scrollRequest, scrolls + 1, "Scrolled to Now")
        XCTAssertEqual(model.nowPulse, pulses + 1, "Now plays once")
        XCTAssertEqual(analytics.events.last, AnalyticsEvent("back_to_now", ["source": .string("reopen")]))
    }

    func testBackWithinTenMinutesKeepsTheDayAndTheScroll() async throws {
        let analytics = RecordingAnalytics.install()
        let (model, clock) = try await loadedModel()
        await model.select(model.days[1])
        let picked = model.selectedDay
        let scrolls = model.scrollRequest

        model.wentToBackground()
        clock.advance(minutes: 9)
        await model.cameToForeground()

        XCTAssertEqual(model.selectedDay, picked)
        XCTAssertEqual(model.scrollRequest, scrolls, "No scroll")
        XCTAssertFalse(analytics.names.contains("back_to_now"))
    }

    /// Becoming active without a trip to the background (a banner pulled down, the app switcher) never scrolls.
    func testActiveWithoutBackgroundKeepsTheScroll() async throws {
        let (model, clock) = try await loadedModel()
        await model.select(model.days[1])
        let scrolls = model.scrollRequest
        clock.advance(minutes: 30)
        await model.cameToForeground()
        XCTAssertEqual(model.scrollRequest, scrolls)
    }
}
