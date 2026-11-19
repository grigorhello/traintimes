import XCTest
@testable import TrainTimes

/// TT-233 (D114): Boarding on Schedule. A train GO's train feed places at the station with its platform posted is
/// Boarding and stays the next train past its time; it has left when GO's feeds say so, or by the clock with no position.
@MainActor
final class ScheduleBoardingTests: XCTestCase {
    private typealias Rig = (model: ScheduleViewModel, clock: TestClock, repository: BoardingScheduleRepository)

    private let thursday = ServiceDay(year: 2026, month: 11, day: 5)
    private let formatter = TimeFormatter(format: .twelveHour)
    /// The 7:32 AM train from Oakville, Platform 2.
    private let first = BoardingFixtures.firstTripId

    override func tearDown() async throws {
        Analytics.tracker = nil
        try await super.tearDown()
    }

    private func at(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        thursday.date(hour: hour, minute: minute).addingTimeInterval(TimeInterval(second))
    }

    /// The fixture's live status fetched at `now`, with the 7:32 AM train `metres` from Oakville (nil: GO's train feed
    /// does not carry it) and, with `left`, Oakville dropped from its trip update.
    private func live(at now: Date, metres: Double?, left: Bool = false) async throws -> LiveSnapshot {
        try await BoardingFixtures.live(at: now, metres: metres.map { [first: $0] } ?? [:], left: left ? [first] : [])
    }

    /// Schedule on the fixture route, loaded at `now` with fresh live data.
    private func schedule(
        at now: Date, metres: Double?, watched: Set<TripKey> = [], boardingShown: BoardingShown = BoardingShown(defaults: nil)
    ) async throws -> Rig {
        let fixture = try FixtureScheduleRepository(bundle: Bundle(for: ScheduleBoardingTests.self))
        let trips = try await fixture.trips(for: fixture.route, on: fixture.serviceDay)
        let fetched = try await live(at: now, metres: metres)
        let repository = BoardingScheduleRepository(trips: trips, live: fetched)
        let clock = TestClock(now: now)
        let model = ScheduleViewModel(
            route: fixture.route, repository: repository, clock: clock, watchedTrips: FakeWatchedTrips(watched),
            boardingShown: boardingShown
        )
        await model.loadIfNeeded()
        return (model, clock, repository)
    }

    /// One poll at `now`: the clock moves there, then GO's feeds say `metres` and `left`. Polls stay under 2 min apart, as
    /// the app's are (30 s): an older position says nothing and the train would follow the clock.
    private func poll(_ rig: Rig, at now: Date, metres: Double?, left: Bool = false) async throws {
        let fetched = try await live(at: now, metres: metres, left: left)
        rig.clock.set(now)
        await rig.repository.set(fetched)
        await rig.model.pollOnce(playsDepartures: true)
    }

    private func departures(_ recorder: RecordingAnalytics) -> [AnalyticsEvent] {
        recorder.events.filter { $0.name == "train_departed" }
    }

    // MARK: Boarding

    /// At the station with its platform posted: Boarding, with the countdown still running.
    func testATrainAtItsPlatformIsBoarding() async throws {
        let rig = try await schedule(at: at(7, 31), metres: 120)
        let cards = rig.model.cards(formatter)
        XCTAssertEqual(cards.map(\.isBoarding), [true, false, false, false])
        XCTAssertEqual(cards[0].shownStatus, .boarding)
        XCTAssertEqual(cards[0].status, .onTime, "The train's own status stays under it")
        XCTAssertTrue(cards[0].isNext)
        XCTAssertEqual(cards[0].relativeTime, "in 1 min")
    }

    /// With no position for the train nothing is guessed: no Boarding.
    func testNoBoardingWithoutAPosition() async throws {
        let rig = try await schedule(at: at(7, 31), metres: nil)
        XCTAssertFalse(rig.model.cards(formatter).contains(where: \.isBoarding))
    }

    /// On its way in, farther than 350 m: not Boarding yet.
    func testNoBoardingWhileTheTrainIsStillOnItsWayIn() async throws {
        let rig = try await schedule(at: at(7, 31), metres: 900)
        let card = try XCTUnwrap(rig.model.cards(formatter).first)
        XCTAssertFalse(card.isBoarding)
        XCTAssertEqual(card.shownStatus, .onTime)
    }

    /// Past its time and still standing there: Boarding, the next train, "Departing", in its place. The poll that says so
    /// is no new set of trains: no cascade, no scroll.
    func testATrainStillAtItsPlatformStaysNextPastItsTime() async throws {
        let rig = try await schedule(at: at(7, 31, 30), metres: 120)
        let entrances = rig.model.entranceRequest
        let scrolls = rig.model.scrollRequest
        try await poll(rig, at: at(7, 32, 30), metres: 120)
        let cards = rig.model.cards(formatter)
        XCTAssertTrue(cards[0].isBoarding)
        XCTAssertFalse(cards[0].isDeparted)
        XCTAssertTrue(cards[0].isNext)
        XCTAssertEqual(cards[0].relativeTime, "Departing")
        XCTAssertFalse(cards[1].isNext)
        XCTAssertEqual(rig.model.nextDepartureId?.tripId, first)
        XCTAssertFalse(try XCTUnwrap(rig.model.layout.cards.first).isSteppedUp)
        XCTAssertEqual(rig.model.departureRequest, 0)
        XCTAssertEqual(rig.model.entranceRequest, entrances)
        XCTAssertEqual(rig.model.scrollRequest, scrolls)
    }

    // MARK: Departed

    /// The train moves off a minute past its time: Departed at that poll, with the step up, though the clock's own minute
    /// has passed.
    func testATrainThatMovesOffHasLeft() async throws {
        let recorder = RecordingAnalytics.install()
        let rig = try await schedule(at: at(7, 31, 30), metres: 120)
        try await poll(rig, at: at(7, 33), metres: 900)
        let cards = rig.model.cards(formatter)
        XCTAssertTrue(cards[0].isDeparted)
        XCTAssertFalse(cards[0].isBoarding)
        XCTAssertEqual(cards[0].shownStatus, .departed)
        XCTAssertTrue(cards[1].isNext)
        XCTAssertTrue(try XCTUnwrap(rig.model.layout.cards.first).isSteppedUp)
        XCTAssertEqual(rig.model.departureRequest, 1)
        XCTAssertEqual(rig.model.departing.map(\.tripId), [first])
        XCTAssertEqual(rig.model.departureLead?.tripId, first)
        XCTAssertEqual(rig.model.departureNext?.tripId, BoardingFixtures.expressTripId)
        XCTAssertEqual(departures(recorder), [.trainDeparted(source: .moved, secondsAfter: 60)])
    }

    /// With no position the clock decides, as before: Departed at its time.
    func testWithoutAPositionTheClockDecides() async throws {
        let recorder = RecordingAnalytics.install()
        let rig = try await schedule(at: at(7, 31), metres: nil)
        rig.clock.set(at(7, 32))
        rig.model.tick()
        XCTAssertEqual(try XCTUnwrap(rig.model.cards(formatter).first).shownStatus, .departed)
        XCTAssertEqual(rig.model.departureRequest, 1)
        XCTAssertEqual(departures(recorder), [.trainDeparted(source: .clock, secondsAfter: 0)])
    }

    /// GO's trip feed drops the station: the train has left from 1 min before its time, not earlier.
    func testTheFeedSaysTheTrainHasLeftFromOneMinuteBefore() async throws {
        let recorder = RecordingAnalytics.install()
        let rig = try await schedule(at: at(7, 30), metres: 120)
        try await poll(rig, at: at(7, 30, 30), metres: 120, left: true)
        XCTAssertFalse(try XCTUnwrap(rig.model.cards(formatter).first).isDeparted, "Too early to believe it")
        XCTAssertEqual(departures(recorder), [])
        rig.clock.set(at(7, 31))
        rig.model.tick()
        XCTAssertTrue(try XCTUnwrap(rig.model.cards(formatter).first).isDeparted)
        XCTAssertEqual(rig.model.departureRequest, 1)
        XCTAssertEqual(departures(recorder), [.trainDeparted(source: .feed, secondsAfter: -60)])
    }

    /// A train that left while the screen was away is drawn at rest and counted by nobody.
    func testNoEventForADepartureScheduleDidNotWatch() async throws {
        let recorder = RecordingAnalytics.install()
        let rig = try await schedule(at: at(7, 31), metres: nil)
        rig.clock.set(at(7, 32))
        rig.model.tick(playsDepartures: false)
        XCTAssertTrue(try XCTUnwrap(rig.model.cards(formatter).first).isDeparted)
        XCTAssertEqual(rig.model.departureRequest, 0)
        XCTAssertEqual(departures(recorder), [])
    }

    /// The watched-trip strip says "Departed" (D32), so it waits for the train to leave too.
    func testTheWatchedStripWaitsForTheTrainToLeave() async throws {
        let key = TripKey(serviceDay: thursday, tripId: first)
        let rig = try await schedule(at: at(7, 31, 30), metres: 120, watched: [key])
        try await poll(rig, at: at(7, 32, 30), metres: 120)
        XCTAssertNil(rig.model.watchedStrip(formatter), "Still at its platform")
        try await poll(rig, at: at(7, 33, 30), metres: 900)
        XCTAssertEqual(rig.model.watchedStrip(formatter)?.id, key)
    }

    // MARK: Analytics

    /// `boarding_shown` once per train, however many polls and ticks find it Boarding.
    func testBoardingShownIsSentOncePerTrain() async throws {
        let recorder = RecordingAnalytics.install()
        let rig = try await schedule(at: at(7, 24), metres: 120, boardingShown: BoardingShown(defaults: .ephemeral()))
        try await poll(rig, at: at(7, 24, 30), metres: 120)
        try await poll(rig, at: at(7, 25), metres: 120)
        rig.clock.set(at(7, 26))
        rig.model.tick()
        XCTAssertEqual(
            recorder.events.filter { $0.name == "boarding_shown" },
            [.boardingShown(station: "OA", minutesBefore: 8, surface: .schedule)]
        )
    }
}
