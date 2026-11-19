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

    /// TT-230: the question sends `detection_asked` once, with where it was asked and what made the matcher sure.
    func testAskingSendsDetectionAsked() async throws {
        let recorder = RecordingAnalytics.install()
        defer { Analytics.tracker = nil }
        let clock = startClock()
        let location = FakeLocation(authorized: true)
        let detector = makeDetector(location: location, clock: clock, defaults: nil, askedWhere: "app")
        _ = await detector.start(on: DemoRide.route)

        await ride(detector, location: location, clock: clock)
        await detector.tick()

        XCTAssertTrue(detector.isAsking)
        XCTAssertEqual(recorder.events, [.detectionAsked(where: "app", evidence: "stops")])
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

    // MARK: A turned route (TT-234, D116)

    /// Automatic direction turns the route round under the matcher: the same two stations the other way keep the matcher,
    /// its question and its trains, also after the screen went and came back; the new route is the one it loads next.
    func testARouteTurnedRoundKeepsTheMatcher() async throws {
        let clock = startClock()
        let location = FakeLocation(authorized: true)
        let candidates = CountingCandidates(train: DemoRide.candidate(on: day))
        let detector = makeDetector(location: location, clock: clock, defaults: nil, candidates: candidates)
        _ = await detector.start(on: DemoRide.route)
        await ride(detector, location: location, clock: clock)
        guard case .asking(let question) = detector.state else { return XCTFail("The detector asks after two shared stops") }
        let loaded = await candidates.routes

        let turned = Route(from: DemoRide.route.to, to: DemoRide.route.from, line: DemoRide.route.line)
        let started = await detector.start(on: turned)

        XCTAssertTrue(started)
        XCTAssertEqual(detector.state, .asking(question), "The question stays through the turn")
        XCTAssertTrue(location.isUpdating)
        let afterTurn = await candidates.routes
        XCTAssertEqual(afterTurn, loaded, "The matcher keeps its trains: nothing is loaded again")

        // The screen goes and comes back, the route turned again meanwhile.
        detector.stop()
        _ = await detector.start(on: DemoRide.route)
        XCTAssertEqual(detector.state, .asking(question))
        _ = await detector.start(on: turned)

        // The next minute's trains are loaded for the route as it is now.
        clock.advance(seconds: TrainDetector.candidatesInterval)
        await detector.tick()
        let afterAMinute = await candidates.routes
        XCTAssertEqual(afterAMinute.count, loaded.count + 1)
        XCTAssertEqual(afterAMinute.last, turned)
    }

    /// Another pair of stations starts the matcher again: the question goes and the trains are loaded for the new route.
    func testAnotherPairOfStationsStartsTheMatcherAgain() async throws {
        let clock = startClock()
        let location = FakeLocation(authorized: true)
        let candidates = CountingCandidates(train: DemoRide.candidate(on: day))
        let detector = makeDetector(location: location, clock: clock, defaults: nil, candidates: candidates)
        _ = await detector.start(on: DemoRide.route)
        await ride(detector, location: location, clock: clock)
        XCTAssertTrue(detector.isAsking)
        let loaded = await candidates.routes

        let other = Route(from: DemoRide.route.from, to: Station(id: "OA", name: "Oakville GO"), line: DemoRide.line)
        _ = await detector.start(on: other)

        XCTAssertEqual(detector.state, .idle)
        let afterwards = await candidates.routes
        XCTAssertEqual(afterwards.count, loaded.count + 1)
        XCTAssertEqual(afterwards.last, other)
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
        // From the moment the question was asked on its clock, not from 5:32 PM.
        XCTAssertEqual(rideClock.now, question.askedAt)
        XCTAssertEqual(onBoard.activeRide?.tripId, DemoRide.tripId)
        XCTAssertNil(onBoard.demoDetector)
        XCTAssertEqual(onBoard.detection, .idle)
    }

    /// The ride's Live Activity (TT-174) follows the demo engine the question's Yes starts, and lets it go when Demo trains
    /// › Ride is turned off.
    func testTheLiveActivityFollowsTheDemoRideFromYes() async throws {
        let day = self.day
        let clock = startClock()
        let activity = FollowingSpy()
        let onBoard = OnBoard(
            app: nil,
            liveActivity: activity,
            makeDemo: { moment in
                let rideClock = TestClock(now: moment ?? day.gtfsTime(DemoRide.startSeconds))
                return (engine: DemoRide.engine(on: day, clock: rideClock, tickInterval: nil), ride: DemoRide.ride(on: day))
            },
            makeDemoDetector: { DemoRide.detector(on: day, clock: clock, tickInterval: nil) }
        )
        await onBoard.setDemo(true)
        try await askDemo(onBoard, clock: clock)
        XCTAssertTrue(activity.followed.isEmpty, "Nothing to follow while the question waits")
        guard case .asking(let question) = onBoard.detection else { return XCTFail("The demo asks on Schedule") }

        await onBoard.accept(try XCTUnwrap(question.trains.first))
        let engine = try XCTUnwrap(onBoard.demo)
        XCTAssertEqual(activity.followed.count, 1)
        XCTAssertTrue(activity.followed.first! === engine)

        await onBoard.setDemo(false)
        XCTAssertEqual(activity.followed.count, 2)
        XCTAssertNil(activity.followed.last!, "Back to the app's engine")
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

    /// A detector on the demo train, placed by GO's train feed, against a phone the test moves. `candidates`: the trains
    /// it loads, the demo's one train by default.
    private func makeDetector(
        location: FakeLocation, clock: TestClock, defaults: UserDefaults?, askedWhere: String? = nil,
        candidates: (any TrainCandidatesProviding)? = nil
    ) -> TrainDetector {
        TrainDetector(
            candidates: candidates ?? DemoCandidates(train: DemoRide.candidate(on: day)),
            location: location,
            trains: DemoTrainPositions(plan: DemoRide.plan(on: day), clock: clock),
            clock: clock,
            defaults: defaults,
            tickInterval: nil,
            feedInterval: 0,
            askedWhere: askedWhere
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

/// The demo's one train, keeping the route of each load.
private actor CountingCandidates: TrainCandidatesProviding {
    private let train: TrainCandidate
    private(set) var routes: [Route] = []

    init(train: TrainCandidate) {
        self.train = train
    }

    func candidates(on route: Route, at time: Date) async -> [TrainCandidate] {
        routes.append(route)
        return [train]
    }
}

/// Records what the Live Activity was told to follow.
@MainActor
private final class FollowingSpy: RideActivityFollowing {
    private(set) var followed: [RideEngine?] = []

    func follow(demo engine: RideEngine?) {
        followed.append(engine)
    }
}
