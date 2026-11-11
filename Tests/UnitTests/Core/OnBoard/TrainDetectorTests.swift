import XCTest
@testable import TrainTimes

/// Train detection in the app (TT-175): it watches only with location already allowed and never asks for it, a No is kept
/// for the day, and only a Yes starts a ride. The demo's question (Demo trains › Ride) comes before its ride.
@MainActor
final class TrainDetectorTests: XCTestCase {
    private let day = OnBoardFixtures.friday

    func testNeverAsksForLocation() async {
        let location = FakeLocation(authorized: false)
        let detector = makeDetector(location: location, clock: startClock(), defaults: nil)

        await detector.run(on: DemoRide.route)
        let started = await detector.start(on: DemoRide.route)

        XCTAssertFalse(started)
        XCTAssertEqual(location.requests, 0)
        XCTAssertFalse(location.isUpdating)
        XCTAssertEqual(detector.state, .idle)
    }

    func testAsksAboutTheTrainThePhoneRides() async throws {
        let clock = startClock()
        let location = FakeLocation(authorized: true)
        let detector = makeDetector(location: location, clock: clock, defaults: nil)
        let started = await detector.start(on: DemoRide.route)
        XCTAssertTrue(started)
        XCTAssertTrue(location.isUpdating)

        await ride(detector, location: location, clock: clock)

        guard case .asking(let question) = detector.state else { return XCTFail("The detector asks after two shared stops") }
        XCTAssertEqual(question.trains.map(\.trip), [DemoRide.ride(on: day).tripKey])
        XCTAssertEqual(question.stops.map(\.id), ["EX", "MI"])
        XCTAssertLessThan(clock.now, day.gtfsTime(17 * 3600 + 27 * 60))
        // The screen goes: the phone's updates stop, and the question stays for the rider.
        detector.stop()
        XCTAssertFalse(location.isUpdating)
        XCTAssertTrue(detector.isAsking)
        XCTAssertEqual(location.requests, 0)
    }

    func testNoIsKeptForTheDay() async throws {
        let defaults = UserDefaults.ephemeral()
        let clock = startClock()
        let location = FakeLocation(authorized: true)
        let first = makeDetector(location: location, clock: clock, defaults: defaults)
        _ = await first.start(on: DemoRide.route)
        await ride(first, location: location, clock: clock)
        XCTAssertTrue(first.isAsking)

        first.decline()

        let key = DemoRide.ride(on: day).tripKey
        XCTAssertEqual(first.state, .idle)
        XCTAssertEqual(makeDetector(location: location, clock: clock, defaults: defaults).silenced, [key])
        clock.advance(seconds: 24 * 3600)
        XCTAssertEqual(makeDetector(location: location, clock: clock, defaults: defaults).silenced, [])
    }

    // MARK: The demo through On board

    func testDemoAsksBeforeTheRideAndYesStartsIt() async throws {
        let day = self.day
        let clock = startClock()
        // The ride's clock, set where the demo ride starts.
        let rideClock = TestClock(now: .distantPast)
        let onBoard = OnBoard(
            app: nil,
            makeDemo: { moment in
                rideClock.set(moment ?? day.gtfsTime(DemoRide.startSeconds))
                return (engine: DemoRide.engine(on: day, clock: rideClock, tickInterval: nil), ride: DemoRide.ride(on: day))
            },
            makeDemoDetector: { DemoRide.detector(on: day, clock: clock, tickInterval: nil) }
        )
        await onBoard.setDemo(true)
        XCTAssertNil(onBoard.activeRide)
        try await askDemo(onBoard, clock: clock)

        guard case .asking(let question) = onBoard.detection else { return XCTFail("The demo asks on Schedule") }
        XCTAssertEqual(question.trains.first?.departure, day.gtfsTime(17 * 3600 + 13 * 60))
        // Asked, and still no ride until the tap.
        XCTAssertNil(onBoard.activeRide)

        let started = await onBoard.accept(try XCTUnwrap(question.trains.first))

        XCTAssertTrue(started)
        // From the moment of the Yes on the question's clock, not from 5:32 PM.
        XCTAssertEqual(rideClock.now, clock.now)
        XCTAssertEqual(onBoard.activeRide?.tripId, DemoRide.tripId)
        XCTAssertNil(onBoard.demoDetector)
        XCTAssertEqual(onBoard.detection, .idle)
    }

    func testDemoNoSilencesTheTrain() async throws {
        let day = self.day
        let clock = startClock()
        let onBoard = OnBoard(app: nil, makeDemoDetector: { DemoRide.detector(on: day, clock: clock, tickInterval: nil) })
        await onBoard.setDemo(true)
        let detector = try await askDemo(onBoard, clock: clock)

        onBoard.decline()

        XCTAssertEqual(onBoard.detection, .idle)
        XCTAssertNil(onBoard.activeRide)
        XCTAssertEqual(detector.silenced, [DemoRide.ride(on: day).tripKey])
    }

    // MARK: Helpers

    /// 5:18:20 PM, where the demo's question starts.
    private func startClock() -> TestClock {
        TestClock(now: day.gtfsTime(DemoRide.detectStartSeconds))
    }

    /// A detector on the demo train, placed by GO's train feed, against a phone the test moves.
    private func makeDetector(location: FakeLocation, clock: TestClock, defaults: UserDefaults?) -> TrainDetector {
        TrainDetector(
            candidates: DemoCandidates(train: DemoRide.candidate(on: day)),
            location: location,
            trains: DemoTrainPositions(plan: DemoRide.plan(on: day), clock: clock),
            clock: clock,
            defaults: defaults,
            tickInterval: nil,
            feedInterval: 0
        )
    }

    /// The phone on the demo train, a fix each 5 s, until the question comes or 5:40 PM.
    private func ride(_ detector: TrainDetector, location: FakeLocation, clock: TestClock) async {
        let plan = DemoRide.plan(on: day)
        guard let shape = plan.track?.shape else { return XCTFail("The demo has a track") }
        while clock.now < day.gtfsTime(17 * 3600 + 40 * 60), !detector.isAsking {
            clock.advance(seconds: 5)
            await detector.tick()
            location.send(LocationFix(coordinate: shape.point(at: plan.scheduledAlong(at: clock.now)), horizontalAccuracy: 5))
        }
    }

    /// Schedule opens with the demo on: its detector is made (with no timer the run ends at once), then the test rides it to
    /// the question.
    @discardableResult
    private func askDemo(_ onBoard: OnBoard, clock: TestClock) async throws -> TrainDetector {
        await onBoard.detect(on: DemoRide.route, demo: true)
        let detector = try XCTUnwrap(onBoard.demoDetector)
        _ = await detector.start(on: DemoRide.route)
        let plan = DemoRide.plan(on: day)
        let shape = try XCTUnwrap(plan.track?.shape)
        while clock.now < day.gtfsTime(17 * 3600 + 40 * 60), !detector.isAsking {
            clock.advance(seconds: 5)
            await detector.tick()
            detector.receive(LocationFix(coordinate: shape.point(at: plan.scheduledAlong(at: clock.now)), horizontalAccuracy: 5))
        }
        return detector
    }
}
