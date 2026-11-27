import XCTest
@testable import TrainTimes

/// The wrong train warning in the app (TT-250, D127): Settings › Testing's demo ride raising it, the ride's ending as
/// `wrong_train`, the route "Trains from …" shows, the ride screen's words and Schedule's strip.
@MainActor
final class WrongTrainDemoTests: XCTestCase {
    private let formatter = TimeFormatter(format: .twelveHour)

    override func tearDown() async throws {
        Analytics.tracker = nil
        try await super.tearDown()
    }

    /// An OnBoard with the demo ride on `DemoRideRig.day` and the rig's presenter; `moments` collects what each demo ride
    /// was started from.
    @MainActor
    private final class DemoRig {
        let wrong = WrongTrainRig()
        let clock = TestClock(now: DemoRideRig.time(17, 13))
        var moments: [Date?] = []
        var engines: [RideEngine] = []
        private var made: OnBoard?
        var onBoard: OnBoard { made! }

        init(delay: Duration = .milliseconds(20)) {
            let day = DemoRideRig.day
            let clock = self.clock
            let made = OnBoard(
                app: nil,
                makeDemo: { [unowned self] moment in
                    self.moments.append(moment)
                    let engine = DemoRide.engine(on: day, clock: clock, tickInterval: nil)
                    self.engines.append(engine)
                    return (engine: engine, ride: DemoRide.ride(on: day))
                },
                haptics: FakeHaptics(),
                wrongTrain: wrong.presenter,
                wrongTrainDelay: delay
            )
            self.made = made
            wrong.active.isActive = true
            wrong.presenter.endRide = { [weak made] ride in made?.endWrongTrain(ride) ?? false }
        }

        func waitForWarning() async {
            for _ in 0..<200 where wrong.presenter.warning == nil {
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    // MARK: The demo

    func testWithTheSwitchOnTheDemoRideStartsAt513AndWarnsAfterTheDelay() async throws {
        let rig = DemoRig()
        await rig.onBoard.setDemo(true, wrongTrain: true)

        let moment = try XCTUnwrap(rig.moments.first ?? nil)
        XCTAssertEqual(moment, ServiceDay(calendarDayContaining: moment).gtfsTime(17 * 3600 + 13 * 60), "From Union at 5:13 PM")
        XCTAssertNil(rig.wrong.presenter.warning, "Not at once")

        await rig.waitForWarning()
        await WrongTrainFixtures.settle()
        let warning = try XCTUnwrap(rig.wrong.presenter.warning)
        XCTAssertEqual(warning.ride, DemoRide.ride(on: DemoRideRig.day))
        XCTAssertEqual(warning.reason, .skipsStop)
        XCTAssertEqual(warning.evidence, .feed)
        XCTAssertEqual(warning.source, .onBoard)
        XCTAssertEqual(warning.reasonLine, "Doesn’t stop at Clarkson")
        XCTAssertEqual(warning.nextStopId, "OA")
        XCTAssertEqual(warning.nextStopTime, DemoRideRig.time(17, 35))
        XCTAssertEqual(warning.expires, DemoRideRig.time(17, 37))
        XCTAssertEqual(warning.secondsAfter, 0)
        XCTAssertTrue(warning.isDemo)
        XCTAssertEqual(rig.wrong.haptics.played, [.alarm])
    }

    func testWithTheSwitchOffTheDemoRideStartsAt532AndNeverWarns() async throws {
        let rig = DemoRig()
        await rig.onBoard.setDemo(true, wrongTrain: false)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(rig.moments.count, 1)
        XCTAssertNil(rig.moments.first ?? nil, "From 5:32 PM, as before")
        XCTAssertNil(rig.wrong.presenter.warning)
    }

    func testTurningTheSwitchOnWhileTheDemoPlaysStartsTheRideAgain() async throws {
        let rig = DemoRig()
        await rig.onBoard.setDemo(true, wrongTrain: false)
        await rig.onBoard.setDemo(true, wrongTrain: true)
        XCTAssertEqual(rig.moments.count, 2)
        XCTAssertEqual(rig.engines.first?.state?.phase, .ended, "The running ride ends")
        XCTAssertTrue(rig.onBoard.engine === rig.engines.last)

        await rig.onBoard.setDemo(true, wrongTrain: true)
        XCTAssertEqual(rig.moments.count, 2, "Nothing changed: it plays on")
    }

    func testTheDemoTurnedOffTakesTheWarningAway() async throws {
        let recorder = RecordingAnalytics.install()
        let rig = DemoRig()
        await rig.onBoard.setDemo(true, wrongTrain: true)
        await rig.waitForWarning()
        XCTAssertNotNil(rig.wrong.presenter.warning)

        await rig.onBoard.setDemo(false)

        XCTAssertNil(rig.wrong.presenter.warning)
        XCTAssertEqual(
            recorder.events.first { $0.name == "wrong_train_answered" }?.properties["answer"], .string("withdrawn")
        )
    }

    func testTheDemoTurnedOffBeforeTheDelayRaisesNothing() async throws {
        let rig = DemoRig(delay: .milliseconds(100))
        await rig.onBoard.setDemo(true, wrongTrain: true)
        await rig.onBoard.setDemo(false)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(rig.wrong.presenter.warning)
    }

    func testTrainsFromOakvilleEndsTheDemoRideAndClosesTheSheet() async throws {
        let rig = DemoRig()
        await rig.onBoard.setDemo(true, wrongTrain: true)
        await rig.waitForWarning()
        let key = DemoRide.ride(on: DemoRideRig.day).tripKey

        rig.onBoard.wrongTrainTrains()

        XCTAssertEqual(rig.onBoard.engine?.state?.endReason, .wrongTrain)
        XCTAssertNil(rig.onBoard.activeRide)
        XCTAssertTrue(rig.onBoard.endedUndone(key), "RootView closes the sheet")
        XCTAssertEqual(rig.wrong.presenter.routeRequest?.nextStopId, "OA")
        XCTAssertEqual(rig.wrong.presenter.routeRequest?.stopId, "CL")
        XCTAssertEqual(rig.wrong.presenter.routeRequest?.originId, "UN")
    }

    func testEndRideWhileItShowsCountsAsEndRide() async throws {
        let recorder = RecordingAnalytics.install()
        let rig = DemoRig()
        await rig.onBoard.setDemo(true, wrongTrain: true)
        await rig.waitForWarning()

        rig.onBoard.end()

        XCTAssertNil(rig.wrong.presenter.warning)
        XCTAssertEqual(
            recorder.events.first { $0.name == "wrong_train_answered" }?.properties["answer"], .string("end_ride")
        )
    }

    // MARK: The engine

    func testTheWrongTrainEndingDeclinesTheTrainTodayAndCountsAsUndone() async throws {
        let defaults = UserDefaults.ephemeral()
        let engine = RideEngine(
            data: FakeRideData(plan: try OnBoardFixtures.plan()), location: FakeLocation(authorized: true),
            clock: TestClock(now: WrongTrainFixtures.now), defaults: defaults, tickInterval: nil
        )
        let onBoard = OnBoard(app: engine)
        let started = await engine.start(OnBoardFixtures.ride)
        XCTAssertTrue(started)

        XCTAssertTrue(onBoard.endWrongTrain(OnBoardFixtures.ride))

        XCTAssertEqual(engine.state?.endReason, .wrongTrain)
        XCTAssertTrue(DepartureQuestion.isDeclined(OnBoardFixtures.ride.tripKey, in: defaults), "Not asked about again today")
        XCTAssertTrue(onBoard.endedUndone(OnBoardFixtures.ride.tripKey))
        XCTAssertFalse(onBoard.endWrongTrain(OnBoardFixtures.ride), "Once")
    }

    // MARK: The route

    private struct Stations: StationRepository {
        func stations() async throws -> [Station] {
            [Station(id: "CL", name: "Clarkson GO"), Station(id: "OA", name: "Oakville GO"), Station(id: "UN", name: "Union Station GO")]
        }

        func route(from: Station, to: Station) async throws -> Route { Route(from: from, to: to, line: DemoRide.line) }
    }

    /// Trains from Oakville to Clarkson leaving at `departures`; none anywhere else.
    private struct Trains: ScheduleRepository {
        let departures: [Date]

        func trips(for route: Route, on day: ServiceDay) async throws -> [Trip] {
            guard route.from.id == "OA", route.to.id == "CL" else { return [] }
            return departures.enumerated().map { index, time in
                Trip(
                    key: TripKey(serviceDay: day, tripId: "OA-CL-\(index)"), scheduledDeparture: time,
                    scheduledArrival: time.addingTimeInterval(480), platform: .pending, tags: []
                )
            }
        }

        func liveStatus(for route: Route, on day: ServiceDay) async throws -> LiveSnapshot { .empty }
        func lineNotices(for line: Line) async throws -> [LineNotice] { [] }
    }

    private let request = WrongTrainRouteRequest(nextStopId: "OA", stopId: "CL", originId: "UN")

    func testATrainStillToLeaveTodayGoesFromTheNextStopToYourStop() async throws {
        let now = DemoRideRig.time(17, 40)
        let route = await WrongTrainRoute.route(
            for: request, stations: Stations(), repository: Trains(departures: [DemoRideRig.time(17, 20), DemoRideRig.time(18, 5)]),
            now: now
        )
        XCTAssertEqual(route?.from.id, "OA")
        XCTAssertEqual(route?.to.id, "CL")
    }

    func testWithNoTrainLeftItGoesBackToWhereYouGotOn() async throws {
        let now = DemoRideRig.time(23, 50)
        let route = await WrongTrainRoute.route(
            for: request, stations: Stations(), repository: Trains(departures: [DemoRideRig.time(17, 20)]), now: now
        )
        XCTAssertEqual(route?.from.id, "OA")
        XCTAssertEqual(route?.to.id, "UN")
    }

    // MARK: The screens

    func testTheRideScreenShowsTheWarningForItsRideOnly() async throws {
        let rig = DemoRig()
        await rig.onBoard.setDemo(true, wrongTrain: true)
        let key = DemoRide.ride(on: DemoRideRig.day).tripKey
        XCTAssertNil(rig.onBoard.details(for: key, formatter: formatter)?.wrongTrain)

        await rig.waitForWarning()
        let wrong = try XCTUnwrap(rig.onBoard.details(for: key, formatter: formatter)?.wrongTrain)
        XCTAssertEqual(wrong.reason, "Doesn’t stop at Clarkson")
        XCTAssertEqual(wrong.next, "Next stop Oakville · 5:35 PM")
        XCTAssertEqual(wrong.nextStop, "Oakville")
        XCTAssertEqual(wrong.trains, "Trains from Oakville")

        rig.onBoard.wrongTrainFine()
        XCTAssertNil(rig.onBoard.details(for: key, formatter: formatter)?.wrongTrain, "I’m fine: the ride's own screen")
    }

    func testAnotherRidesWarningIsNotDrawnOnThisRide() async throws {
        let rig = DemoRig()
        await rig.onBoard.setDemo(true, wrongTrain: false)
        await rig.wrong.presenter.raise(WrongTrainFixtures.warning(), now: WrongTrainFixtures.now)?.value
        let key = DemoRide.ride(on: DemoRideRig.day).tripKey
        XCTAssertNotNil(rig.onBoard.details(for: key, formatter: formatter))
        XCTAssertNil(rig.onBoard.details(for: key, formatter: formatter)?.wrongTrain)
    }

    func testScheduleShowsTheWarningFirst() async throws {
        XCTAssertEqual(RideStripContent(warnsWrongTrain: true, isRiding: true, asksDeparture: true), .wrongTrain)
        XCTAssertEqual(RideStripContent(warnsWrongTrain: false, isRiding: true), .riding)

        let rig = DemoRig()
        await rig.onBoard.setDemo(true, wrongTrain: true)
        XCTAssertEqual(RideStripContent(rig.onBoard), .riding)
        await rig.waitForWarning()
        XCTAssertEqual(RideStripContent(rig.onBoard), .wrongTrain)
    }

    func testTheButtonsPlayTap() async throws {
        let rig = DemoRig()
        await rig.onBoard.setDemo(true, wrongTrain: true)
        await rig.waitForWarning()
        let haptics = FakeHaptics()
        let model = TripDetailsViewModel(
            route: DemoRide.route, key: DemoRide.ride(on: DemoRideRig.day).tripKey,
            repository: StubScheduleRepository(tripList: [], live: .empty, stopList: []),
            clock: rig.clock, onBoard: rig.onBoard, haptics: haptics
        )

        model.wrongTrainFine()

        XCTAssertEqual(haptics.played, [.tap])
        XCTAssertNil(rig.wrong.presenter.warning)
        model.wrongTrainFine()
        XCTAssertEqual(haptics.played, [.tap], "Nothing to answer")
    }
}
