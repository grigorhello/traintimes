import XCTest
@testable import TrainTimes

/// TT-242 (D120): Settings › Testing › Demo trains › Depart › Automatic ride, on the demo departure's clock moved by hand:
/// Boards starts the ride by itself, Stays is not on board, No feed cannot tell; and On board runs the demo watch only
/// while the demo departure plays.
@MainActor
final class AutoRideDemoTests: XCTestCase {
    private let day = OnBoardFixtures.friday

    private final class Box {
        var started = 0
    }

    private struct Rig {
        let watch: AutoRideWatch
        let location: DemoAutoRideLocation
        let clock: TestClock
        let session: DemoDeparture.Session
        let box: Box
    }

    private func rig(_ mode: DemoAutoRide) -> Rig {
        let clock = TestClock(now: day.gtfsTime(DemoDeparture.startSeconds))
        let session = DemoDeparture.Session(day: day, clock: clock)
        let location = DemoAutoRideLocation(session: session, mode: mode, interval: nil)
        let box = Box()
        let watch = AutoRideDemo.watch(
            session: session, mode: mode, location: location, lookInterval: nil,
            start: { _ in
                box.started += 1
                return true
            },
            rideRuns: { box.started > 0 }
        )
        return Rig(watch: watch, location: location, clock: clock, session: session, box: box)
    }

    /// Arms at 5:01 PM and plays the demo to 5:26 PM: a fix every 2 s and a look every 15 s on its clock, until the watch
    /// watches nothing.
    private func play(_ rig: Rig) async throws {
        let candidate = try XCTUnwrap(AutoRideDemo.candidate(rig.session, at: rig.clock.now))
        rig.watch.watchDemo(candidate, plan: AutoRideDemo.plan(on: day))
        XCTAssertNotNil(rig.watch.watched)
        let start = day.gtfsTime(DemoDeparture.startSeconds)
        for second in stride(from: 0, through: DemoDeparture.endSeconds - DemoDeparture.startSeconds, by: 1) {
            rig.clock.set(start.addingTimeInterval(TimeInterval(second)))
            if second % 2 == 0 { rig.location.tick() }
            if second % 15 == 0 { await rig.watch.look() }
            for _ in 0..<5 { await Task.yield() }
            if rig.watch.watched == nil { return }
        }
    }

    /// The demo train leaves Union at 5:16 PM, 3 min late, and the watch's plan says so.
    func testTheDemoTrainLeavesThreeMinutesLate() {
        let plan = AutoRideDemo.plan(on: day)
        XCTAssertEqual(plan.stops.first?.departure, day.gtfsTime(17 * 3600 + 16 * 60))
        XCTAssertEqual(plan.stops.last?.arrival, day.gtfsTime(17 * 3600 + 46 * 60))
        XCTAssertNotNil(plan.track)
    }

    func testBoardsStartsTheRideByItself() async throws {
        let recorder = RecordingAnalytics.install()
        defer { Analytics.tracker = nil }
        let rig = rig(.boards)
        try await play(rig)
        XCTAssertEqual(rig.box.started, 1)
        let check = try XCTUnwrap(rig.watch.lastCheck)
        XCTAssertEqual(check.outcome, .started)
        let seconds = try XCTUnwrap(check.secondsAfter)
        XCTAssertTrue((45...150).contains(seconds), "\(seconds) s after 5:16 PM")
        let started = try XCTUnwrap(recorder.events.first { $0.name == "ride_started" })
        XCTAssertEqual(started.properties["source"], .string("auto"))
        XCTAssertEqual(started.properties["demo"], .bool(true))
        XCTAssertFalse(rig.location.isUpdating, "The demo phone stops with its watch; the demo ride rides on its own")
    }

    func testStaysIsNotOnBoard() async throws {
        let rig = rig(.stays)
        try await play(rig)
        XCTAssertEqual(rig.box.started, 0)
        XCTAssertEqual(rig.watch.lastCheck?.outcome, .notOnBoard)
    }

    func testNoFeedCannotTell() async throws {
        let rig = rig(.noFeed)
        try await play(rig)
        XCTAssertEqual(rig.box.started, 0)
        XCTAssertEqual(rig.watch.lastCheck?.outcome, .unsure)
        XCTAssertEqual(rig.watch.lastCheck?.reason, .noFeed)
        XCTAssertEqual(rig.watch.lastCheck?.secondsAfter, 180, "It could not tell at 5:19 PM")
    }

    /// No fix while the demo phone is under Union's shed; Stays sends a stationary fix at the platform.
    func testTheDemoPhone() {
        let clock = TestClock(now: day.gtfsTime(17 * 3600 + 16 * 60 + 10))
        let session = DemoDeparture.Session(day: day, clock: clock)
        XCTAssertNil(DemoAutoRideLocation(session: session, mode: .boards, interval: nil).fix())
        XCTAssertEqual(DemoAutoRideLocation(session: session, mode: .stays, interval: nil).fix()?.isStationary, true)
        clock.set(day.gtfsTime(17 * 3600 + 17 * 60))
        XCTAssertNotNil(DemoAutoRideLocation(session: session, mode: .noFeed, interval: nil).fix())
    }

    /// On board runs the demo watch only while the demo departure plays with a mode chosen, armed before its train leaves.
    func testOnBoardRunsTheDemoWatchWhileTheDemoDeparturePlays() {
        let clock = TestClock(now: day.gtfsTime(DemoDeparture.startSeconds))
        let session = DemoDeparture.Session(day: day, clock: clock)
        let onBoard = OnBoard(
            app: nil, makeDeparture: { session },
            makeAutoRideDemo: { session, mode, _ in
                AutoRideDemo.watch(
                    session: session, mode: mode, location: DemoAutoRideLocation(session: session, mode: mode, interval: nil),
                    lookInterval: nil, start: { _ in false }, rideRuns: { false }
                )
            }
        )
        onBoard.setDemoAutoRide(.boards)
        XCTAssertNil(onBoard.autoRideDemo, "No demo departure plays")
        onBoard.setDemoDeparture(true)
        XCTAssertNotNil(onBoard.autoRideDemo?.watched, "Armed at 5:01 PM")
        onBoard.setDemoAutoRide(.off)
        XCTAssertNil(onBoard.autoRideDemo)
        XCTAssertEqual(onBoard.autoRideCheck?.outcome, nil, "A demo watch turned off leaves no check")
        onBoard.setDemoAutoRide(.stays)
        XCTAssertNotNil(onBoard.autoRideDemo?.watched)
        onBoard.setDemoDeparture(false)
        XCTAssertNil(onBoard.autoRideDemo)
    }

    /// No on the demo's question: that train is not watched again this run, so the watch does not arm and end every second
    /// on the demo's next plays (each would send `auto_ride_checked`).
    func testADeclinedDemoTrainIsNotWatchedAgain() async throws {
        let clock = TestClock(now: day.gtfsTime(DemoDeparture.startSeconds))
        let session = DemoDeparture.Session(day: day, clock: clock)
        let onBoard = OnBoard(
            app: nil, makeDeparture: { session },
            makeAutoRideDemo: { session, mode, _ in
                AutoRideDemo.watch(
                    session: session, mode: mode, location: DemoAutoRideLocation(session: session, mode: mode, interval: nil),
                    lookInterval: nil, start: { _ in false }, rideRuns: { false }
                )
            }
        )
        onBoard.setDemoAutoRide(.stays)
        onBoard.setDemoDeparture(true)
        let watch = try XCTUnwrap(onBoard.autoRideDemo)
        XCTAssertNotNil(watch.watched)

        clock.set(day.gtfsTime(17 * 3600 + 17 * 60))
        let departure = try XCTUnwrap(session.departure(at: clock.now))
        let live = try XCTUnwrap(LiveDeparture(departure, now: clock.now))
        onBoard.updateDepartureAsk(live, route: session.route, isDemo: true)
        XCTAssertNotNil(onBoard.departureAsk)
        onBoard.declineDeparture()
        watch.stop()
        XCTAssertNil(watch.watched)

        // The demo's next play, from 5:01 PM.
        clock.set(day.gtfsTime(DemoDeparture.startSeconds + 60))
        onBoard.armAutoRideDemo()
        XCTAssertNil(watch.watched, "Declined this run: not watched again")
    }
}
