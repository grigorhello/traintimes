import XCTest
@testable import TrainTimes

/// Back in the foreground after more than 10 min away, Schedule returns to Now on Today, as the Schedule tab does; a
/// shorter time keeps the day and the scroll (TT-222). Automatic direction's look is awaited first, so there is one
/// arrival and one Now play (TT-234, D116).
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

    // MARK: Automatic direction's look first (TT-234, D116)

    /// The look turned the route (true): the turn's own load, jump and Now play are the arrival, so coming back adds no
    /// Now play and no scroll of its own.
    func testALookThatTurnedTheRouteLeavesNoSecondNowPlay() async throws {
        let (model, clock) = try await loadedModel()
        await model.backToNow()
        let scrolls = model.scrollRequest
        let pulses = model.nowPulse
        let look = LookRecord()

        model.wentToBackground()
        clock.advance(minutes: 9)
        await model.cameToForeground {
            look.runs += 1
            return true
        }

        XCTAssertEqual(look.runs, 1)
        XCTAssertEqual(model.nowPulse, pulses, "No Now play beside the turn's")
        XCTAssertEqual(model.scrollRequest, scrolls)
    }

    /// The look did nothing (false) after a short time away: what `cameToForeground()` alone does, Now plays where it is.
    func testALookThatDidNothingPlaysNowWhereItIs() async throws {
        let (model, clock) = try await loadedModel()
        await model.backToNow()
        let scrolls = model.scrollRequest
        let pulses = model.nowPulse
        let look = LookRecord()

        model.wentToBackground()
        clock.advance(minutes: 9)
        await model.cameToForeground {
            look.runs += 1
            return false
        }

        XCTAssertEqual(look.runs, 1)
        XCTAssertEqual(model.nowPulse, pulses + 1, "Now plays once")
        XCTAssertEqual(model.scrollRequest, scrolls, "No scroll")
    }

    /// More than 10 min away on another day: Today is selected before the look runs, so it looks on Today, and the other
    /// day's cards hide meanwhile. The look did nothing, so the return to Now follows as without it.
    func testAfterALongTimeAwayTodayIsBackBeforeTheLookRuns() async throws {
        let analytics = RecordingAnalytics.install()
        let (model, clock) = try await loadedModel()
        await model.select(model.days[1])
        let scrolls = model.scrollRequest
        let pulses = model.nowPulse
        let look = LookRecord()

        model.wentToBackground()
        clock.advance(minutes: 11)
        await model.cameToForeground {
            look.runs += 1
            look.day = model.selectedDay
            look.wasToday = model.isToday
            look.hidOldCards = model.awaitsNewTrains
            look.scrolls = model.scrollRequest
            return false
        }

        XCTAssertEqual(look.runs, 1)
        XCTAssertEqual(look.day, model.today, "Today was put back first")
        XCTAssertTrue(look.wasToday)
        XCTAssertTrue(look.hidOldCards, "The other day's cards hide while the look decides")
        XCTAssertEqual(look.scrolls, scrolls, "The scroll waits for the look")
        XCTAssertEqual(model.selectedDay, model.today)
        XCTAssertFalse(model.awaitsNewTrains)
        XCTAssertEqual(model.departures.count, 4, "Today's trains")
        XCTAssertEqual(model.scrollRequest, scrolls + 1, "Scrolled to Now")
        XCTAssertEqual(model.nowPulse, pulses + 1, "Now plays once")
        XCTAssertEqual(analytics.names.filter { $0 == "back_to_now" }.count, 1)
    }

    /// More than 10 min away on another day, and the look turns the route: its turn is the one load, the one jump to Now
    /// and the one Now play.
    func testAfterALongTimeAwayATurnIsTheOneArrival() async throws {
        let (model, clock) = try await loadedModel()
        let route = try XCTUnwrap(model.route)
        await model.select(model.days[1])
        let scrolls = model.scrollRequest
        let pulses = model.nowPulse

        model.wentToBackground()
        clock.advance(minutes: 11)
        await model.cameToForeground {
            await model.turn()
            return true
        }

        XCTAssertEqual(model.route, Route(from: route.to, to: route.from, line: route.line))
        XCTAssertEqual(model.selectedDay, model.today)
        XCTAssertFalse(model.awaitsNewTrains)
        XCTAssertEqual(model.scrollRequest, scrolls + 1, "One jump to Now")
        XCTAssertEqual(model.nowPulse, pulses + 1, "One Now play")
    }
}

/// What the look's closure saw when `cameToForeground(looking:)` ran it.
@MainActor
private final class LookRecord {
    var runs = 0
    var day: ServiceDay?
    var wasToday = false
    var hidOldCards = false
    var scrolls = 0
}
