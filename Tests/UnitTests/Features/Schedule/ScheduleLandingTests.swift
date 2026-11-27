import XCTest
@testable import TrainTimes

/// See trains lands on the alert's own card in Schedule, and Pick a new train at the old time's place (TT-255, D129): the
/// route and the day in one load, the scroll target, the swell's request, and the tab's return that the landing replaces.
/// The fixture route is Oakville to Union on Thu Nov 5 at 7:21 AM, trains at 7:32, 7:58, 8:21 and 8:50 AM.
@MainActor
final class ScheduleLandingTests: XCTestCase {
    override func tearDown() async throws {
        Analytics.tracker = nil
        try await super.tearDown()
    }

    private func loadedModel() async throws -> (ScheduleViewModel, FixtureScheduleRepository, TestClock) {
        let repository = try FixtureScheduleRepository(bundle: Bundle(for: ScheduleLandingTests.self))
        let clock = TestClock(now: repository.now)
        let model = ScheduleViewModel(route: repository.route, repository: repository, clock: clock)
        await model.loadIfNeeded()
        return (model, repository, clock)
    }

    private func key(_ id: String, on day: ServiceDay) -> TripKey { TripKey(serviceDay: day, tripId: id) }

    // MARK: See trains

    /// Today's card on the route and day already shown: no new trains, a glide to the card, then its swell.
    func testTodaysCardScrollsIntoViewAndSwells() async throws {
        let (model, repository, _) = try await loadedModel()
        let card = key("LW-0821-20261105", on: model.today)
        let (scrolls, entrances, days) = (model.scrollRequest, model.entranceRequest, model.daySelection)

        await model.land(.card(card), on: repository.route, day: model.today)

        XCTAssertEqual(model.scrollRequest, scrolls + 1)
        XCTAssertFalse(model.scrollJumps, "The same trains: the timeline glides")
        XCTAssertEqual(model.entranceRequest, entrances, "No new trains, no cascade")
        XCTAssertEqual(model.daySelection, days)
        XCTAssertEqual(model.scrollFocus, card)
        XCTAssertEqual(model.scrollOffset, try XCTUnwrap(model.layout.scrollOffset(showing: card)), accuracy: 0.001)
        XCTAssertEqual(model.landedCard, card)
        XCTAssertEqual(model.landingRequest, 1)
    }

    /// Another day's card: the day tile glides there, one load and one cascade, the jump to the card, its swell; no
    /// `day_changed`, which counts day taps.
    func testAnotherDaysCardChangesTheDayInOneLoad() async throws {
        let analytics = RecordingAnalytics.install()
        let (model, repository, _) = try await loadedModel()
        let friday = model.days[1]
        let card = key("LW-0758-20261105", on: friday)
        let (entrances, days) = (model.entranceRequest, model.daySelection)

        await model.land(.card(card), on: repository.route, day: friday)

        XCTAssertEqual(model.selectedDay, friday)
        XCTAssertEqual(model.daySelection, days + 1, "The accent tile glides")
        XCTAssertEqual(model.entranceRequest, entrances + 1, "One cascade")
        XCTAssertTrue(model.scrollJumps, "New trains: the timeline jumps and they cascade where they land")
        XCTAssertEqual(model.scrollFocus, card)
        XCTAssertEqual(model.landingRequest, 1)
        XCTAssertFalse(analytics.names.contains("day_changed"))
    }

    /// The evening's card on the other direction and a later day (board 52): the route turns and the day changes in one
    /// load, as one train's link, which Automatic direction keeps.
    func testTheRouteAndTheDayChangeInOneLoad() async throws {
        let timetable = try await TurnFixtures.timetable()
        let model = ScheduleViewModel(route: timetable.route, repository: timetable.repository(), clock: FixedClock(now: timetable.now))
        let choices = RecordingChoices()
        model.choices = choices
        await model.loadIfNeeded()
        let monday = model.days[4]
        let card = timetable.reverseTrips[1].key
        let entrances = model.entranceRequest

        await model.land(.card(card), on: timetable.reversed, day: monday)

        XCTAssertEqual(model.route, timetable.reversed)
        XCTAssertEqual(model.selectedDay, monday)
        XCTAssertEqual(model.entranceRequest, entrances + 1, "One load for the route and the day")
        XCTAssertEqual(model.scrollFocus, card)
        XCTAssertEqual(model.landedCard, card)
        XCTAssertEqual(choices.by, [.trainLink])
    }

    /// The route already shown is still told as one train's link, as a notification's tap does.
    func testTheSameRouteIsKeptAsATrainLink() async throws {
        let (model, repository, _) = try await loadedModel()
        let choices = RecordingChoices()
        model.choices = choices

        await model.land(.card(key("LW-0732-20261105", on: model.today)), on: repository.route, day: model.today)

        XCTAssertEqual(choices.chosen, [repository.route])
        XCTAssertEqual(choices.by, [.trainLink])
    }

    /// A card the day does not have: the timeline opens as the day would, and nothing swells.
    func testACardNotFoundOpensTheDayWithoutASwell() async throws {
        let (model, repository, _) = try await loadedModel()
        let scrolls = model.scrollRequest

        await model.land(.card(key("LW-0000-20261105", on: model.today)), on: repository.route, day: model.today)

        XCTAssertEqual(model.scrollRequest, scrolls + 1)
        XCTAssertNil(model.scrollFocus)
        XCTAssertEqual(model.scrollOffset, model.layout.initialScrollOffset, accuracy: 0.001, "Now near the top")
        XCTAssertNil(model.landedCard)
        XCTAssertEqual(model.landingRequest, 0)
    }

    /// Any other scroll request goes back to Now or the first train: the focus is the landing's alone.
    func testTheNextScrollRequestDropsTheFocus() async throws {
        let (model, repository, _) = try await loadedModel()
        await model.land(.card(key("LW-0850-20261105", on: model.today)), on: repository.route, day: model.today)
        XCTAssertNotNil(model.scrollFocus)

        await model.backToNow()

        XCTAssertNil(model.scrollFocus)
        XCTAssertEqual(model.scrollOffset, model.layout.initialScrollOffset, accuracy: 0.001)
        XCTAssertEqual(model.landingRequest, 1, "Nothing swells again")
    }

    // MARK: Pick a new train

    /// The old time's place: the first train at or after that time of day, with no swell; past the last train, the last.
    func testPickANewTrainLandsAtTheOldTimesPlace() async throws {
        let (model, repository, _) = try await loadedModel()
        let friday = model.days[1]

        await model.land(.time(model.today.date(hour: 7, minute: 50)), on: repository.route, day: friday)

        XCTAssertEqual(model.selectedDay, friday)
        XCTAssertEqual(model.scrollFocus, key("LW-0758-20261105", on: friday))
        XCTAssertNil(model.landedCard)
        XCTAssertEqual(model.landingRequest, 0, "No swell: it is not the alert's card")

        await model.land(.time(model.today.date(hour: 21, minute: 0)), on: repository.route, day: friday)
        XCTAssertEqual(model.scrollFocus, key("LW-0850-20261105", on: friday))
    }

    // MARK: The tab's return

    /// See trains from the Alerts tab after more than 10 min away: the tab's return neither goes back to Now on Today nor
    /// plays Now, since the landing brings its own day, scroll and swell. The next return is as before.
    func testTheTabsReturnIsTheLanding() async throws {
        let (model, repository, clock) = try await loadedModel()
        await model.select(model.days[2])
        model.leftView()
        clock.advance(minutes: 11)
        let (scrolls, pulses, day) = (model.scrollRequest, model.nowPulse, model.selectedDay)

        model.expectLanding()
        await model.cameIntoView()

        XCTAssertEqual(model.selectedDay, day, "Not back to Today")
        XCTAssertEqual(model.scrollRequest, scrolls)
        XCTAssertEqual(model.nowPulse, pulses)

        let friday = model.days[1]
        await model.land(.card(key("LW-0821-20261105", on: friday)), on: repository.route, day: friday)
        XCTAssertEqual(model.selectedDay, friday)

        model.leftView()
        clock.advance(minutes: 11)
        await model.cameIntoView()
        XCTAssertEqual(model.selectedDay, model.today, "A later return goes back to Now")
    }

    /// With Schedule in view (Pick a new train from Trip details over it) nothing is held.
    func testExpectingALandingInViewHoldsNothing() async throws {
        let (model, _, clock) = try await loadedModel()
        model.expectLanding()
        model.leftView()
        clock.advance(minutes: 11)
        let scrolls = model.scrollRequest

        await model.cameIntoView()

        XCTAssertEqual(model.scrollRequest, scrolls + 1, "Back to Now as usual")
    }

    // MARK: The swell

    func testTheSwell() {
        XCTAssertEqual(LandingSwell.pose(at: 0), LandingSwell.rest)
        let top = LandingSwell.pose(at: LandingSwell.peakTime)
        XCTAssertEqual(top.scale, LandingSwell.peak, accuracy: 0.0001)
        XCTAssertEqual(top.lift, 1, accuracy: 0.0001)
        XCTAssertGreaterThan(top.bellScale, 1, "The bell's pop has started")
        let bellTop = LandingSwell.pose(at: LandingSwell.bellDelay + LandingSwell.bellSwell)
        XCTAssertEqual(bellTop.bellScale, LandingSwell.bellPeak, accuracy: 0.0001)
        let settling = LandingSwell.pose(at: 0.6)
        XCTAssertLessThan(settling.scale, LandingSwell.peak)
        XCTAssertGreaterThanOrEqual(settling.lift, 0)
        XCTAssertEqual(LandingSwell.pose(at: LandingSwell.duration), LandingSwell.rest)
        XCTAssertEqual(LandingSwell.pose(at: LandingSwell.duration - 0.01).scale, 1, accuracy: 0.002, "At rest by the end")
    }
}

/// Stands in for Automatic direction's look: records each route Schedule says was chosen, and by whom.
@MainActor
private final class RecordingChoices: RouteChoiceFollowing {
    private(set) var chosen: [Route] = []
    private(set) var by: [RouteChoice] = []

    func chose(_ route: Route, by choice: RouteChoice) {
        chosen.append(route)
        by.append(choice)
    }
}
