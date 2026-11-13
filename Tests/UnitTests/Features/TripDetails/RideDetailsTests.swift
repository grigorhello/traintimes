import XCTest
@testable import TrainTimes

/// TT-172, TT-204: the ride display model through the demo ride's moments (Live-Ride-Lean), the ride strip, the "I'm on board" window
/// and the first-ride permission sheet, and Demo trains › Ride.
@MainActor
final class RideDetailsTests: XCTestCase {
    private let formatter = TimeFormatter(format: .twelveHour)

    private func t(_ hours: Int, _ minutes: Int, _ seconds: Int = 0) -> Date {
        DemoRideRig.time(hours, minutes, seconds)
    }

    private func details(_ rig: DemoRideRig) throws -> RideDetails {
        try XCTUnwrap(rig.onBoard.details(for: rig.key, formatter: formatter))
    }

    // MARK: The demo ride's moments (TT-204, D87: Live-Ride-Lean)

    func testRidingShowsYourStopAndTheMinutesToIt() async throws {
        let rig = await DemoRideRig.started()
        let ride = try details(rig)
        XCTAssertEqual(ride.moment, .riding)
        XCTAssertEqual(ride.kicker, "Your stop")
        XCTAssertFalse(ride.isKickerAccent)
        XCTAssertEqual(ride.countdown, "11 min")
        XCTAssertNil(ride.late, "Nothing says On time")
        // The list ends at your stop; passed stops have no time.
        XCTAssertEqual(ride.stops.map(\.id), ["UN", "EX", "MI", "LO", "PO", "CL"])
        XCTAssertEqual(ride.stops.map(\.time), [nil, nil, nil, nil, "5:36 PM", "5:43 PM"])
        XCTAssertEqual(ride.stops.map(\.isDone), [true, true, true, true, false, false])
        XCTAssertEqual(ride.stops.map(\.isNext), [false, false, false, false, true, false])
        XCTAssertEqual(ride.stops.map(\.isYours), [false, false, false, false, false, true])
        XCTAssertFalse(ride.stops.contains(where: \.isLate))
        // 80 s of the 320 s from Long Branch to Port Credit: a quarter of the way.
        XCTAssertEqual(ride.trainPosition ?? 0, 3.25, accuracy: 0.01)
        XCTAssertFalse(ride.isTinted)
        XCTAssertFalse(ride.pingsYourStop)
        XCTAssertEqual(ride.title, "5:13 PM train")
        XCTAssertEqual(ride.button, "End ride")
    }

    func testAtTheStopBeforeYoursYourStopIsNext() async throws {
        let rig = await DemoRideRig.started(at: t(17, 36, 20))
        let ride = try details(rig)
        XCTAssertEqual(ride.moment, .atStation)
        XCTAssertEqual(ride.kicker, "Your stop is next")
        XCTAssertTrue(ride.isKickerAccent)
        XCTAssertEqual(ride.countdown, "7 min")
        XCTAssertEqual(ride.trainPosition, 4)
        XCTAssertEqual(ride.stops.map(\.isDone), [true, true, true, true, true, false])
        XCTAssertEqual(ride.stops.map(\.time), [nil, nil, nil, nil, nil, "5:43 PM"])
        XCTAssertEqual(ride.stops.last?.isNext, true)
    }

    func testYourStopNextRingsYourStop() async throws {
        let rig = await DemoRideRig.started(at: t(17, 38))
        let ride = try details(rig)
        XCTAssertEqual(ride.moment, .yourStopNext)
        XCTAssertEqual(ride.kicker, "Your stop is next")
        XCTAssertTrue(ride.isKickerAccent)
        XCTAssertEqual(ride.countdown, "5 min")
        XCTAssertTrue(ride.pingsYourStop)
        XCTAssertFalse(ride.isTinted)
    }

    func testArrivingTintsTheHero() async throws {
        let rig = await DemoRideRig.started(at: t(17, 42, 20))
        let ride = try details(rig)
        XCTAssertEqual(ride.moment, .arriving)
        XCTAssertEqual(ride.kicker, "Arriving at your stop")
        XCTAssertEqual(ride.countdown, "1 min")
        XCTAssertTrue(ride.isTinted)
        XCTAssertTrue(ride.pingsYourStop)
        XCTAssertNotNil(ride.trainPosition)
    }

    func testAtYourStopItSaysNowAndShowsYourStopsTime() async throws {
        let rig = await DemoRideRig.started(at: t(17, 43, 5))
        let ride = try details(rig)
        XCTAssertEqual(ride.moment, .atYourStop)
        XCTAssertEqual(ride.kicker, "This is your stop")
        XCTAssertEqual(ride.countdown, "Now")
        XCTAssertNil(ride.late)
        XCTAssertNil(ride.trainPosition, "The tick takes the train's place")
        XCTAssertEqual(ride.railFill, 5)
        XCTAssertTrue(ride.isComplete)
        XCTAssertTrue(ride.isTinted)
        XCTAssertFalse(ride.pingsYourStop)
        XCTAssertEqual(ride.button, "Done")
        XCTAssertTrue(ride.stops.allSatisfy(\.isDone))
        XCTAssertEqual(ride.stops.map(\.time), [nil, nil, nil, nil, nil, "5:43 PM"])

        // Standing at your stop is not running late.
        rig.drive(to: t(17, 50))
        XCTAssertNil(try details(rig).late)
    }

    func testTheRideEndsTenMinutesAfterYourStopAndStaysCompleteInTheOpenSheetOnly() async throws {
        let rig = await DemoRideRig.started(at: t(17, 43, 5))
        XCTAssertNotNil(rig.onBoard.activeRide)
        let open = rig.tripDetails()
        rig.drive(to: t(17, 53, 10))
        XCTAssertEqual(rig.engine?.state?.phase, .ended)
        XCTAssertNil(rig.onBoard.activeRide, "The strip goes")
        XCTAssertTrue(open.isRiding, "The open sheet still says Ride complete")
        XCTAssertEqual(open.rideDetails(formatter)?.moment, .atYourStop)

        let later = rig.tripDetails()
        XCTAssertFalse(later.isRiding, "Opened again later, the sheet shows the trip")
        XCTAssertNil(later.rideDetails(formatter))
    }

    // MARK: Live data, the timetable, a late train

    private func plan() -> RidePlan { DemoRide.plan(on: DemoRideRig.day) }

    private func station(_ id: String) -> Station? {
        plan().stops.first { $0.station.id == id }?.station
    }

    func testALateTrainSaysHowLateAndMovesTheTimesAhead() throws {
        let state = RideState(
            phase: .riding, currentStop: nil, nextStop: station("PO"), stopsLeft: 2, minutesToYourStop: 13,
            expectedArrival: t(17, 48), source: .trainFeed, lastUpdate: t(17, 30)
        )
        let ride = try XCTUnwrap(RideDetails(plan: plan(), state: state, now: t(17, 32), formatter: formatter))
        XCTAssertEqual(ride.kicker, "Your stop")
        XCTAssertEqual(ride.countdown, "16 min")
        XCTAssertEqual(ride.late, "5 min late")
        XCTAssertEqual(ride.stops.map(\.time), [nil, nil, nil, nil, "5:41 PM", "5:48 PM"])
        XCTAssertEqual(ride.stops.map(\.isLate), [false, false, false, false, true, true])
    }

    func testUnderAMinuteLateIsOnTime() throws {
        let state = RideState(
            phase: .riding, currentStop: nil, nextStop: station("PO"), stopsLeft: 2, minutesToYourStop: 11,
            expectedArrival: t(17, 43, 25), source: .trainFeed, lastUpdate: t(17, 30)
        )
        let ride = try XCTUnwrap(RideDetails(plan: plan(), state: state, now: t(17, 32), formatter: formatter))
        XCTAssertNil(ride.late)
        XCTAssertFalse(ride.stops.contains(where: \.isLate))
    }

    func testOnTheTimetableTheScreenIsTheSame() throws {
        let state = RideState(
            phase: .riding, currentStop: nil, nextStop: station("PO"), stopsLeft: 2, minutesToYourStop: 11,
            expectedArrival: t(17, 43), source: .timetable, lastUpdate: nil
        )
        let ride = try XCTUnwrap(RideDetails(plan: plan(), state: state, now: t(17, 32), formatter: formatter))
        XCTAssertEqual(ride.kicker, "Your stop")
        XCTAssertEqual(ride.countdown, "11 min")
        XCTAssertNil(ride.late)
    }

    // MARK: The ride strip

    func testTheStripShowsTheNextStopAndYourStop() async throws {
        let rig = await DemoRideRig.started()
        let strip = try XCTUnwrap(rig.onBoard.strip(formatter: formatter))
        XCTAssertEqual(strip.title, "On board · 5:13 PM train")
        XCTAssertEqual(strip.next, "Next stop Port Credit")
        XCTAssertEqual(strip.countdown, "4 min")
        XCTAssertEqual(strip.destination, "Clarkson")
        XCTAssertEqual(strip.arrival, "5:43 PM")
        XCTAssertTrue(strip.isLive)

        rig.drive(to: t(17, 43, 5))
        let there = try XCTUnwrap(rig.onBoard.strip(formatter: formatter))
        XCTAssertEqual(there.next, "This is your stop")
        XCTAssertEqual(there.countdown, "Now")
    }

    func testEndRideEndsTheDemoRideAndTheStripGoes() async throws {
        let rig = await DemoRideRig.started()
        let model = rig.tripDetails()
        XCTAssertTrue(model.isRiding)
        XCTAssertNotNil(model.rideDetails(formatter))
        model.endRide()
        XCTAssertNil(rig.onBoard.activeRide)
        XCTAssertNil(rig.onBoard.strip(formatter: formatter))
        XCTAssertFalse(model.isRiding, "Ended by the rider: the sheet goes back to the trip")
    }

    // MARK: Demo trains › Ride

    func testTheDemoPlaysOnItsOwnEngineAndStopsWhenTurnedOff() async throws {
        let rig = await DemoRideRig.started()
        XCTAssertNotNil(rig.onBoard.demo)
        XCTAssertEqual(rig.onBoard.activeRide, DemoRide.ride(on: DemoRideRig.day))
        XCTAssertFalse(rig.onBoard.canStart, "No real ride starts while the demo plays")
        let route = await rig.onBoard.rideRoute(stations: NoStations())
        XCTAssertEqual(route?.from.id, "UN")
        XCTAssertEqual(route?.to.id, "CL")
        XCTAssertEqual(route?.line?.id, "LW")

        await rig.onBoard.setDemo(false)
        XCTAssertNil(rig.onBoard.demo)
        XCTAssertNil(rig.onBoard.activeRide)
    }

    func testTheDemoRunsSixTimesAsFastFrom532() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = DemoRideClock(start: t(17, 32), realStart: start, speed: DemoRide.speed)
        XCTAssertEqual(clock.start, t(17, 32))
        XCTAssertEqual(DemoRide.speed, 6)
        let demo = plan()
        XCTAssertEqual(demo.stops.map(\.station.id), ["UN", "EX", "MI", "LO", "PO", "CL"])
        XCTAssertEqual(demo.stops.first?.departure, t(17, 13))
        XCTAssertEqual(demo.stops.last?.arrival, t(17, 43))
        // Standing at Port Credit for 40 s, then at an even speed to Clarkson.
        let distances = demo.track?.stopDistances ?? []
        XCTAssertEqual(distances.count, 6)
        XCTAssertEqual(DemoRide.along(at: t(17, 36, 20), plan: demo), distances[4], accuracy: 0.001)
        XCTAssertEqual(DemoRide.along(at: t(17, 50), plan: demo), distances[5], accuracy: 0.001)
    }

    // MARK: "I'm on board"

    func testTheWindowOpens20MinutesBeforeDepartureAndClosesOnArrival() {
        let departure = t(17, 13), arrival = t(17, 43)
        XCTAssertFalse(TripDetailsViewModel.isInBoardingWindow(departure: departure, arrival: arrival, now: t(16, 52, 59)))
        XCTAssertTrue(TripDetailsViewModel.isInBoardingWindow(departure: departure, arrival: arrival, now: t(16, 53)))
        XCTAssertTrue(TripDetailsViewModel.isInBoardingWindow(departure: departure, arrival: arrival, now: t(17, 42, 59)))
        XCTAssertFalse(TripDetailsViewModel.isInBoardingWindow(departure: departure, arrival: arrival, now: t(17, 43)))
    }

    func testTheButtonShowsInTheWindowOnly() async throws {
        // 7:32 AM train, Oakville 7:32 to Union 8:12: 11 min before, and long before.
        let inWindow = try await TripDetailsViewModel.onBoardFixture()
        XCTAssertTrue(inWindow.showsOnBoardButton)
        XCTAssertFalse(inWindow.isRiding)
        XCTAssertEqual(
            inWindow.onBoardHint,
            "On board shows your stops as you ride and taps you about 1 minute before Union. It works from 20 minutes before departure until you arrive."
        )
        let early = try await TripDetailsViewModel.onBoardFixture(minutesLater: -30)
        XCTAssertFalse(early.showsOnBoardButton)
    }

    func testWithoutOnBoardTheSheetHasNoButton() async throws {
        let model = try await TripDetailsViewModel.loadedFixture()
        XCTAssertFalse(model.showsOnBoardButton)
        XCTAssertNil(model.rideDetails(formatter))
    }

    func testTheFirstRideShowsTheSheetThenAsksOnStart() async throws {
        let location = FakeLocation()
        let model = try await TripDetailsViewModel.onBoardFixture(location: location)
        XCTAssertTrue(model.needsLocationIntro, "Not asked yet: the app's sheet comes first")
        XCTAssertEqual(location.requests, 0, "Showing the button or the sheet asks nothing")

        let started = await model.startRide()
        XCTAssertTrue(started)
        XCTAssertEqual(location.requests, 1, "Continue goes on to the iOS prompt")
        XCTAssertFalse(model.needsLocationIntro)
        XCTAssertTrue(model.isRiding)
        XCTAssertFalse(model.showsOnBoardButton)
        XCTAssertNotNil(model.rideDetails(formatter))
        XCTAssertEqual(model.onBoard?.route, model.route)
        XCTAssertFalse(model.ridesInPlace, "started from the journey card: the rows rise (TT-172)")
    }

    func testOnceAnsweredTheButtonStartsWithoutTheSheet() async throws {
        let model = try await TripDetailsViewModel.onBoardFixture(location: FakeLocation(authorized: true))
        XCTAssertFalse(model.needsLocationIntro)
    }
}

/// No stations: the demo's route does not need them.
private struct NoStations: StationRepository {
    func stations() async throws -> [Station] { [] }
    func route(from: Station, to: Station) async throws -> Route { Route(from: from, to: to, line: nil) }
}
