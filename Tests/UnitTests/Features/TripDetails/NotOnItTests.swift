import XCTest
@testable import TrainTimes

/// Not on it (TT-243, D120): the ride screen's button for the first 10 min of a ride that started by itself, the sheet's tap
/// on the demo ride (declined for the run, never counted) and on the app's (counted: two within 14 days turn Automatic ride
/// off), and the card's `undoable` in the Live Activity's JSON.
@MainActor
final class NotOnItTests: XCTestCase {
    private let formatter = TimeFormatter(format: .twelveHour)

    override func tearDown() async throws {
        Analytics.tracker = nil
        try await super.tearDown()
    }

    // MARK: The button

    func testARideThatStartedByItselfShowsNotOnItForTenMinutes() async throws {
        let rig = await DemoRideRig.autoStarted(at: DemoRideRig.time(17, 34))
        let details = try XCTUnwrap(rig.onBoard.details(for: rig.key, formatter: formatter))
        XCTAssertEqual(details.button, .notOnIt)
        XCTAssertEqual(details.button.title, "Not on it")

        rig.drive(to: DemoRideRig.time(17, 42, 5))
        XCTAssertEqual(rig.onBoard.details(for: rig.key, formatter: formatter)?.button, .end, "10 min after the start")
    }

    func testARideStartedByTheRiderShowsEndRide() async throws {
        let rig = await DemoRideRig.started(at: DemoRideRig.time(17, 33))
        XCTAssertEqual(rig.onBoard.details(for: rig.key, formatter: formatter)?.button, .end)
    }

    // MARK: The demo ride

    func testNotOnItOnTheDemoRideEndsItAndClosesTheSheetWithoutCounting() async throws {
        let recorder = RecordingAnalytics.install()
        let haptics = FakeHaptics()
        let rig = await DemoRideRig.autoStarted()
        let model = TripDetailsViewModel(
            route: DemoRide.route, key: rig.key, repository: StubScheduleRepository(tripList: [], live: .empty, stopList: []),
            clock: rig.clock, onBoard: rig.onBoard, haptics: haptics
        )
        XCTAssertTrue(model.isRiding)

        model.notOnIt()

        XCTAssertEqual(haptics.played, [.tap])
        XCTAssertEqual(rig.engine?.state?.endReason, .notOnIt)
        XCTAssertNil(rig.onBoard.activeRide)
        XCTAssertTrue(rig.onBoard.endedUndone(rig.key))
        XCTAssertTrue(model.rideWasUndone, "RootView closes the sheet")
        XCTAssertEqual(recorder.events.last?.properties["reason"], .string("not_on_it"))
        XCTAssertEqual(recorder.events.last?.properties["surface"], .string("ride"))

        model.notOnIt()
        XCTAssertEqual(haptics.played, [.tap], "Once")
    }

    func testTheDemoCardsNotOnItEndsTheDemoRide() async throws {
        let recorder = RecordingAnalytics.install()
        let rig = await DemoRideRig.autoStarted()
        rig.onBoard.demoCardNotOnIt(DemoRide.ride(on: DemoRideRig.day))
        XCTAssertEqual(rig.engine?.state?.endReason, .notOnIt)
        XCTAssertEqual(recorder.events.last?.properties["surface"], .string("card"))
    }

    // MARK: The app's ride

    private func appRide(at time: Date, store: AutoRideStore) async throws -> (onBoard: OnBoard, engine: RideEngine) {
        let engine = RideEngine(
            data: FakeRideData(plan: try OnBoardFixtures.plan()), location: FakeLocation(authorized: true),
            clock: TestClock(now: time), defaults: .ephemeral(), tickInterval: nil
        )
        let onBoard = OnBoard(app: engine, autoRideStore: store)
        let started = await engine.start(OnBoardFixtures.ride, source: .auto, asks: false)
        XCTAssertTrue(started)
        return (onBoard, engine)
    }

    func testTwoNotOnItWithinFourteenDaysTurnAutomaticRideOff() async throws {
        let recorder = RecordingAnalytics.install()
        let store = AutoRideStore(defaults: .ephemeral())
        let first = OnBoardFixtures.time(11, 18)

        let one = try await appRide(at: first, store: store)
        one.onBoard.notOnIt()
        XCTAssertEqual(one.engine.state?.endReason, .notOnIt)
        XCTAssertEqual(store.notOnIts, [first])
        XCTAssertFalse(store.isOff)

        let second = first.addingTimeInterval(13 * 24 * 3600)
        let two = try await appRide(at: second, store: store)
        two.onBoard.notOnIt()

        XCTAssertTrue(store.isOff)
        XCTAssertEqual(store.turnedOffAt, second)
        XCTAssertTrue(store.notOnIts.isEmpty)
        XCTAssertFalse(recorder.names.contains("setting_changed"), "Not the rider's own switch")
    }

    func testNotOnItFifteenDaysApartDoNotTurnItOff() {
        let store = AutoRideStore(defaults: .ephemeral())
        let first = OnBoardFixtures.time(11, 18)
        XCTAssertFalse(store.recordNotOnIt(at: first))
        XCTAssertFalse(store.recordNotOnIt(at: first.addingTimeInterval(15 * 24 * 3600)))
        XCTAssertFalse(store.isOff)
        XCTAssertEqual(store.notOnIts.count, 1, "The older one fell out of the 14 days")
    }

    func testTurningItOnAgainClearsTheCountAndTheNote() {
        let store = AutoRideStore(defaults: .ephemeral())
        let first = OnBoardFixtures.time(11, 18)
        store.recordNotOnIt(at: first)
        XCTAssertTrue(store.recordNotOnIt(at: first.addingTimeInterval(60)))

        store.turnOn()

        XCTAssertFalse(store.isOff)
        XCTAssertNil(store.turnedOffAt)
        XCTAssertTrue(store.notOnIts.isEmpty)
    }

    func testARideStartedByTheRiderHasNoNotOnIt() async throws {
        let store = AutoRideStore(defaults: .ephemeral())
        let engine = RideEngine(
            data: FakeRideData(plan: try OnBoardFixtures.plan()), location: FakeLocation(authorized: true),
            clock: TestClock(now: OnBoardFixtures.time(11, 18)), defaults: .ephemeral(), tickInterval: nil
        )
        let onBoard = OnBoard(app: engine, autoRideStore: store)
        let started = await engine.start(OnBoardFixtures.ride, source: .onBoard)
        XCTAssertTrue(started)

        onBoard.notOnIt()

        XCTAssertNotEqual(engine.state?.phase, .ended)
        XCTAssertTrue(store.notOnIts.isEmpty)
    }

    // MARK: The card

    func testTheCardsUndoableIsLeftOutOfItsJSONWhenFalse() async throws {
        let rig = await DemoRideRig.autoStarted()
        let engine = try XCTUnwrap(rig.engine)
        var state = try XCTUnwrap(RideActivityAttributes.ContentState(
            plan: rig.plan, state: try XCTUnwrap(engine.state), now: engine.now, deviceNow: engine.now, formatter: formatter
        ))
        XCTAssertFalse(state.undoable)
        let plain = try XCTUnwrap(JSONSerialization.jsonObject(with: try JSONEncoder().encode(state)) as? [String: Any])
        XCTAssertNil(plain["undoable"], "Older builds and the server's own JSON leave it out")

        state.undoable = true
        let data = try JSONEncoder().encode(state)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["undoable"] as? Bool, true)
        XCTAssertTrue(try JSONDecoder().decode(RideActivityAttributes.ContentState.self, from: data).undoable)

        let decoded = try JSONDecoder().decode(
            RideActivityAttributes.ContentState.self, from: try JSONSerialization.data(withJSONObject: plain)
        )
        XCTAssertFalse(decoded.undoable)
    }
}
