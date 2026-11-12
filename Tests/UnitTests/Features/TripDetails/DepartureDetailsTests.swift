import XCTest
@testable import TrainTimes

private final class BundleToken {}

/// Before departure in Trip details and on Schedule (TT-177, D69): the demo's states (pending, platform posted, delayed,
/// boarding, departed, over), "just announced" only after the pill was seen, the strip, the hand-off into the ride, and only
/// the alerted train that leaves first shows the card.
@MainActor
final class DepartureDetailsTests: XCTestCase {
    private let formatter = TimeFormatter(format: .twelveHour)

    private func details(at time: Date) async throws -> DepartureDetails {
        let model = await DepartureRig.started(at: time).tripDetails()
        return try XCTUnwrap(model.departureDetails(formatter))
    }

    func testPendingCountsDownWithThePulsingPill() async throws {
        let card = try await details(at: DepartureRig.time(17, 1))
        XCTAssertEqual(card.label, "Departs from Union Station GO")
        XCTAssertNil(card.platform)
        XCTAssertEqual(card.platformText, "Platform")
        XCTAssertTrue(card.pillPulses)
        XCTAssertEqual(card.countdown, "12 min")
        XCTAssertEqual(card.countdownTime, "5:13 PM")
        XCTAssertEqual(card.detail, "On time · platform soon")
        XCTAssertEqual(card.emphasis, "platform soon")
        XCTAssertFalse(card.isDelayed)
        XCTAssertFalse(card.isBoarding)
        XCTAssertEqual(card.yourStop, "Clarkson GO")
        XCTAssertEqual(card.arrival, "5:43 PM")
        XCTAssertEqual(card.rideLength, "30 min ride")
        XCTAssertEqual(card.source, .live("Live · GO train data"))
        XCTAssertEqual(card.freshness, "Updated just now")
    }

    func testThePlatformPostedWhileOpenIsJustAnnounced() async throws {
        let rig = DepartureRig.started()
        let model = await rig.tripDetails()
        rig.move(to: DepartureRig.time(17, 3), model)

        let card = try XCTUnwrap(model.departureDetails(formatter))
        XCTAssertEqual(card.platform, "7")
        XCTAssertEqual(card.platformText, "Platform 7")
        XCTAssertEqual(card.countdown, "10 min")
        XCTAssertEqual(card.detail, "On time · just announced")
        XCTAssertEqual(card.emphasis, "just announced")
    }

    func testAPlatformAlreadyPostedWhenOpenedIsNotNews() async throws {
        let card = try await details(at: DepartureRig.time(17, 3, 30))
        XCTAssertEqual(card.platformText, "Platform 7")
        XCTAssertEqual(card.detail, "On time")
        XCTAssertNil(card.emphasis)
    }

    func testALateTrainCountsToItsLateTimeInDelayInk() async throws {
        let card = try await details(at: DepartureRig.time(17, 7))
        XCTAssertEqual(card.countdown, "9 min")
        XCTAssertEqual(card.countdownTime, "5:16 PM")
        XCTAssertEqual(card.detail, "Delayed 3 min · was 5:13 PM")
        XCTAssertEqual(card.emphasis, "was 5:13 PM")
        XCTAssertTrue(card.isDelayed)
        XCTAssertEqual(card.arrival, "5:46 PM")
    }

    func testBoardingNowFor2MinBeforeItLeaves() async throws {
        let card = try await details(at: DepartureRig.time(17, 14))
        XCTAssertEqual(card.label, "Boarding now")
        XCTAssertTrue(card.isBoarding)
        XCTAssertFalse(card.isDelayed)
        XCTAssertEqual(card.countdown, "2 min")
        XCTAssertEqual(card.detail, "Doors close at 5:16 PM")
        XCTAssertEqual(card.emphasis, "5:16 PM")
    }

    func testDepartedFor2MinThenTheJourneyCardIsBack() async throws {
        let rig = DepartureRig.started(at: DepartureRig.time(17, 16))
        let model = await rig.tripDetails()
        let card = try XCTUnwrap(model.departureDetails(formatter))
        XCTAssertEqual(card.label, "Departed 5:16 PM")
        XCTAssertNil(card.countdown)
        XCTAssertEqual(card.detail, "Delayed 3 min")

        rig.move(to: DepartureRig.time(17, 18), model)
        XCTAssertNil(model.departureDetails(formatter))
        XCTAssertNotNil(model.details(formatter))
    }

    func testDirectionsOpenMapsToTheDepartureStationUntilTheTrainLeaves() async throws {
        let maps = FakeMapsOpener()
        let rig = DepartureRig.started()
        let model = await rig.tripDetails(maps: maps)
        XCTAssertEqual(model.directionsStation?.id, "UN")
        model.openDirections()
        XCTAssertEqual(maps.opened.map(\.name), ["Union Station GO"])
        rig.move(to: DepartureRig.time(17, 16), model)
        XCTAssertNotNil(model.departureDetails(formatter), "Departed still shows the card")
        XCTAssertNil(model.directionsStation, "the train has left Union: no link")
    }

    func testTheSheetFollowsTheClockWhileLive() async {
        let model = await DepartureRig.started().tripDetails()
        XCTAssertTrue(model.followsClock)
        XCTAssertTrue(model.showsOnBoardButton)
        XCTAssertFalse(model.needsLocationIntro, "the demo asks for no location")
    }

    func testImOnBoardTurnsTheSameSheetIntoTheRide() async throws {
        let rig = DepartureRig.started(at: DepartureRig.time(17, 10))
        let model = await rig.tripDetails()
        XCTAssertNotNil(model.departureDetails(formatter))

        let started = await model.startRide()

        XCTAssertTrue(started)
        XCTAssertTrue(model.isRiding)
        XCTAssertNil(model.departureDetails(formatter))
        XCTAssertNotNil(model.rideDetails(formatter))
        XCTAssertFalse(model.showsOnBoardButton)
        XCTAssertTrue(model.ridesInPlace, "the ride takes the card's place at rest, with no rise")
        XCTAssertNotNil(rig.onBoard.departureDemo, "the departure keeps playing under the ride")
    }

    func testEndRideBringsTheDepartureBack() async {
        let rig = DepartureRig.started(at: DepartureRig.time(17, 10))
        let model = await rig.tripDetails()
        await model.startRide()

        model.endRide()

        XCTAssertNil(rig.onBoard.activeRide)
        XCTAssertNil(rig.onBoard.demo)
        XCTAssertNotNil(model.departureDetails(formatter))
    }

    func testTurningTheDemoOffStopsIt() {
        let rig = DepartureRig.started()
        rig.onBoard.setDemoDeparture(false)
        XCTAssertNil(rig.onBoard.departureDemo)
        XCTAssertNil(rig.onBoard.demoDepartureStrip(formatter: formatter))
    }

    // MARK: Strip

    func testTheStripCountsDownThroughTheStates() throws {
        let rig = DepartureRig.started()
        let pending = try XCTUnwrap(rig.onBoard.demoDepartureStrip(formatter: formatter))
        XCTAssertEqual(pending.title, "Your 5:13 PM train")
        XCTAssertNil(pending.platform)
        XCTAssertTrue(pending.pillPulses)
        XCTAssertEqual(pending.status, "On time")
        XCTAssertEqual(pending.countdown, "12 min")

        rig.clock.set(DepartureRig.time(17, 3))
        let posted = try XCTUnwrap(rig.onBoard.demoDepartureStrip(formatter: formatter))
        XCTAssertEqual(posted.platform, "7")
        XCTAssertEqual(posted.countdown, "10 min")

        rig.clock.set(DepartureRig.time(17, 7))
        let delayed = try XCTUnwrap(rig.onBoard.demoDepartureStrip(formatter: formatter))
        XCTAssertEqual(delayed.title, "Your 5:13 PM train", "the scheduled time stays the train's name")
        XCTAssertEqual(delayed.status, "Delayed 3 min")
        XCTAssertTrue(delayed.isDelayed)
        XCTAssertEqual(delayed.countdown, "9 min")

        rig.clock.set(DepartureRig.time(17, 14))
        let boarding = try XCTUnwrap(rig.onBoard.demoDepartureStrip(formatter: formatter))
        XCTAssertEqual(boarding.status, "Boarding now")
        XCTAssertFalse(boarding.isDelayed)

        rig.clock.set(DepartureRig.time(17, 16))
        XCTAssertNil(rig.onBoard.demoDepartureStrip(formatter: formatter), "once it has left the watched strip takes over")
    }

    func testWithoutAPlatformFeedThePendingPlatformStaysStill() throws {
        let day = DepartureRig.day
        let trip = Trip(
            key: TripKey(serviceDay: day, tripId: "A"), scheduledDeparture: DepartureRig.time(17, 13),
            scheduledArrival: DepartureRig.time(17, 43), platform: .pending, tags: []
        )
        let departure = Departure(trip: trip, status: .scheduled, expectedDeparture: nil, expectedArrival: nil)
        let live = try XCTUnwrap(LiveDeparture(departure, now: DepartureRig.time(17, 1)))

        let strip = DepartureStrip(live, now: DepartureRig.time(17, 1), hasPlatformSource: false, formatter: formatter)
        XCTAssertNil(strip.platform, "The still dash pill")
        XCTAssertFalse(strip.pillPulses)
        XCTAssertEqual(strip.status, "Scheduled")

        let card = DepartureDetails(
            live, origin: "Union Station GO", destination: "Clarkson GO", now: DepartureRig.time(17, 1), freshness: .scheduledOnly,
            hasPlatformSource: false, justAnnounced: false, formatter: formatter
        )
        XCTAssertFalse(card.pillPulses)
        XCTAssertEqual(card.detail, "Scheduled · Check the board")
        XCTAssertEqual(card.source, .timetable)
        XCTAssertNil(card.freshness)
    }

    func testTheCountdownStripRanksUnderTheRideAndTrainDetection() {
        let checking = TrainMatcher.State.checking(DetectionFixtures.progress(stops: 1))
        let asking = TrainMatcher.State.asking(DetectionFixtures.question())
        XCTAssertEqual(RideStripContent(isRiding: false, detection: .idle, departs: true), .departure)
        XCTAssertEqual(RideStripContent(isRiding: false, detection: .idle, departs: false), .otherwise)
        // The phone moving with a train, and a ride, win over the countdown (D68, D69).
        XCTAssertEqual(RideStripContent(isRiding: false, detection: checking, departs: true), .checking)
        XCTAssertEqual(RideStripContent(isRiding: false, detection: asking, departs: true), .asking)
        XCTAssertEqual(RideStripContent(isRiding: true, detection: .idle, departs: true), .riding)
    }

    func testAHandOffRideThatEndedOnItsOwnLetsARealRideStart() async throws {
        let day = DepartureRig.day
        let clock = TestClock(now: DepartureRig.time(17, 10))
        let app = RideEngine(
            data: FakeRideData(plan: try OnBoardFixtures.plan()), location: FakeLocation(authorized: true), clock: clock,
            defaults: nil, tickInterval: nil
        )
        let onBoard = OnBoard(
            app: app,
            makeDeparture: { DemoDeparture.Session(day: day, clock: clock) },
            makeHandOff: { _ in (engine: DemoRide.engine(on: day, clock: clock, tickInterval: nil), ride: DemoRide.ride(on: day)) }
        )
        onBoard.setDemoDeparture(true)
        let handedOff = await onBoard.handOffDemo()
        XCTAssertTrue(handedOff)
        XCTAssertFalse(onBoard.canStart, "the demo ride stands in for the app's engine while it runs")

        // The demo ride ends by itself, as 10 min after its last stop, not through End ride.
        onBoard.engine?.end()
        XCTAssertNil(onBoard.activeRide)
        XCTAssertTrue(onBoard.canStart)

        // Train detection's Yes (or "I’m on board") on a real train now starts it on the app's engine.
        let ride = Ride(trip: TripKey(serviceDay: day, tripId: "LW-REAL"), from: "UN", to: "CL")
        let started = await onBoard.start(ride, on: DemoRide.route)
        XCTAssertTrue(started)
        XCTAssertTrue(onBoard.engine === app)
        XCTAssertEqual(onBoard.activeRide?.tripId, "LW-REAL")
    }

    // MARK: Real trains

    /// The fixture route at 7:29 AM: the 7:32 AM and 7:58 AM trains are both in their window.
    private func fixtureModels(alerted: Set<String>) async throws -> (first: TripDetailsViewModel, second: TripDetailsViewModel) {
        let repository = try FixtureScheduleRepository(bundle: Bundle(for: BundleToken.self))
        let day = repository.serviceDay
        let alerts = FakeWatchedTrips(Set(alerted.map { TripKey(serviceDay: day, tripId: $0) }))
        func model(_ id: String) async -> TripDetailsViewModel {
            let model = TripDetailsViewModel(
                route: repository.route, key: TripKey(serviceDay: day, tripId: id), repository: repository,
                clock: FixedClock(now: day.date(hour: 7, minute: 29)), alerts: alerts
            )
            await model.load()
            return model
        }
        return (await model("LW-0732-20261105"), await model("LW-0758-20261105"))
    }

    func testOnlyTheAlertedTrainThatLeavesFirstShowsTheCard() async throws {
        let both = try await fixtureModels(alerted: ["LW-0732-20261105", "LW-0758-20261105"])
        XCTAssertEqual(both.first.departureDetails(formatter)?.countdown, "3 min")
        XCTAssertNil(both.second.departureDetails(formatter), "the 7:32 AM train leaves first")

        let later = try await fixtureModels(alerted: ["LW-0758-20261105"])
        XCTAssertNil(later.first.departureDetails(formatter), "no alert on the 7:32 AM train")
        XCTAssertEqual(later.second.departureDetails(formatter)?.countdown, "29 min")
    }

    func testNoAlertsNoCard() async throws {
        let none = try await fixtureModels(alerted: [])
        XCTAssertNil(none.first.departureDetails(formatter))
        XCTAssertFalse(none.first.followsClock)
    }

    func testScheduleShowsTheStripForTheAlertedTrainThatLeavesFirst() async throws {
        let repository = try FixtureScheduleRepository(bundle: Bundle(for: BundleToken.self))
        let day = repository.serviceDay
        let keys = ["LW-0732-20261105", "LW-0758-20261105"].map { TripKey(serviceDay: day, tripId: $0) }
        let model = ScheduleViewModel(
            route: repository.route, repository: repository, clock: FixedClock(now: day.date(hour: 7, minute: 21)),
            watchedTrips: FakeWatchedTrips(Set(keys))
        )
        await model.loadIfNeeded()

        let strip = try XCTUnwrap(model.departureStrip(formatter))
        XCTAssertEqual(strip.key, keys[0])
        XCTAssertEqual(strip.title, "Your 7:32 AM train")
        XCTAssertEqual(strip.platform, "2")
        XCTAssertEqual(strip.countdown, "11 min")

        let unalerted = ScheduleViewModel(
            route: repository.route, repository: repository, clock: FixedClock(now: day.date(hour: 7, minute: 21)),
            watchedTrips: FakeWatchedTrips()
        )
        await unalerted.loadIfNeeded()
        XCTAssertNil(unalerted.departureStrip(formatter))
    }
}
