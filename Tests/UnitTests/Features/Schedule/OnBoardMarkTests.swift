import XCTest
@testable import TrainTimes

/// TT-256 (D130): the train you ride is marked on Schedule ("You’re on board", its ordinary colours, the ride's arrival),
/// named on the ride strip and the ride screen ("You’re on the 5:13 PM"), and the ride opens by itself on each arrival
/// (`RideOpening`), counted as `ride_ended`'s `auto_opens`.
@MainActor
final class OnBoardMarkTests: XCTestCase {
    private let thursday = ServiceDay(year: 2026, month: 11, day: 5)
    private let formatter = TimeFormatter(format: .twelveHour)

    // MARK: The card

    private func departure(minutes: Int = 25, status: TrainStatus = .onTime) -> Departure {
        let time = thursday.date(hour: 16, minute: 29)
        let trip = Trip(
            key: TripKey(serviceDay: thursday, tripId: "LW-1629"),
            scheduledDeparture: time,
            scheduledArrival: time.addingTimeInterval(TimeInterval(minutes * 60)),
            platform: .pending,
            tags: [.express]
        )
        return Departure(trip: trip, status: status, expectedDeparture: nil, expectedArrival: nil)
    }

    private func riding(_ departure: Departure, minutes: Int, isLate: Bool) -> RiddenTrain {
        RiddenTrain(
            key: departure.id, originId: "UN", destinationId: "CL",
            arrival: departure.departureTime.addingTimeInterval(TimeInterval(minutes * 60)), isLate: isLate
        )
    }

    /// Board 9, option A: the 4:29 PM has left, you ride it 4 min late: "You’re on board", its arrival and ride length from
    /// the ride, the arrival amber, and the card is not drawn as a departed one although it has left.
    func testTheCardOfTheTrainYouRideFollowsTheRide() {
        let train = departure()
        let card = DepartureCard(
            train, isNext: false, isDeparted: true, riding: riding(train, minutes: 29, isLate: true),
            now: thursday.date(hour: 16, minute: 34), formatter: formatter
        )
        XCTAssertTrue(card.isOnBoard)
        XCTAssertTrue(card.isDeparted, "it keeps a departed train's place on the timeline")
        XCTAssertFalse(card.looksDeparted, "but not the flat grey look")
        XCTAssertEqual(card.arrivalTime, "4:58 PM")
        XCTAssertEqual(card.tripLength, "29 min ride")
        XCTAssertTrue(card.arrivesLate)
        XCTAssertFalse(card.isDelayed, "the departure time keeps the train's own ink")
    }

    /// On time: the arrival is ink. Not ridden: the card is as before, its arrival the train's own.
    func testOnlyTheRiddenTrainIsMarked() {
        let train = departure()
        let onTime = DepartureCard(
            train, isNext: false, isDeparted: true, riding: riding(train, minutes: 25, isLate: false),
            now: thursday.date(hour: 16, minute: 34), formatter: formatter
        )
        XCTAssertTrue(onTime.isOnBoard)
        XCTAssertFalse(onTime.arrivesLate)
        let plain = DepartureCard(train, isNext: false, isDeparted: true, now: thursday.date(hour: 16, minute: 34), formatter: formatter)
        XCTAssertFalse(plain.isOnBoard)
        XCTAssertTrue(plain.looksDeparted)
        XCTAssertEqual(plain.arrivalTime, "4:54 PM")
        XCTAssertEqual(plain.shownStatus, .departed)
    }

    /// A train that does not run for your stop is never marked: it keeps "Cancelled".
    func testACancelledTrainIsNotMarked() {
        let train = departure(status: .cancelled(reportedAt: thursday.date(hour: 16, minute: 0)))
        let card = DepartureCard(
            train, isNext: false, isDeparted: true, riding: riding(train, minutes: 29, isLate: true),
            now: thursday.date(hour: 16, minute: 34), formatter: formatter
        )
        XCTAssertFalse(card.isOnBoard)
        XCTAssertEqual(card.shownStatus, .cancelled)
    }

    // MARK: Schedule

    private func model(at hour: Int, _ minute: Int) async throws -> ScheduleViewModel {
        let repository = try FixtureScheduleRepository(scenario: .normal, bundle: Bundle(for: OnBoardMarkTests.self))
        let model = ScheduleViewModel(
            route: repository.route, repository: repository, clock: TestClock(now: thursday.date(hour: hour, minute: minute))
        )
        await model.loadIfNeeded()
        return model
    }

    /// Today, on the ride's two stations: only the ridden train's card is marked.
    func testScheduleMarksTheRiddenTrainOnItsRoute() async throws {
        let model = try await model(at: 7, 40)
        let route = try XCTUnwrap(model.route)
        let first = try XCTUnwrap(model.departures.first)
        let ride = RiddenTrain(
            key: first.id, originId: route.from.id, destinationId: route.to.id,
            arrival: first.trip.scheduledArrival.addingTimeInterval(240), isLate: true
        )
        let cards = model.cards(formatter, riding: ride)
        XCTAssertEqual(cards.map(\.isOnBoard), cards.indices.map { $0 == 0 })
        XCTAssertTrue(cards[0].isDeparted)
        XCTAssertFalse(cards[0].looksDeparted)
        XCTAssertEqual(cards[0].arrivalTime, formatter.time(ride.arrival))
        XCTAssertFalse(model.cards(formatter).contains(where: \.isOnBoard), "no ride, no mark")
    }

    /// The other way round, or another day: the ride is not on Schedule's route, so nothing is marked.
    func testScheduleLeavesOtherRoutesAndDaysUnmarked() async throws {
        let model = try await model(at: 7, 40)
        let route = try XCTUnwrap(model.route)
        let first = try XCTUnwrap(model.departures.first)
        let backwards = RiddenTrain(
            key: first.id, originId: route.to.id, destinationId: route.from.id, arrival: first.trip.scheduledArrival, isLate: false
        )
        XCTAssertFalse(model.cards(formatter, riding: backwards).contains(where: \.isOnBoard))
        let ride = RiddenTrain(
            key: first.id, originId: route.from.id, destinationId: route.to.id, arrival: first.trip.scheduledArrival, isLate: false
        )
        await model.select(thursday.adding(days: 1))
        XCTAssertFalse(model.cards(formatter, riding: ride).contains(where: \.isOnBoard))
    }

    // MARK: The strip and the ride screen

    /// The demo ride is the 5:13 PM from Union: the strip and the ride screen name it by its scheduled time, and On board
    /// hands Schedule the ride's train, on time.
    func testTheStripAndTheRideScreenNameTheTrain() async throws {
        let rig = await DemoRideRig.started()
        let strip = try XCTUnwrap(rig.onBoard.strip(formatter: formatter))
        XCTAssertEqual(strip.train, "You’re on the 5:13 PM")
        let details = try XCTUnwrap(rig.onBoard.details(for: rig.key, formatter: formatter))
        XCTAssertEqual(details.onTrain, "You’re on the 5:13 PM")
        let train = try XCTUnwrap(rig.onBoard.riddenTrain)
        XCTAssertEqual(train.key, rig.key)
        XCTAssertEqual(train.originId, "UN")
        XCTAssertEqual(train.destinationId, "CL")
        XCTAssertEqual(formatter.time(train.arrival), "5:43 PM")
        XCTAssertFalse(train.isLate)
    }

    /// 24-hour Time format names the train in it.
    func testTheTrainNameFollowsTheTimeFormat() async throws {
        let rig = await DemoRideRig.started()
        let strip = try XCTUnwrap(rig.onBoard.strip(formatter: TimeFormatter(format: .twentyFourHour)))
        XCTAssertEqual(strip.train, "You’re on the 17:13")
    }

    // MARK: The ride opens by itself

    func testTheRideOpensOnAnArrivalWithNothingOverSchedule() {
        let opening = RideOpening()
        opening.arrived()
        XCTAssertTrue(opening.decide(rideRuns: true, inFront: true))
        XCTAssertFalse(opening.decide(rideRuns: true, inFront: true), "one opening per arrival")
        opening.arrived()
        XCTAssertTrue(opening.decide(rideRuns: true, inFront: true), "every arrival, also after the rider closed it")
    }

    func testTheRideStaysClosedWithNoRideOrSomethingOverSchedule() {
        let opening = RideOpening()
        XCTAssertFalse(opening.decide(rideRuns: true, inFront: true), "no arrival")
        opening.arrived()
        XCTAssertFalse(opening.decide(rideRuns: false, inFront: true), "no ride")
        opening.arrived()
        XCTAssertFalse(opening.decide(rideRuns: true, inFront: false), "another tab, a sheet or the splash")
        opening.scheduleBusy = true
        opening.arrived()
        XCTAssertFalse(opening.decide(rideRuns: true, inFront: true), "the station picker or a sheet of Schedule's")
        opening.scheduleBusy = false
        opening.arrived()
        opening.touched()
        XCTAssertFalse(opening.decide(rideRuns: true, inFront: true), "a touch on Schedule meanwhile")
        opening.arrived()
        XCTAssertTrue(opening.decide(rideRuns: true, inFront: true), "a touch counts for its own arrival only")
    }

    func testATouchBeforeTheArrivalDoesNotCount() {
        let opening = RideOpening()
        opening.touched()
        opening.arrived()
        XCTAssertTrue(opening.decide(rideRuns: true, inFront: true))
    }

    // MARK: auto_opens

    func testAutoOpensCountsTheOpensTheAppMade() async throws {
        let rig = await DemoRideRig.started()
        let engine = try XCTUnwrap(rig.engine)
        rig.onBoard.screen.opensByItself(engine)
        rig.onBoard.screen.opened(engine)
        rig.onBoard.screen.closed()
        rig.onBoard.screen.opened(engine)
        XCTAssertEqual(engine.watch.opens, 2)
        XCTAssertEqual(engine.watch.autoOpens, 1)
        XCTAssertEqual(AnalyticsEvent.rideEnded(.arrived, opens: 2, autoOpens: 1).properties["auto_opens"], .int(1))
        XCTAssertEqual(AnalyticsEvent.rideEnded(.byRider).properties["auto_opens"], .int(0))
    }
}
