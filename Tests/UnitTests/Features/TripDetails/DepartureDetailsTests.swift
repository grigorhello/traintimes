import XCTest
@testable import TrainTimes

private final class BundleToken {}

/// Before departure in Trip details (TT-177, D69; the hero card since TT-205, D92): the demo's states (pending, platform
/// posted, late, boarding, departed), the hand-off into the ride, and only the alerted train that leaves first shows it.
@MainActor
final class DepartureDetailsTests: XCTestCase {
    private let formatter = TimeFormatter(format: .twelveHour)

    private func hero(at time: Date) async throws -> DepartureHero {
        let model = await DepartureRig.started(at: time).tripDetails()
        return try XCTUnwrap(model.departureHero(formatter))
    }

    func testPendingCountsDownWithThePulsingDash() async throws {
        let hero = try await hero(at: DepartureRig.time(17, 1))
        XCTAssertEqual(hero.line, "5:13 PM departs in")
        XCTAssertEqual(hero.time, "5:13 PM")
        XCTAssertEqual(hero.countdown, "12 min")
        XCTAssertNil(hero.platform)
        XCTAssertTrue(hero.pillPulses)
        XCTAssertNil(hero.late)
        XCTAssertFalse(hero.isLate)
        XCTAssertFalse(hero.isBoarding)
    }

    func testThePostedPlatformShowsInThePill() async throws {
        let rig = DepartureRig.started()
        let model = await rig.tripDetails()
        rig.move(to: DepartureRig.time(17, 3), model)

        let hero = try XCTUnwrap(model.departureHero(formatter))
        XCTAssertEqual(hero.platform, "7")
        XCTAssertEqual(hero.countdown, "10 min")
    }

    func testALateTrainNamesItsLateTimeAndSaysHowLate() async throws {
        let hero = try await hero(at: DepartureRig.time(17, 7))
        XCTAssertEqual(hero.line, "5:16 PM departs in")
        XCTAssertEqual(hero.time, "5:16 PM")
        XCTAssertEqual(hero.countdown, "9 min")
        XCTAssertEqual(hero.late, "3 min late")
        XCTAssertTrue(hero.isLate)
    }

    func testBoardingNowFor2MinBeforeItLeaves() async throws {
        let hero = try await hero(at: DepartureRig.time(17, 14))
        XCTAssertEqual(hero.line, "5:16 PM boarding now")
        XCTAssertTrue(hero.isBoarding)
        XCTAssertEqual(hero.countdown, "2 min")
    }

    func testOnceTheTrainLeavesTheTripIsBack() async throws {
        let rig = DepartureRig.started(at: DepartureRig.time(17, 16))
        let model = await rig.tripDetails()
        XCTAssertNil(model.departureHero(formatter), "no hero once it has left")
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
        XCTAssertNotNil(model.departureHero(formatter))

        let started = await model.startRide()

        XCTAssertTrue(started)
        XCTAssertTrue(model.isRiding)
        XCTAssertNil(model.departureHero(formatter))
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
        XCTAssertNotNil(model.departureHero(formatter))
    }

    func testTurningTheDemoOffStopsIt() {
        let rig = DepartureRig.started()
        rig.onBoard.setDemoDeparture(false)
        XCTAssertNil(rig.onBoard.departureDemo)
    }

    func testWithoutAPlatformFeedTheDashStaysStill() throws {
        let day = DepartureRig.day
        let trip = Trip(
            key: TripKey(serviceDay: day, tripId: "A"), scheduledDeparture: DepartureRig.time(17, 13),
            scheduledArrival: DepartureRig.time(17, 43), platform: .pending, tags: []
        )
        let departure = Departure(trip: trip, status: .scheduled, expectedDeparture: nil, expectedArrival: nil)
        let live = try XCTUnwrap(LiveDeparture(departure, now: DepartureRig.time(17, 1)))
        let hero = try XCTUnwrap(DepartureHero(live, now: DepartureRig.time(17, 1), pillPulses: false, formatter: formatter))
        XCTAssertNil(hero.platform, "the still dash")
        XCTAssertFalse(hero.pillPulses)
        XCTAssertNil(hero.late)
    }

    /// D92: no countdown strip and no checking strip on Schedule; the ride wins over the question.
    func testTheStripSlotShowsTheRideThenTheQuestion() {
        let checking = TrainMatcher.State.checking(DetectionFixtures.progress(stops: 1))
        let asking = TrainMatcher.State.asking(DetectionFixtures.question())
        XCTAssertEqual(RideStripContent(isRiding: false, detection: .idle), .otherwise)
        XCTAssertEqual(RideStripContent(isRiding: false, detection: checking), .otherwise)
        XCTAssertEqual(RideStripContent(isRiding: false, detection: asking), .asking)
        XCTAssertEqual(RideStripContent(isRiding: true, detection: asking), .riding)
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
        XCTAssertEqual(both.first.departureHero(formatter)?.countdown, "3 min")
        XCTAssertNil(both.second.departureHero(formatter), "the 7:32 AM train leaves first")

        let later = try await fixtureModels(alerted: ["LW-0758-20261105"])
        XCTAssertNil(later.first.departureHero(formatter), "no alert on the 7:32 AM train")
        XCTAssertEqual(later.second.departureHero(formatter)?.countdown, "29 min")
    }

    func testNoAlertsNoCard() async throws {
        let none = try await fixtureModels(alerted: [])
        XCTAssertNil(none.first.departureHero(formatter))
        XCTAssertFalse(none.first.followsClock)
    }
}
